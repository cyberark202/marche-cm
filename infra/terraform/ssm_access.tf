# Accès de l'EC2 (rôle accessRoles3) aux secrets SSM + au bucket S3 régulier.
# Policy INLINE : ne touche pas à managed_policy_arns (authoritative) du rôle.
#
# Corrige aussi un bug latent : le rôle n'avait que AmazonS3ExpressFullAccess
# (S3 Express uniquement), donc PAS d'accès au bucket régulier market-cm.

locals {
  ssm_prefix = "marche-cm/prod"
}

data "aws_caller_identity" "current" {}

resource "aws_iam_role_policy" "ec2_app_access" {
  name = "marche-cm-app-access"
  role = aws_iam_role.ec2_s3.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ReadAppSecrets"
        Effect = "Allow"
        Action = [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:GetParametersByPath",
        ]
        # GetParametersByPath exige l'ARN du chemin lui-même (sans /*) EN PLUS des
        # paramètres enfants (/*) pour GetParameter.
        Resource = [
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${local.ssm_prefix}",
          "arn:aws:ssm:${var.aws_region}:${data.aws_caller_identity.current.account_id}:parameter/${local.ssm_prefix}/*",
        ]
      },
      {
        Sid    = "DecryptSecureStrings"
        Effect = "Allow"
        Action = ["kms:Decrypt"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:ViaService" = "ssm.${var.aws_region}.amazonaws.com"
          }
        }
      },
      {
        Sid    = "S3ObjectAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
        ]
        Resource = "${aws_s3_bucket.media.arn}/*"
      },
      {
        Sid    = "S3BucketAccess"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = aws_s3_bucket.media.arn
      },
      {
        Sid    = "CloudWatchLogsAccess"
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents",
          "logs:DescribeLogStreams",
          "logs:DescribeLogGroups"
        ]
        Resource = "*"
      },
    ]
  })
}
