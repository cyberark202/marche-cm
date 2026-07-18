# Rôle IRSA monté sur le ServiceAccount applicatif (Helm: serviceAccount.name).
# Donne accès au bucket média S3 et aux paramètres SSM (si External Secrets).

data "aws_iam_policy_document" "app" {
  statement {
    sid    = "S3Media"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]
    resources = [
      "arn:aws:s3:::${var.media_bucket_name}",
      "arn:aws:s3:::${var.media_bucket_name}/*",
    ]
  }

  statement {
    sid    = "SsmSecrets"
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = [
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_prefix}",
      "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_prefix}/*",
    ]
  }

  statement {
    sid       = "KmsDecryptSsm"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.aws_region}.amazonaws.com"]
    }
  }
}

module "app_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${var.cluster_name}-app"

  role_policy_arns = {
    app = aws_iam_policy.app.arn
  }

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["${var.app_namespace}:${var.app_service_account}"]
    }
  }
}

resource "aws_iam_policy" "app" {
  name   = "${var.cluster_name}-app"
  policy = data.aws_iam_policy_document.app.json
}
