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
      Stack     = "eks"
    }
  }
}

# Les providers kubernetes/helm s'authentifient sur le cluster EKS via un token
# AWS éphémère (pas de kubeconfig statique).
data "aws_eks_cluster_auth" "this" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
