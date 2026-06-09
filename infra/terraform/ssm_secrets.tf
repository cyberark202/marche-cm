# SSM Parameter Store — Secrets gérés centralisés pour la prod.
# Chaque paramètre est chiffré via KMS.
# Les valeurs INITIALES doivent être fournies via `terraform apply -var` ou tfvars.
# Ne JAMAIS committer les vraies valeurs dans ce fichier.

# KMS key pour chiffrer les secrets (réutilisé pour RDS + S3)
resource "aws_kms_key" "ssm_secrets" {
  description             = "KMS key for SSM Parameter Store secrets (Marche CM)"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    Name = "marche-cm-ssm-secrets"
  }
}

resource "aws_kms_alias" "ssm_secrets" {
  name          = "alias/marche-cm-ssm-secrets"
  target_key_id = aws_kms_key.ssm_secrets.key_id
}

# ────────────────────────────────────────────────────────────────────────────
# Variables d'environnement d'APPLICATION
# ────────────────────────────────────────────────────────────────────────────

locals {
  ssm_prefix = "marche-cm/prod"
}

# Base de données PostgreSQL
resource "aws_ssm_parameter" "db_host" {
  name            = "${local.ssm_prefix}/DB_HOST"
  type            = "String"
  value           = try(aws_db_instance.postgres.address, var.db_host)
  description     = "RDS endpoint (PostgreSQL)"
  tags            = { Component = "database" }
  override_account_id = data.aws_caller_identity.current.account_id
}

resource "aws_ssm_parameter" "db_port" {
  name        = "${local.ssm_prefix}/DB_PORT"
  type        = "String"
  value       = "5432"
  description = "PostgreSQL port"
  tags        = { Component = "database" }
}

resource "aws_ssm_parameter" "db_name" {
  name        = "${local.ssm_prefix}/DB_NAME"
  type        = "String"
  value       = var.db_name
  description = "Database name"
  tags        = { Component = "database" }
}

resource "aws_ssm_parameter" "db_user" {
  name        = "${local.ssm_prefix}/DB_USER"
  type        = "String"
  value       = var.db_user
  description = "Database username"
  tags        = { Component = "database" }
}

resource "aws_ssm_parameter" "db_password" {
  name            = "${local.ssm_prefix}/DB_PASSWORD"
  type            = "SecureString"
  value           = var.db_password
  description     = "Database password (RDS)"
  key_id          = aws_kms_key.ssm_secrets.id
  tags            = { Component = "database", Sensitive = "true" }
  depends_on      = [aws_kms_key.ssm_secrets]
}

# ────────────────────────────────────────────────────────────────────────────
# Clés JWT (multi-lignes PEM)
# Stockées dans SSM pour accès sécurisé depuis l'EC2.
# ────────────────────────────────────────────────────────────────────────────

resource "aws_ssm_parameter" "jwt_signing_key" {
  name            = "${local.ssm_prefix}/JWT_SIGNING_KEY"
  type            = "SecureString"
  value           = var.jwt_signing_key
  description     = "JWT RSA private key (PEM) for signing tokens"
  key_id          = aws_kms_key.ssm_secrets.id
  tags            = { Component = "auth", Sensitive = "true" }
  depends_on      = [aws_kms_key.ssm_secrets]
}

resource "aws_ssm_parameter" "jwt_verifying_key" {
  name            = "${local.ssm_prefix}/JWT_VERIFYING_KEY"
  type            = "SecureString"
  value           = var.jwt_verifying_key
  description     = "JWT RSA public key (PEM) for verifying tokens"
  key_id          = aws_kms_key.ssm_secrets.id
  tags            = { Component = "auth", Sensitive = "true" }
  depends_on      = [aws_kms_key.ssm_secrets]
}

# ────────────────────────────────────────────────────────────────────────────
# Configuration d'APPLICATION
# ────────────────────────────────────────────────────────────────────────────

