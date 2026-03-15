# 🚀 TMCP - Hướng Dẫn Cài Đặt & Vận Hành

Tài liệu này hướng dẫn bạn dựng cụm TMCP từ lúc máy trắng đến khi ứng dụng chạy trên trình duyệt.

## 📋 1. Chuẩn bị (Prerequisites)
Hãy cài đặt các công cụ sau trên máy Mac:
- **Multipass**: `brew install --cask multipass`
- **Terraform**: `brew install terraform`
- **kubectl**: `brew install kubectl`
- **jq**: `brew install jq`

---

## 🛠️ 2. Trình tự Cài đặt (Installation Steps)

Chỉ cần thực hiện theo các bước sau:

### Bước 1: Khởi tạo hạ tầng
```bash
cd tmcp-infra
terraform init
terraform apply -auto-approve
```
*Hệ thống sẽ mất khoảng 5-10 phút để tạo VM, cài K3s, ArgoCD và khởi tạo Vault.*

### Bước 2: Cấu hình kết nối
```bash
# Trỏ kubectl về cụm mới
export KUBECONFIG=~/.kube/tmcp_config

# Kiểm tra xem các Pod đã lên chưa
kubectl get pods -A
```

### Bước 3: Đăng nhập ArgoCD
Mật khẩu Admin của ArgoCD sẽ được in ra ở cuối lệnh `terraform apply`.
Địa chỉ: `http://192.168.2.10/argocd` (nếu bạn có cài Ingress cho nó).

---

## 🔄 3. Cách Khởi Động Lại (The "One-Command" Restart)

Khi bạn tắt máy tính hoặc khởi động lại VM, Vault sẽ bị khóa (Sealed). Để hệ thống hoạt động lại bình thường, hãy chạy duy nhất lệnh sau:

```bash
cd tmcp-infra
terraform apply -var="unseal=$(date +%s)" -auto-approve
```
**Lệnh này sẽ tự động:**
1. Khởi động lại máy ảo (nếu đang tắt).
2. Tự động Unseal Vault bằng các Key đã lưu trong `tmcp_vault_keys.txt`.
3. Kiểm tra và đảm bảo các ứng dụng thông suốt.

---

## 🔐 4. Quản lý Mật khẩu (Secret Management)

Để nạp thêm mật khẩu vào hệ thống, hãy dùng lệnh sau:

```bash
# Ví dụ nạp mật khẩu cho Agent
kubectl exec -it -n vault vault-0 -- vault kv put secret/tmcp/agent POCKETBASE_PASSWORD="mật_khẩu_mới"
```

---

## 🌐 5. Truy cập Ứng dụng (End-user Links)

| Ứng dụng | Đường dẫn (URL) |
|----------|----------------|
| **Astro Blog** | `http://192.168.2.10/` |
| **Marketing Hub** | `http://192.168.2.10/hub/` |
| **PocketBase Admin** | `http://192.168.2.10/pb/_/` |
| **Agent API Docs** | `http://192.168.2.10/api/agent/docs` |

---

## ⚠️ 6. Xử lý sự cố (Troubleshooting)

- **Lỗi 502/Timeout:** Thường do máy ảo đang quá tải CPU. Hãy đợi 1-2 phút hoặc kiểm tra bộ nhớ bằng lệnh `free -h` trên VM.
- **Pod bị "CreateContainerConfigError":** Do bạn chưa nạp đủ mật khẩu vào Vault. Kiểm tra bằng `kubectl describe pod <tên-pod>`.
- **Lỗi "i/o timeout" khi chạy Terraform:** Do mạng giữa Mac và VM bị nghẽn. Hãy chạy lại lệnh Unseal ở mục 3.
