# ==========================================
# BIẾN BẢO MẬT CHO VAULT SECRET SEEDING
# ==========================================
# Tất cả giá trị mặc định lấy từ .env files hiện có.
# Override bằng terraform.tfvars nếu cần thay đổi.

# --- Bridge Secrets (tmcp/bridge) ---
variable "pocketbase_password" {
  type        = string
  description = "Mật khẩu PocketBase cho Bridge & Agent"
  default     = "1234567890"
  sensitive   = true
}

# --- Agent Secrets (tmcp/agent) ---
variable "google_api_key" {
  type        = string
  description = "Google API Key cho Marketing Agent (Gemini)"
  default     = "YOUR_GOOGLE_API_KEY"
  sensitive   = true
}

variable "langsmith_api_key" {
  type        = string
  description = "LangSmith API Key cho tracing"
  default     = "YOUR_LANGSMITH_API_KEY"
  sensitive   = true
}

# --- AIOps Agent Secrets (tmcp/aiops-agent) ---
variable "discord_webhook_url" {
  type        = string
  description = "Discord Webhook URL cho AIOps alerting"
  default     = "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_WEBHOOK_TOKEN"
  sensitive   = true
}

# --- Kibana Secrets (tmcp/kibana) ---
variable "kibana_saved_objects_key" {
  type        = string
  description = "Kibana xpack.encryptedSavedObjects.encryptionKey (32-char hex)"
  default     = ""
  sensitive   = true
}

variable "kibana_reporting_key" {
  type        = string
  description = "Kibana xpack.reporting.encryptionKey (32-char hex)"
  default     = ""
  sensitive   = true
}

variable "kibana_security_key" {
  type        = string
  description = "Kibana xpack.security.encryptionKey (32-char hex)"
  default     = ""
  sensitive   = true
}

# --- Video-Creater Secrets (tmcp/video-creater) ---
variable "pb_admin_password" {
  type        = string
  description = "PocketBase admin password cho Video-Creater worker"
  default     = "1234567890"
  sensitive   = true
}
