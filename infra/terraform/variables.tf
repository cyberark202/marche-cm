variable "aws_profile" {
  description = "Profil AWS CLI utilisé par Terraform (clés d'accès programmatiques)."
  type        = string
  default     = "central-market_credentials"
}

variable "aws_region" {
  description = "Région AWS où l'infra existe déjà. À confirmer par l'inventaire."
  type        = string
  # Pas de default volontaire : on le renseigne après l'inventaire pour éviter
  # de viser la mauvaise région.
}

variable "environment" {
  description = "Nom de l'environnement (prod, staging…)."
  type        = string
  default     = "prod"
}

variable "aws_shared_config_files" {
  description = "Emplacement du fichier ~/.aws/config (laisser vide = défaut)."
  type        = list(string)
  default     = []
}

variable "aws_shared_credentials_files" {
  description = "Emplacement du fichier ~/.aws/credentials (laisser vide = défaut)."
  type        = list(string)
  default     = []
}

variable "alert_email" {
  description = "Email destinataire des alertes CloudWatch (via SNS). Vide = pas d'abonnement."
  type        = string
  default     = ""
}

# ──────────────────────────────────────────────────────────────────────────
# Secrets & Configuration (SSM Parameter Store)
# ──────────────────────────────────────────────────────────────────────────

variable "db_host" {
  description = "RDS database host (will be auto-filled if AWS-managed)"
  type        = string
  default     = ""
}

variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "marche_cm_db"
  sensitive   = true
}

variable "db_user" {
  description = "PostgreSQL username"
  type        = string
  default     = "marchecm_admin"
  sensitive   = true
}

variable "db_password" {
  description = "PostgreSQL password (MUST be provided via terraform.tfvars or -var)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "jwt_signing_key" {
  description = "JWT RSA private key (PEM format) for signing tokens"
  type        = string
  sensitive   = true
  default     = ""
}

variable "jwt_verifying_key" {
  description = "JWT RSA public key (PEM format) for verifying tokens"
  type        = string
  sensitive   = true
  default     = ""
}

variable "allowed_hosts" {
  description = "Django ALLOWED_HOSTS (comma-separated)"
  type        = string
  default     = "cm.digital-get.com,localhost,127.0.0.1"
}

variable "cors_allowed_origins" {
  description = "CORS allowed origins (comma-separated)"
  type        = string
  default     = "https://cm.digital-get.com"
}

variable "email_backend_api_key" {
  description = "Email backend API key (SendGrid/Mailgun)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "notchpay_api_key" {
  description = "NotchPay API key (live mode)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "notchpay_secret_key" {
  description = "NotchPay secret key (live mode)"
  type        = string
  sensitive   = true
  default     = ""
}

variable "redis_url" {
  description = "Redis connection URL (ElastiCache or local)"
  type        = string
  sensitive   = true
  default     = "redis://localhost:6379/0"
}

variable "celery_broker_url" {
  description = "Celery broker URL"
  type        = string
  sensitive   = true
  default     = "redis://localhost:6379/1"
}
