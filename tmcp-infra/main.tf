terraform {
  required_providers {
    multipass = {
      source  = "larstobi/multipass"
      version = "~> 1.4.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6.0"
    }
  }
}

provider "multipass" {}

# ==========================================
# 1. TẠO CẶP KHÓA SSH TỰ ĐỘNG
# ==========================================
resource "tls_private_key" "tmcp_ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Lưu Private Key ra Mac để xài (Chỉ cấp quyền 0600 cho bảo mật)
resource "local_file" "private_key" {
  content         = tls_private_key.tmcp_ssh.private_key_pem
  filename        = "${path.module}/tmcp_rsa"
  file_permission = "0600"
}

# Tiêm Public Key vào file cloud-init
resource "local_file" "cloud_init" {
  content = templatefile("${path.module}/cloud-init.tftpl", {
    ssh_public_key = tls_private_key.tmcp_ssh.public_key_openssh
  })
  filename = "${path.module}/cloud-init.yaml"
}

# ==========================================
# 2. KHỞI TẠO MÁY ẢO BỌC THÉP
# ==========================================
data "multipass_instance" "existing_tmcp_server" {
  name = "tmcp-prod"
}

resource "multipass_instance" "new_tmcp_server" {
  count          = data.multipass_instance.existing_tmcp_server.name == "" ? 1 : 0
  name           = "tmcp-prod"
  cpus           = 2
  memory         = "6G"
  disk           = "20G"
  image          = "24.04"
  cloudinit_file = local_file.cloud_init.filename

  depends_on = [local_file.cloud_init]
}

locals {
  tmcp_server = data.multipass_instance.existing_tmcp_server.name != "" ? data.multipass_instance.existing_tmcp_server : multipass_instance.new_tmcp_server[0]
}

# ==========================================
# 3. KẾT NỐI SSH THỰC TẾ & CÀI K3S
# ==========================================
resource "null_resource" "setup_k3s" {
  depends_on = [multipass_instance.new_tmcp_server, local_file.private_key]

  # Thiết lập kết nối SSH
  connection {
    type        = "ssh"
    user        = "ubuntu"
    private_key = tls_private_key.tmcp_ssh.private_key_pem
    host        = local.tmcp_server.ipv4
    timeout     = "5m" # Chờ tối đa 5 phút để VM boot xong và mở UFW
  }

  # Cử đặc vụ chui vào qua SSH để cài K3s
  provisioner "remote-exec" {
    inline = [
      "echo 'Đang chờ cloud-init chạy xong OS Hardening...'",
      "cloud-init status --wait",
      "echo 'Cài đặt K3s...'",
      "curl -sfL https://get.k3s.io | sh -",
      "mkdir -p /home/ubuntu/.kube",
      "sudo cp /etc/rancher/k3s/k3s.yaml /home/ubuntu/.kube/config",
      "sudo chown -R ubuntu:ubuntu /home/ubuntu/.kube",
      "chmod 600 /home/ubuntu/.kube/config"
    ]
  }

  # Lệnh chạy trên Mac để kéo Kubeconfig bằng 'scp' qua SSH
  provisioner "local-exec" {
    command = <<EOT
      echo "Kéo Kubeconfig về Mac qua giao thức SCP..."
      scp -o StrictHostKeyChecking=no -i ${local_file.private_key.filename} ubuntu@${local.tmcp_server.ipv4}:~/.kube/config ~/.kube/tmcp_config
      sed -i '' "s/127.0.0.1/${local.tmcp_server.ipv4}/g" ~/.kube/tmcp_config
      echo "✅ Đã xong! Lệnh cần gõ: export KUBECONFIG=~/.kube/tmcp_config"
    EOT
  }
}

# ==========================================
# 4. THẢ "CỤC TÌNH BÁO" ARGOCD VÀO CĂN CỨ
# ==========================================
resource "null_resource" "deploy_argocd" {
  # Bắt buộc phải đợi K3s cài xong mới được thả ArgoCD
  depends_on = [null_resource.setup_k3s]

  # Dùng máy Mac làm bệ phóng để gõ lệnh điều khiển K3s
  provisioner "local-exec" {
    command = <<EOT
      export KUBECONFIG=~/.kube/tmcp_config
      echo "🛩️ Đang thả Cục Tình Báo ArgoCD vào căn cứ..."
      kubectl create namespace argocd || true
      
      # 1. Dùng Server-Side Apply để qua mặt giới hạn 256KB
      kubectl apply -n argocd --server-side -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
      
      # 2. Cho API Server 10 giây để nạp bản vẽ và đẻ Deployment
      echo "⏳ Chờ hệ thống nạp bản vẽ chỉ huy..."
      sleep 10
      
      # 3. Theo dõi đích danh 2 thằng Tướng quan trọng nhất của ArgoCD
      echo "🎯 Đang giám sát tiến độ xuất quân (Có thể mất vài phút để kéo Image)..."
      kubectl rollout status deployment/argocd-server -n argocd --timeout=300s
      kubectl rollout status statefulset/argocd-application-controller -n argocd --timeout=300s
      
      echo "✅ Cục tình báo ArgoCD đã sẵn sàng hoạt động!"
    EOT
  }
}

