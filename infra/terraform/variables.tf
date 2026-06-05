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
