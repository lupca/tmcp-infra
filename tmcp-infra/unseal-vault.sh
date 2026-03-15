#!/bin/bash
set -e

export KUBECONFIG=~/.kube/tmcp_config
KEY_FILE="tmcp_vault_keys.txt"

echo "🔐 Starting Vault Unseal Process (via kubectl exec)..."

# Check if kubectl is configured
if ! kubectl config current-context >/dev/null 2>&1; then
  echo "❌ kubectl not configured. Ensure KUBECONFIG is set correctly."
  exit 1
fi

echo "⏳ Waiting for Vault pod to be running..."
if ! kubectl wait --for=jsonpath='{.status.phase}'=Running pods/vault-0 -n vault --timeout=180s; then
  echo "❌ Timed out waiting for vault-0 pod to be in Running state."
  exit 1
fi

# Check if Vault is initialized
echo "🔍 Checking Vault init status..."
INIT_STATUS=$(kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null | jq -r '.initialized')

if [ "$INIT_STATUS" != "true" ]; then
  echo "⚠️ Vault is not initialized yet. Skipping unseal."
  exit 0
fi

# Check if Vault is sealed
echo "🔍 Checking if Vault is sealed..."
SEAL_STATUS=$(kubectl exec -n vault vault-0 -- vault status -format=json 2>/dev/null | jq -r '.sealed')

if [ "$SEAL_STATUS" = "false" ]; then
  echo "✅ Vault is already unsealed."
  exit 0
fi

echo "🔒 Vault is sealed. Proceeding with unseal..."

if [ ! -f "$KEY_FILE" ]; then
  echo "❌ CRITICAL ERROR: Vault is sealed, but key file '$KEY_FILE' not found!"
  exit 1
fi

echo "🔑 Found key file. Reading unseal keys..."
KEY1=$(grep "Unseal Key 1:" $KEY_FILE | awk '{print $4}')
KEY2=$(grep "Unseal Key 2:" $KEY_FILE | awk '{print $4}')
KEY3=$(grep "Unseal Key 3:" $KEY_FILE | awk '{print $4}')

if [ -z "$KEY1" ] || [ -z "$KEY2" ] || [ -z "$KEY3" ]; then
    echo "❌ Could not parse unseal keys from $KEY_FILE."
    exit 1
fi

echo "🔑 Unsealing Vault with 3 keys..."
kubectl exec -n vault vault-0 -- vault operator unseal "$KEY1"
kubectl exec -n vault vault-0 -- vault operator unseal "$KEY2"
kubectl exec -n vault vault-0 -- vault operator unseal "$KEY3"

# Final check
SEAL_STATUS_AFTER=$(kubectl exec -n vault vault-0 -- vault status -format=json | jq -r '.sealed')
if [ "$SEAL_STATUS_AFTER" = "false" ]; then
  echo "🎉 Vault successfully unsealed!"
else
  echo "❌ Failed to unseal Vault."
  exit 1
fi

exit 0
