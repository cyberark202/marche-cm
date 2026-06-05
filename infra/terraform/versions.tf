terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # État local au départ (gitignoré). Migration possible vers un backend S3 +
  # verrouillage DynamoDB une fois le bucket d'état créé (voir README, §État distant).
  # backend "s3" {
  #   bucket         = "marche-cm-tfstate"
  #   key            = "prod/terraform.tfstate"
  #   region         = "eu-west-3"
  #   dynamodb_table = "marche-cm-tflock"
  #   encrypt        = true
  # }
}
