# 🏗️ TMCP - Kiến Trúc Hệ Thống

> **TMCP (The Iron Commander)** — Hệ thống tự động hóa hạ tầng Kubernetes từ con số 0 trên máy local,
> sử dụng Terraform + K3s + ArgoCD + Vault theo mô hình **GitOps**.

---

## 📖 Mục Lục

1. [Tổng Quan Kiến Trúc](#1-tổng-quan-kiến-trúc)
2. [Sơ Đồ Kiến Trúc](#2-sơ-đồ-kiến-trúc)
3. [Luồng Khởi Tạo (Pipeline)](#3-luồng-khởi-tạo-pipeline)
4. [Thành Phần Chi Tiết](#4-thành-phần-chi-tiết)
5. [Cấu Trúc Repository](#5-cấu-trúc-repository)
6. [Bảo Mật](#6-bảo-mật)
7. [Luồng GitOps](#7-luồng-gitops)
8. [Công Nghệ Sử Dụng](#8-công-nghệ-sử-dụng)

---

## 1. Tổng Quan Kiến Trúc

Hệ thống TMCP triển khai **một cụm Kubernetes hoàn chỉnh** trên máy local (macOS) với:

| Lớp | Vai trò | Công cụ |
|-----|---------|---------|
| **Ảo hóa** | Tạo máy ảo Ubuntu trên Mac | Multipass |
| **Provisioning** | Tự động hóa toàn bộ hạ tầng | Terraform |
| **OS Hardening** | Bảo mật máy ảo ngay từ khi boot | Cloud-Init |
| **Container Orchestration** | Chạy workloads | K3s (lightweight K8s) |
| **GitOps Engine** | Tự động đồng bộ cấu hình từ Git | ArgoCD |
| **Secret Management** | Quản lý bí mật tập trung | HashiCorp Vault |
| **Secret Sync** | Đồng bộ secret từ Vault → K8s | External Secrets Operator (ESO) |
| **Application** | Dashboard ứng dụng | PocketBase |

**Triết lý thiết kế:** Chỉ cần chạy `terraform apply` — mọi thứ tự động từ A đến Z.

---

## 2. Sơ Đồ Kiến Trúc

```
┌─────────────────────────────────────────────────────────────────┐
│                        macOS (Host Machine)                     │
│                                                                 │
│  ┌──────────┐    ┌──────────────┐    ┌────────────────────┐     │
│  │ Terraform│───▶│   Multipass  │───▶│  VM: tmcp-prod     │     │
│  │ (IaC)    │    │ (Hypervisor) │    │  Ubuntu 24.04      │     │
│  └──────────┘    └──────────────┘    │  2 CPU | 4GB | 20G │     │
│       │                              │                    │     │
│       │ SSH (RSA 4096)               │  ┌──────────────┐  │     │
│       └─────────────────────────────▶│  │     K3s      │  │     │
│                                      │  │  (Kubernetes)│  │     │
│  ┌──────────┐   kubeconfig (SCP)     │  └──────┬───────┘  │     │
│  │ kubectl  │◀───────────────────────│         │          │     │
│  │ (Mac)    │                        │         ▼          │     │
│  └──────────┘                        │  ┌──────────────┐  │     │
│                                      │  │   ArgoCD     │  │     │
│                                      │  │ (GitOps CD)  │  │     │
│                                      │  └──────┬───────┘  │     │
│                                      │         │ sync     │     │
│                                      │         ▼          │     │
│                                      │  ┌──────────────┐  │     │
│                                      │  │ Vault + ESO  │  │     │
│                                      │  │ (Secrets)    │  │     │
│                                      │  └──────────────┘  │     │
│                                      │         │          │     │
│                                      │         ▼          │     │
│                                      │  ┌──────────────┐  │     │
│                                      │  │ PocketBase   │  │     │
│                                      │  │ (Dashboard)  │  │     │
│                                      │  └──────────────┘  │     │
│                                      └────────────────────┘     │
└─────────────────────────────────────────────────────────────────┘
                               │ sync
                               ▼
                    ┌─────────────────────┐
                    │   GitHub Repository  │
                    │  lupca/tmcp-gitops   │
                    │  (Source of Truth)   │
                    └─────────────────────┘
```

---

## 3. Luồng Khởi Tạo (Pipeline)

Toàn bộ hạ tầng được dựng theo **7 giai đoạn tuần tự**, mỗi giai đoạn phụ thuộc giai đoạn trước:

```
terraform apply
    │
    ▼
┌──────────────────────────────────────────────────────────────┐
│ GIAI ĐOẠN 1: Tạo SSH Key                                    │
│ ─────────────────────────────────────────────────────────     │
│ • Terraform tự sinh cặp SSH Key RSA-4096                     │
│ • Private key → lưu local (tmcp_rsa, chmod 0600)             │
│ • Public key  → nhúng vào cloud-init template                │
└──────────────────────┬───────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────────┐
│ GIAI ĐOẠN 2: Tạo VM                                         │
│ ─────────────────────────────────────────────────────────     │
│ • Multipass tạo VM Ubuntu 24.04 (2 CPU, 4GB RAM, 20GB disk)  │
│ • Cloud-init tự động chạy OS Hardening:                      │
│   - Cài curl, jq, ufw, fail2ban                             │
│   - Tắt PermitRootLogin, tắt PasswordAuthentication          │
│   - UFW: chỉ mở port 22, 80, 443, 6443                      │
│   - Fail2Ban: ban IP sau 3 lần login sai                     │
└──────────────────────┬───────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────────┐
│ GIAI ĐOẠN 3: Cài K3s qua SSH                                │
│ ─────────────────────────────────────────────────────────     │
│ • Terraform SSH vào VM bằng private key vừa tạo              │
│ • Chờ cloud-init chạy xong (cloud-init status --wait)        │
│ • Cài K3s (curl -sfL https://get.k3s.io | sh -)             │
│ • Copy kubeconfig về Mac qua SCP                             │
│ • Sửa IP trong kubeconfig: 127.0.0.1 → IP thật của VM       │
└──────────────────────┬───────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────────┐
│ GIAI ĐOẠN 4: Deploy ArgoCD                                   │
│ ─────────────────────────────────────────────────────────     │
│ • Tạo namespace "argocd"                                     │
│ • Apply manifest ArgoCD (dùng server-side apply vì >256KB)   │
│ • Chờ argocd-server Deployment ready                         │
│ • Chờ argocd-application-controller StatefulSet ready         │
└──────────────────────┬───────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────────┐
│ GIAI ĐOẠN 5: Dựng hạ tầng lõi (Vault + ESO)                 │
│ ─────────────────────────────────────────────────────────     │
│ • ArgoCD apply eso-application.yaml (External Secrets)       │
│ • ArgoCD apply vault-application.yaml (HashiCorp Vault)      │
│ • Chờ namespace "vault" xuất hiện                            │
│ • Chờ Pod Vault-0 xuất hiện                                  │
└──────────────────────┬───────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────────┐
│ GIAI ĐOẠN 6: Khởi tạo & Unseal Vault                        │
│ ─────────────────────────────────────────────────────────     │
│ • Kiểm tra trạng thái Vault (đã init hay chưa?)              │
│ • Nếu chưa init:                                             │
│   - vault operator init (3 key shares, threshold 3)          │
│   - Lưu unseal keys + root token ra file local               │
│   - Unseal bằng 3 key                                        │
│ • Nếu đã init:                                               │
│   - Đọc key từ file local, unseal lại                        │
│ • Chờ Vault pod Ready (1/1)                                  │
└──────────────────────┬───────────────────────────────────────┘
                       ▼
┌──────────────────────────────────────────────────────────────┐
│ GIAI ĐOẠN 7: Thả toàn bộ Workloads (App of Apps)            │
│ ─────────────────────────────────────────────────────────     │
│ • Tạo ArgoCD Root Application (tmcp-master)                  │
│ • Root App trỏ về repo: lupca/tmcp-gitops                    │
│ • ArgoCD tự scan toàn bộ YAML trong repo và deploy           │
│ • In mật khẩu admin ArgoCD                                   │
│ • ✅ HOÀN TẤT                                               │
└──────────────────────────────────────────────────────────────┘
```

---

## 4. Thành Phần Chi Tiết

### 4.1 Terraform (Provisioning Layer)

**File:** `tmcp-infra/main.tf`

| Provider | Vai trò |
|----------|---------|
| `larstobi/multipass` | Quản lý VM Multipass |
| `hashicorp/tls` | Tạo SSH key pair tự động |
| `hashicorp/local` | Ghi file ra local (cloud-init, key, root app) |

**Resources quan trọng:**

| Resource | Chức năng |
|----------|-----------|
| `tls_private_key.tmcp_ssh` | Sinh SSH key RSA-4096 |
| `multipass_instance.tmcp_server` | Tạo VM Ubuntu 24.04 |
| `null_resource.setup_k3s` | SSH vào VM, cài K3s, kéo kubeconfig |
| `null_resource.deploy_argocd` | Cài ArgoCD lên K3s |
| `null_resource.trigger_infra` | Deploy Vault + ESO qua ArgoCD |
| `null_resource.deploy_vault_unsealer` | Init + Unseal Vault tự động |
| `null_resource.trigger_workloads` | Apply Root Application |

### 4.2 Cloud-Init (OS Hardening)

**File:** `tmcp-infra/cloud-init.tftpl` (template) → render ra `cloud-init.yaml`

```
Cloud-Init thực hiện:
├── 📦 Cài đặt packages: curl, jq, ufw, fail2ban
├── 👤 Tạo user "ubuntu" với SSH public key từ Terraform
├── 🔒 SSH Hardening:
│   ├── PermitRootLogin no
│   └── PasswordAuthentication no
├── 🧱 Tường lửa UFW:
│   ├── Default: deny incoming, allow outgoing
│   ├── Mở: 22 (SSH), 80 (HTTP), 443 (HTTPS), 6443 (K8s API)
│   └── Cho phép mạng nội bộ K3s: 10.42.0.0/16
└── 🛡️ Fail2Ban:
    ├── Giám sát SSH login
    ├── maxretry: 3 lần
    └── bantime: 1 giờ
```

### 4.3 K3s (Kubernetes)

- **Lightweight Kubernetes** — phù hợp lab/edge/local dev
- Cài bằng script chính thức: `curl -sfL https://get.k3s.io | sh -`
- Kubeconfig được copy về Mac qua SCP, sửa IP để điều khiển từ xa
- Sử dụng: `export KUBECONFIG=~/.kube/tmcp_config`

### 4.4 ArgoCD (GitOps Engine)

- **Continuous Delivery** theo mô hình GitOps
- Tự động đồng bộ cấu hình từ GitHub repo → Kubernetes cluster
- Sử dụng **App of Apps Pattern**:

```
tmcp-master (Root Application)
    │
    │  sync từ: github.com/lupca/tmcp-gitops
    │
    ├── eso-application.yaml      → External Secrets Operator
    ├── vault-application.yaml    → HashiCorp Vault
    └── ... (các app khác)        → PocketBase, v.v.
```

**syncPolicy:**
- `automated: true` — tự động sync khi có thay đổi trên Git
- `prune: true` — xóa resource khi bị xóa khỏi Git
- `selfHeal: true` — tự sửa nếu có ai chỉnh tay trên cluster

### 4.5 HashiCorp Vault (Secret Management)

- Quản lý secrets tập trung (API keys, passwords, certificates...)
- Init với **3 unseal keys**, threshold = 3 (cần đủ 3 key để mở)
- Tự động init + unseal trong pipeline Terraform
- Kết hợp **External Secrets Operator (ESO)** để sync secrets vào K8s

```
Vault (source of truth)
    │
    │  ESO đồng bộ
    │
    ▼
K8s Secrets (auto-created)
    │
    │  mount vào
    │
    ▼
Pods (sử dụng secrets)
```

### 4.6 PocketBase (Application)

**File:** `pb.yaml`

- Dashboard/Backend dạng nhẹ
- Image: `lupca/tmcp-dashboard:v0.0.18`
- Port: 8090
- Có PersistentVolumeClaim 1Gi cho data
- Expose qua K8s Service (port 80 → 8090)

---

## 5. Cấu Trúc Repository

```
tmcp-workspace/
│
├── .gitignore                 # Bảo vệ file nhạy cảm
├── README.md                  # Giới thiệu project
├── ARCHITECTURE.md            # 📖 File này
├── init-cluster.sh            # Script thủ công (phiên bản đơn giản, trước Terraform)
├── pb.yaml                    # K8s manifest cho PocketBase
│
└── tmcp-infra/                # 🏗️ Terraform infrastructure
    ├── main.tf                # File chính — toàn bộ pipeline 7 giai đoạn
    ├── cloud-init.tftpl       # Template cloud-init (có biến ${ssh_public_key})
    ├── cloud-init.yaml        # ⚡ File rendered (auto-generated, có public key thật)
    ├── tmcp-root.yaml         # ⚡ ArgoCD Root Application (auto-generated)
    ├── tmcp_rsa               # 🔒 SSH Private Key (auto-generated, KHÔNG commit)
    ├── tmcp_vault_keys.txt    # 🔒 Vault Unseal Keys (auto-generated, KHÔNG commit)
    ├── terraform.tfstate      # 🔒 Terraform State (KHÔNG commit)
    └── terraform.tfstate.backup
```

**Repo liên quan:**
- **`lupca/tmcp-gitops`** — Chứa các ArgoCD Application YAML (Source of Truth cho GitOps)

---

## 6. Bảo Mật

### Các lớp bảo mật đã triển khai

| Lớp | Biện pháp | Chi tiết |
|-----|-----------|----------|
| **SSH** | Key-based auth only | RSA-4096, tắt password login, tắt root login |
| **Firewall** | UFW | Chỉ mở port cần thiết (22, 80, 443, 6443) |
| **Brute-force** | Fail2Ban | Ban IP sau 3 lần sai, 1 giờ |
| **Secrets** | Vault + ESO | Quản lý tập trung, auto-sync vào K8s |
| **Git** | .gitignore | Chặn commit: private key, vault keys, tfstate |
| **File Permission** | chmod 0600 | Private key chỉ owner đọc được |

### Các file TUYỆT ĐỐI KHÔNG được commit

| File | Lý do |
|------|-------|
| `tmcp_rsa` | SSH Private Key — ai có file này SSH được vào server |
| `tmcp_vault_keys.txt` | Vault Unseal Keys + Root Token — kiểm soát toàn bộ secrets |
| `terraform.tfstate` | Chứa toàn bộ state, có thể lộ IP, key, credentials |
| `.terraform/` | Chứa provider binaries, không cần thiết |

### ⚠️ Nếu lỡ commit file nhạy cảm

```bash
# 1. Xóa khỏi git tracking (giữ file local)
git rm --cached <file>

# 2. Commit
git commit -m "Remove sensitive file from tracking"

# 3. QUAN TRỌNG: Xóa khỏi lịch sử git
# Dùng BFG Repo-Cleaner hoặc git filter-branch

# 4. ROTATE (thay mới) tất cả keys/tokens đã bị lộ!
```

---

## 7. Luồng GitOps

```
Developer                    GitHub                     ArgoCD                  K8s Cluster
    │                          │                          │                         │
    │  git push YAML files     │                          │                         │
    │─────────────────────────▶│                          │                         │
    │                          │   poll/webhook           │                         │
    │                          │─────────────────────────▶│                         │
    │                          │                          │  detect diff            │
    │                          │                          │────────────────────────▶│
    │                          │                          │  kubectl apply          │
    │                          │                          │────────────────────────▶│
    │                          │                          │                         │
    │                          │                          │  self-heal nếu bị      │
    │                          │                          │  chỉnh tay trên cluster │
    │                          │                          │────────────────────────▶│
    │                          │                          │                         │
```

**Nguyên tắc GitOps:**
1. **Git là Single Source of Truth** — Mọi thay đổi đều qua Git
2. **Declarative** — Khai báo trạng thái mong muốn, ArgoCD tự hiện thực hóa
3. **Automated** — Không cần chạy `kubectl apply` thủ công
4. **Self-healing** — Nếu ai đó sửa tay trên cluster, ArgoCD tự sửa lại

---

## 8. Công Nghệ Sử Dụng

| Công nghệ | Phiên bản | Vai trò |
|-----------|-----------|---------|
| **Terraform** | - | Infrastructure as Code |
| **Multipass** | - | Tạo VM Ubuntu trên macOS |
| **Ubuntu** | 24.04 LTS | Hệ điều hành VM |
| **K3s** | latest | Lightweight Kubernetes |
| **ArgoCD** | stable | GitOps Continuous Delivery |
| **HashiCorp Vault** | - | Secret Management |
| **External Secrets Operator** | - | Sync secrets Vault → K8s |
| **PocketBase** | v0.0.18 (custom) | Application Dashboard |
| **Cloud-Init** | - | VM bootstrap & hardening |
| **UFW** | - | Firewall |
| **Fail2Ban** | - | Brute-force protection |

---

## 🚀 Quick Start

```bash
# 1. Vào thư mục infra
cd tmcp-infra

# 2. Khởi tạo Terraform
terraform init

# 3. Xem trước những gì sẽ tạo
terraform plan

# 4. Chạy toàn bộ pipeline (mất ~5-10 phút)
terraform apply

# 5. Trỏ kubectl về cluster mới
export KUBECONFIG=~/.kube/tmcp_config

# 6. Kiểm tra
kubectl get nodes
kubectl get pods -A
```

---

> 📝 **Ghi chú:** File này mô tả kiến trúc tại thời điểm viết.
> Kiến trúc có thể thay đổi khi project phát triển thêm.