# ==========================================
# 5. GIAI ĐOẠN 1: DỰNG HẠ TẦNG LÕI (VAULT & ESO)
# ==========================================
resource "null_resource" "trigger_infra" {
  depends_on = [null_resource.deploy_argocd]

  provisioner "local-exec" {
    command = <<EOT
      export KUBECONFIG=~/.kube/tmcp_config
      echo "🏗️ Xây dựng Hạ tầng lõi trước để cài cắm CRD..."
      
      # Ép K8s cài trực tiếp 2 App này từ GitHub của mày
      kubectl apply -f https://raw.githubusercontent.com/lupca/tmcp-gitops/main/eso-application.yaml
      kubectl apply -f https://raw.githubusercontent.com/lupca/tmcp-gitops/main/vault-application.yaml
      
      echo "⏳ Chờ doanh trại Vault được lập..."
      while ! kubectl get namespace vault >/dev/null 2>&1; do sleep 3; done
      
      echo "⏳ Chờ Pod Vault xuất hiện..."
      while ! kubectl get pods -n vault -l app.kubernetes.io/name=vault 2>/dev/null | grep -q "0/1"; do sleep 5; done
    EOT
  }
}

# ==========================================
# 6. ĐẶC VỤ TỰ ĐỘNG KHỞI TẠO & MỞ KHÓA VAULT
# ==========================================
variable "unseal" {
  type        = string
  description = "A trigger to force the unsealing of Vault. Pass in the current timestamp to always run."
  default     = ""
}

resource "null_resource" "initial_vault_setup" {
  depends_on = [null_resource.trigger_infra]

  provisioner "local-exec" {
    command = <<EOT
      set -e
      export KUBECONFIG=~/.kube/tmcp_config
      KEY_FILE="tmcp_vault_keys.txt"
      
      echo "🤖 Tung Đặc vụ giải quyết Vault..."
      
      echo "⏳ Chờ Vault Pod thức dậy..."
      while ! kubectl get pods -n vault vault-0 >/dev/null 2>&1; do sleep 3; done
      kubectl wait --for=jsonpath='{.status.phase}'=Running pods/vault-0 -n vault --timeout=180s

      # Start port-forward in the background
      echo "🚀 Starting port-forward to Vault..."
      kubectl -n vault port-forward svc/vault 8200:8200 >/dev/null 2>&1 &
      PF_PID=$!

      # Function to automatically kill the port-forward process on exit
      cleanup() {
          echo "🧹 Cleaning up port-forward process..."
          kill $PF_PID || true
      }
      trap cleanup EXIT
      sleep 3

      echo "🔍 Kiểm tra trí nhớ của Vault..."
      # Use kubectl exec instead of port-forwarded localhost for more reliability
      INIT_STATUS=$(kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null | jq -r '.initialized')
      
      if [ "$INIT_STATUS" = "false" ]; then
        echo "🚨 Vault mới tinh! Đang khởi tạo và đúc bộ chìa khóa mới..."
        kubectl exec -n vault vault-0 -- vault operator init -key-shares=3 -key-threshold=3 > $KEY_FILE
        
        echo "💾 ĐÃ LƯU BỘ CHÌA KHÓA MỚI VÀO: $KEY_FILE"
      else
        echo "✅ Vault đã được khởi tạo. Bỏ qua bước init."
      fi
    EOT
  }
}

resource "null_resource" "vault_unsealer" {
  depends_on = [null_resource.initial_vault_setup]
  triggers = {
    unseal_trigger = var.unseal
  }

  provisioner "local-exec" {
    command = "${path.module}/unseal-vault.sh"
  }
}

# ==========================================
# 6.5. TỰ ĐỘNG SEED SECRETS VÀO VAULT
# ==========================================
resource "null_resource" "seed_vault_secrets" {
  depends_on = [null_resource.vault_unsealer]

  provisioner "local-exec" {
    command = "${path.module}/seed-vault.sh"
    environment = {
      POCKETBASE_PASSWORD       = var.pocketbase_password
      GOOGLE_API_KEY            = var.google_api_key
      LANGSMITH_API_KEY         = var.langsmith_api_key
      DISCORD_WEBHOOK_URL       = var.discord_webhook_url
      PB_ADMIN_PASSWORD         = var.pb_admin_password
      KIBANA_SAVED_OBJECTS_KEY  = var.kibana_saved_objects_key
      KIBANA_REPORTING_KEY      = var.kibana_reporting_key
      KIBANA_SECURITY_KEY       = var.kibana_security_key
    }
  }
}

# ==========================================
# 7. GIAI ĐOẠN 2: THẢ WORKLOADS (ROOT APP)
# ==========================================
resource "local_file" "argocd_root_app" {
  content = <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: tmcp-master
  namespace: argocd
spec:
  project: default
  source:
    repoURL: 'https://github.com/lupca/tmcp-gitops'
    targetRevision: HEAD
    path: .
  destination:
    server: 'https://kubernetes.default.svc'
    namespace: default
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
  filename = "${path.module}/tmcp-root.yaml"
}

resource "null_resource" "trigger_workloads" {
  depends_on = [null_resource.seed_vault_secrets, local_file.argocd_root_app]

  provisioner "local-exec" {
    command = <<EOT
      export KUBECONFIG=~/.kube/tmcp_config
      echo "🚀 Hạ tầng đã sẵn sàng! Tung toàn bộ lính đánh thuê TMCP..."
      kubectl apply -f ${local_file.argocd_root_app.filename}
      echo "🎯 ĐÃ KHÓA MỤC TIÊU! ArgoCD đang tự động xây dựng doanh trại."
      echo "🔐 Mật khẩu Admin ArgoCD:"
      kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d
      echo "\n🎉 HOÀN TẤT CHIẾN DỊCH THE IRON COMMANDER!"
    EOT
  }
}