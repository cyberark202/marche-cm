variable "aws_region" {
  description = "Région AWS du cluster EKS."
  type        = string
  default     = "eu-north-1"
}

variable "aws_profile" {
  description = "Profil AWS CLI (laisser vide en CI/OIDC)."
  type        = string
  default     = null
}

variable "aws_shared_config_files" {
  description = "Fichiers de config AWS partagés."
  type        = list(string)
  default     = null
}

variable "aws_shared_credentials_files" {
  description = "Fichiers de credentials AWS partagés."
  type        = list(string)
  default     = null
}

variable "environment" {
  description = "Environnement logique."
  type        = string
  default     = "prod"
}

variable "cluster_name" {
  description = "Nom du cluster EKS."
  type        = string
  default     = "marche-cm"
}

variable "kubernetes_version" {
  description = "Version Kubernetes du control plane."
  type        = string
  default     = "1.30"
}

# Réseau : on réutilise le VPC existant (où vit RDS) pour que les pods
# atteignent la base sans peering. Renseigner depuis la console / l'infra EC2.
variable "vpc_id" {
  description = "ID du VPC existant (celui de RDS)."
  type        = string
}

variable "private_subnet_ids" {
  description = "Subnets privés pour les nœuds EKS (≥2 AZ)."
  type        = list(string)
}

variable "public_subnet_ids" {
  description = "Subnets publics pour l'ALB (internet-facing, ≥2 AZ)."
  type        = list(string)
}

variable "node_instance_types" {
  description = "Types d'instances du groupe de nœuds managé."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 4
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "ecr_repository_name" {
  description = "Nom du dépôt ECR pour l'image backend."
  type        = string
  default     = "marche-cm"
}

variable "app_namespace" {
  description = "Namespace Kubernetes de l'application."
  type        = string
  default     = "marche-cm"
}

variable "app_service_account" {
  description = "Nom du ServiceAccount applicatif (doit matcher la Helm chart)."
  type        = string
  default     = "marche-cm"
}

variable "media_bucket_name" {
  description = "Bucket S3 média (accès IRSA app)."
  type        = string
  default     = "market-cm"
}

variable "ssm_prefix" {
  description = "Préfixe SSM des secrets (accès IRSA app si External Secrets)."
  type        = string
  default     = "/marche-cm/prod"
}

variable "cluster_admin_principals" {
  description = "ARNs IAM (user/role) à promouvoir admin du cluster (access entries)."
  type        = list(string)
  default     = []
}
