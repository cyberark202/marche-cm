provider "aws" {
  region                   = var.aws_region
  profile                  = var.aws_profile
  shared_config_files      = var.aws_shared_config_files
  shared_credentials_files = var.aws_shared_credentials_files

  default_tags {
    tags = {
      Project   = "marche-cm"
      ManagedBy = "terraform"
      Env       = var.environment
    }
  }
}
