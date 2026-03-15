#!/bin/bash
set -e

# ==========================================
# SEED VAULT SECRETS - Tự động chạy sau Unseal
# ==========================================
# Script này:
# 1. Login Vault bằng Root Token
# 2. Bật KV-v2 secret engine + Kubernetes Auth
# 3. Tạo ESO policy & role
# 4. Inject tất cả secrets vào Vault

export KUBECONFIG=~/.kube/tmcp_config
KEY_FILE="tmcp_vault_keys.txt"

echo "🔐 Bắt đầu Seed Vault Secrets..."

# Kiểm tra Vault đã unseal chưa
SEAL_STATUS=$(kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null | jq -r '.sealed')
if [ "$SEAL_STATUS" = "true" ]; then
  echo "❌ Vault vẫn đang sealed! Hãy unseal trước."
  exit 1
fi

# ==========================================
# BƯỚC 1: LOGIN VAULT BẰNG ROOT TOKEN
# ==========================================
echo "🔑 Đăng nhập Vault bằng Root Token..."
ROOT_TOKEN=$(grep "Initial Root Token:" "$KEY_FILE" | awk '{print $4}')
if [ -z "$ROOT_TOKEN" ]; then
  echo "❌ Không tìm thấy Root Token trong $KEY_FILE"
  exit 1
fi
kubectl exec -n vault vault-0 -- vault login "$ROOT_TOKEN" > /dev/null 2>&1

# ==========================================
# BƯỚC 2: BẬT KV-V2 SECRET ENGINE (idempotent)
# ==========================================
echo "📦 Bật KV-v2 Secret Engine..."
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2 2>/dev/null || echo "  ↳ Đã bật sẵn, bỏ qua."

# ==========================================
# BƯỚC 3: BẬT KUBERNETES AUTH (idempotent)
# ==========================================
echo "🔗 Bật Kubernetes Auth..."
kubectl exec -n vault vault-0 -- vault auth enable kubernetes 2>/dev/null || echo "  ↳ Đã bật sẵn, bỏ qua."

echo "📡 Cấu hình Kubernetes Auth config..."
kubectl exec -n vault vault-0 -- sh -c 'vault write auth/kubernetes/config kubernetes_host="https://$KUBERNETES_PORT_443_TCP_ADDR:443"'

# ==========================================
# BƯỚC 4: TẠO ESO POLICY & ROLE
# ==========================================
echo "📜 Tạo ESO Policy..."
kubectl exec -n vault vault-0 -- sh -c "echo 'path \"secret/data/tmcp/*\" { capabilities = [\"read\"] }' | vault policy write eso-policy -"

echo "👤 Tạo ESO Role..."
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/eso \
  bound_service_account_names=external-secrets \
  bound_service_account_namespaces=external-secrets \
  policies=eso-policy \
  ttl=1h

# ==========================================
# BƯỚC 5: SEED TẤT CẢ SECRETS
# ==========================================
echo ""
echo "💉 Bắt đầu inject secrets vào Vault..."

# --- tmcp/bridge ---
echo "  📦 tmcp/bridge..."
kubectl exec -n vault vault-0 -- vault kv put secret/tmcp/bridge \
  POCKETBASE_PASSWORD="${POCKETBASE_PASSWORD}"

# --- tmcp/agent ---
echo "  📦 tmcp/agent..."
kubectl exec -n vault vault-0 -- vault kv put secret/tmcp/agent \
  POCKETBASE_PASSWORD="${POCKETBASE_PASSWORD}" \
  GOOGLE_API_KEY="${GOOGLE_API_KEY}" \
  LANGSMITH_API_KEY="${LANGSMITH_API_KEY}"

# --- tmcp/aiops-agent ---
echo "  📦 tmcp/aiops-agent..."
kubectl exec -n vault vault-0 -- vault kv put secret/tmcp/aiops-agent \
  DISCORD_WEBHOOK_URL="${DISCORD_WEBHOOK_URL}"

# --- tmcp/video-creater ---
echo "  📦 tmcp/video-creater..."
kubectl exec -n vault vault-0 -- vault kv put secret/tmcp/video-creater \
  PB_ADMIN_PASSWORD="${PB_ADMIN_PASSWORD}"

# --- tmcp/kibana ---
echo "  📦 tmcp/kibana..."
# Sinh random key nếu chưa có
KIBANA_KEY1="${KIBANA_SAVED_OBJECTS_KEY:-$(openssl rand -hex 16)}"
KIBANA_KEY2="${KIBANA_REPORTING_KEY:-$(openssl rand -hex 16)}"
KIBANA_KEY3="${KIBANA_SECURITY_KEY:-$(openssl rand -hex 16)}"

kubectl exec -n vault vault-0 -- vault kv put secret/tmcp/kibana \
  XPACK_ENCRYPTEDSAVEDOBJECTS_ENCRYPTIONKEY="${KIBANA_KEY1}" \
  XPACK_REPORTING_ENCRYPTIONKEY="${KIBANA_KEY2}" \
  XPACK_SECURITY_ENCRYPTIONKEY="${KIBANA_KEY3}"

# ==========================================
# BƯỚC 6: XÁC NHẬN
# ==========================================
echo ""
echo "✅ Kiểm tra secrets đã được seed..."
kubectl exec -n vault vault-0 -- vault kv list secret/tmcp/ 2>/dev/null && echo "🎉 TẤT CẢ SECRETS ĐÃ ĐƯỢC SEED THÀNH CÔNG!" || echo "⚠️ Không thể list secrets, nhưng có thể đã seed thành công."
