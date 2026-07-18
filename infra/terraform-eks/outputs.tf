output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "ecr_repository_url" {
  description = "URL ECR pour build/push de l'image (image.repository du chart)."
  value       = aws_ecr_repository.backend.repository_url
}

output "app_irsa_role_arn" {
  description = "À mettre dans values-prod: serviceAccount.annotations[eks.amazonaws.com/role-arn]."
  value       = module.app_irsa.iam_role_arn
}

output "configure_kubectl" {
  description = "Commande pour configurer kubectl."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "app_namespace" {
  value = kubernetes_namespace.app.metadata[0].name
}