resource "aws_ssm_parameter" "allowed_hosts" {
  name        = "${local.ssm_prefix}/ALLOWED_HOSTS"
  type        = "String"
  value       = var.allowed_hosts
  description = "Django ALLOWED_HOSTS (comma-separated)"
  tags        = { Component = "django" }
}

resource "aws_ssm_parameter" "cors_allowed_origins" {
  name        = "${local.ssm_prefix}/CORS_ALLOWED_ORIGINS"
  type        = "String"
  value       = var.cors_allowed_origins
  description = "CORS allowed origins (comma-separated)"
  tags        = { Component = "django" }
}

resource "aws_ssm_parameter" "email_backend_api_key" {
  name            = "${local.ssm_prefix}/EMAIL_BACKEND_API_KEY"
  type            = "SecureString"
  value           = var.email_backend_api_key
  description     = "Email service API key (SendGrid/Mailgun)"
  key_id          = aws_kms_key.ssm_secrets.id
  tags            = { Component = "email", Sensitive = "true" }
  depends_on      = [aws_kms_key.ssm_secrets]
}

resource "aws_ssm_parameter" "notchpay_api_key" {
  name            = "${local.ssm_prefix}/NOTCHPAY_API_KEY"
  type            = "SecureString"
  value           = var.notchpay_api_key
  description     = "NotchPay API key for payments (live mode)"
  key_id          = aws_kms_key.ssm_secrets.id
  tags            = { Component = "payments", Sensitive = "true" }
  depends_on      = [aws_kms_key.ssm_secrets]
}

resource "aws_ssm_parameter" "notchpay_secret_key" {
  name            = "${local.ssm_prefix}/NOTCHPAY_SECRET_KEY"
  type            = "SecureString"
  value           = var.notchpay_secret_key
  description     = "NotchPay secret key for payments (live mode)"
  key_id          = aws_kms_key.ssm_secrets.id
  tags            = { Component = "payments", Sensitive = "true" }
  depends_on      = [aws_kms_key.ssm_secrets]
}

resource "aws_ssm_parameter" "redis_url" {
  name            = "${local.ssm_prefix}/REDIS_URL"
  type            = "SecureString"
  value           = var.redis_url
  description     = "Redis connection URL (ElastiCache or local)"
  key_id          = aws_kms_key.ssm_secrets.id
  tags            = { Component = "cache", Sensitive = "true" }
  depends_on      = [aws_kms_key.ssm_secrets]
}

resource "aws_ssm_parameter" "celery_broker_url" {
  name            = "${local.ssm_prefix}/CELERY_BROKER_URL"
  type            = "SecureString"
  value           = var.celery_broker_url
  description     = "Celery broker URL (Redis)"
  key_id          = aws_kms_key.ssm_secrets.id
  tags            = { Component = "celery", Sensitive = "true" }
  depends_on      = [aws_kms_key.ssm_secrets]
}

# ────────────────────────────────────────────────────────────────────────────
# AWS / Cloud Configuration
# ────────────────────────────────────────────────────────────────────────────

resource "aws_ssm_parameter" "s3_bucket_name" {
  name        = "${local.ssm_prefix}/S3_BUCKET_NAME"
  type        = "String"
  value       = aws_s3_bucket.media.id
  description = "S3 bucket for media storage"
  tags        = { Component = "storage" }
}

resource "aws_ssm_parameter" "aws_region" {
  name        = "${local.ssm_prefix}/AWS_REGION"
  type        = "String"
  value       = var.aws_region
  description = "AWS region (for boto3, django-storages)"
  tags        = { Component = "aws" }
}

# ────────────────────────────────────────────────────────────────────────────
# Outputs for administration
# ────────────────────────────────────────────────────────────────────────────

output "ssm_parameters" {
  value       = {
    prefix = local.ssm_prefix
    count  = length(aws_ssm_parameter.db_host) + length(aws_ssm_parameter.jwt_signing_key)
  }
  description = "SSM Parameter Store configuration"
}

output "kms_key_id" {
  value       = aws_kms_key.ssm_secrets.id
  description = "KMS key ID for decrypting SSM secrets"
}
