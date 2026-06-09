# Ressources adoptées depuis l'infra existante (généré par `terraform plan
# -generate-config-out` puis NETTOYÉ : attributs bugués du générateur retirés,
# tags_all supprimés — gérés par default_tags). Voir imports.tf pour les IDs.
# Cible : `terraform plan` sans destruction.

# ── Sous-réseaux privés dédiés RDS ───────────────────────────────────────────
resource "aws_subnet" "rds_1" {
  vpc_id            = "vpc-06c9268a6c1463479"
  availability_zone = "eu-north-1a"
  cidr_block        = "172.31.48.0/25"
  tags              = { Name = "RDS-Pvt-subnet-1" }
}

resource "aws_subnet" "rds_2" {
  vpc_id            = "vpc-06c9268a6c1463479"
  availability_zone = "eu-north-1b"
  cidr_block        = "172.31.48.128/25"
  tags              = { Name = "RDS-Pvt-subnet-2" }
}

resource "aws_subnet" "rds_3" {
  vpc_id            = "vpc-06c9268a6c1463479"
  availability_zone = "eu-north-1-cph-1a"
  cidr_block        = "172.31.49.0/25"
  tags              = { Name = "RDS-Pvt-subnet-3" }
}

resource "aws_subnet" "rds_4" {
  vpc_id            = "vpc-06c9268a6c1463479"
  availability_zone = "eu-north-1c"
  cidr_block        = "172.31.49.128/25"
  tags              = { Name = "RDS-Pvt-subnet-4" }
}

# ── Security groups ──────────────────────────────────────────────────────────
resource "aws_security_group" "ec2_rds" {
  description = "Security group attached to instances to securely connect to marchecm-postgres. Modification could lead to connection loss."
  name        = "ec2-rds-1"
  vpc_id      = "vpc-06c9268a6c1463479"
  egress = [{
    cidr_blocks      = []
    description      = "Rule to allow connections to marchecm-postgres from any instances this security group is attached to"
    from_port        = 5432
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "tcp"
    security_groups  = ["sg-0650f15be757d09e3"]
    self             = false
    to_port          = 5432
  }]
  ingress = []
}

resource "aws_security_group" "rds_ec2" {
  description = "Security group attached to marchecm-postgres to allow EC2 instances with specific security groups attached to connect to the database. Modification could lead to connection loss."
  name        = "rds-ec2-1"
  vpc_id      = "vpc-06c9268a6c1463479"
  egress      = []
  ingress = [{
    cidr_blocks      = []
    description      = "Rule to allow connections from EC2 instances with sg-0819d0a49a7c50f85 attached"
    from_port        = 5432
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "tcp"
    security_groups  = ["sg-0819d0a49a7c50f85"]
    self             = false
    to_port          = 5432
  }]
}

resource "aws_security_group" "launch_wizard_1" {
  description = "launch-wizard-1 created 2026-05-30T23:10:43.817Z"
  name        = "launch-wizard-1"
  vpc_id      = "vpc-06c9268a6c1463479"
  egress = [{
    cidr_blocks      = ["0.0.0.0/0"]
    description      = ""
    from_port        = 0
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "-1"
    security_groups  = []
    self             = false
    to_port          = 0
  }]
  # NOTE sécurité : 22/443/80 actuellement ouverts à 0.0.0.0/0 (état réel importé).
  # Le durcissement (SSH -> IP admin) est proposé séparément, sur accord.
  ingress = [
    {
      cidr_blocks      = ["0.0.0.0/0"]
      description      = ""
      from_port        = 443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 443
    },
    {
      cidr_blocks      = ["0.0.0.0/0"]
      description      = ""
      from_port        = 80
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 80
    }
  ]
}

resource "aws_security_group" "group_secure_marketcm" {
  description = "launch-wizard-1 created 2026-05-29T18:42:51.622Z"
  name        = "group-secure-marketcm"
  vpc_id      = "vpc-06c9268a6c1463479"
  egress = [{
    cidr_blocks      = ["0.0.0.0/0"]
    description      = ""
    from_port        = 0
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "-1"
    security_groups  = []
    self             = false
    to_port          = 0
  }]
  ingress = [
    {
      cidr_blocks      = ["102.244.197.67/32"]
      description      = ""
      from_port        = 5000
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 5000
    },
    {
      cidr_blocks      = ["129.0.99.166/32"]
      description      = ""
      from_port        = 22
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 22
    },
    {
      cidr_blocks      = ["129.0.99.166/32"]
      description      = ""
      from_port        = 443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 443
    },
    {
      cidr_blocks      = ["129.0.99.166/32"]
      description      = ""
      from_port        = 80
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 80
    }
  ]
}

resource "aws_security_group" "secure_group_mcm" {
  description = "launch-wizard-1 created 2026-05-29T17:31:49.751Z"
  name        = "SecureGroup-Mcm"
  vpc_id      = "vpc-06c9268a6c1463479"
  egress = [{
    cidr_blocks      = ["0.0.0.0/0"]
    description      = ""
    from_port        = 0
    ipv6_cidr_blocks = []
    prefix_list_ids  = []
    protocol         = "-1"
    security_groups  = []
    self             = false
    to_port          = 0
  }]
  ingress = [
    {
      cidr_blocks      = ["129.0.99.0/24"]
      description      = "SSH admin (bloc FAI, IP dynamique 129.0.99.x)"
      from_port        = 22
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 22
    },
    {
      cidr_blocks      = ["129.0.99.166/32"]
      description      = ""
      from_port        = 443
      ipv6_cidr_blocks = []
      prefix_list_ids  = []
      protocol         = "tcp"
      security_groups  = []
      self             = false
      to_port          = 443
    }
  ]
}

# ── Elastic IP (market-CM-API) ───────────────────────────────────────────────
resource "aws_eip" "api" {
  domain               = "vpc"
  instance             = "i-09e104c1cd49c757e"
  network_border_group = "eu-north-1"
  network_interface    = "eni-0b38f7eb3aa3a3118"
  public_ipv4_pool     = "amazon"
}

# ── IAM ──────────────────────────────────────────────────────────────────────
resource "aws_iam_role" "ec2_s3" {
  name                  = "accessRoles3"
  path                  = "/"
  description           = "Allows EC2 instances to call AWS services on your behalf."
  force_detach_policies = false
  max_session_duration  = 3600
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/AmazonS3ExpressFullAccess",
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore", # Session Manager / send-command
  ]
  tags                  = { market = "api" }
  assume_role_policy = jsonencode({
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
    Version = "2012-10-17"
  })
}

resource "aws_iam_instance_profile" "ec2_s3" {
  name = "accessRoles3"
  path = "/"
  role = "accessRoles3"
}

resource "aws_iam_role" "rds_monitoring" {
  name                  = "rds-monitoring-role"
  path                  = "/"
  force_detach_policies = false
  max_session_duration  = 3600
  managed_policy_arns   = ["arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"]
  assume_role_policy = jsonencode({
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Sid       = ""
    }]
    Version = "2012-10-17"
  })
}

# ── RDS ──────────────────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "rds" {
  description = "Created from the RDS Management Console"
  name        = "rds-ec2-db-subnet-group-1"
  subnet_ids = [
    "subnet-02149f54ff8bd6afa",
    "subnet-068e00df939c6941d",
    "subnet-0f9d62c77fb7280c1",
    "subnet-0fbbcef65bad04e66",
  ]
}

resource "aws_db_instance" "postgres" {
  identifier            = "marchecm-postgres"
  engine                = "postgres"
  engine_version        = "18.3"
  instance_class        = "db.t3.medium"
  allocated_storage     = 200
  max_allocated_storage = 1000
  storage_type          = "gp3"
  iops                  = 3000
  storage_throughput    = 125
  storage_encrypted     = true
  kms_key_id            = "arn:aws:kms:eu-north-1:958924735829:key/9debcc87-a38b-4aae-9d5f-ad3fb7f836eb"

  username             = "marchecm_admin"
  db_subnet_group_name = "rds-ec2-db-subnet-group-1"
  vpc_security_group_ids = [
    "sg-0650f15be757d09e3",
    "sg-083d7a0e9c9eed317",
    "sg-0883ba2a8933d59ba",
  ]
  parameter_group_name = "default.postgres18"
  option_group_name    = "default:postgres-18"

  multi_az            = true
  publicly_accessible = false
  port                = 5432
  availability_zone   = "eu-north-1a"
  network_type        = "IPV4"
  ca_cert_identifier  = "rds-ca-rsa2048-g1"

  backup_retention_period      = 7
  backup_window                = "05:24-05:54"
  backup_target                = "region"
  maintenance_window           = "sat:04:11-sat:04:41"
  copy_tags_to_snapshot        = true
  auto_minor_version_upgrade   = true
  delete_automated_backups     = true
  monitoring_interval          = 60
  monitoring_role_arn          = "arn:aws:iam::958924735829:role/rds-monitoring-role"
  performance_insights_enabled = false
  database_insights_mode       = "standard"
  engine_lifecycle_support     = "open-source-rds-extended-support-disabled"

  # DeletionProtection activée (fintech). skip_final_snapshot conservé à true.
  deletion_protection = true
  skip_final_snapshot = true
  apply_immediately   = true
}

# ── S3 ───────────────────────────────────────────────────────────────────────
resource "aws_s3_bucket" "media" {
  bucket              = "market-cm"
  object_lock_enabled = false
}

# ── EC2 (prod canonique market-CM-API) ───────────────────────────────────────
resource "aws_instance" "api" {
  ami                                  = "ami-067bcf851477ebb78"
  instance_type                        = "t3.large"
  availability_zone                    = "eu-north-1b"
  subnet_id                            = "subnet-0716a414907ee5ea8"
  key_name                             = "neue-key-api"
  iam_instance_profile                 = "accessRoles3"
  associate_public_ip_address          = true
  private_ip                           = "172.31.34.90"
  ebs_optimized                        = true
  source_dest_check                    = true
  disable_api_stop                     = false
  disable_api_termination              = false
  instance_initiated_shutdown_behavior = "stop"
  monitoring                           = false
  tenancy                              = "default"
  vpc_security_group_ids               = ["sg-03833d09622cb36b0", "sg-0819d0a49a7c50f85"]
  tags                                 = { Name = "market-CM-API" }

  capacity_reservation_specification {
    capacity_reservation_preference = "open"
  }
  cpu_options {
    core_count       = 1
    threads_per_core = 2
  }
  credit_specification {
    cpu_credits = "unlimited"
  }
  enclave_options {
    enabled = false
  }
  maintenance_options {
    auto_recovery = "default"
  }
  metadata_options {
    http_endpoint               = "enabled"
    http_protocol_ipv6          = "disabled"
    http_put_response_hop_limit = 2
    http_tokens                 = "required"
    instance_metadata_tags      = "disabled"
  }
  private_dns_name_options {
    enable_resource_name_dns_a_record    = true
    enable_resource_name_dns_aaaa_record = false
    hostname_type                        = "ip-name"
  }
  root_block_device {
    delete_on_termination = true
    encrypted             = false
    iops                  = 3000
    throughput            = 125
    volume_size           = 40
    volume_type           = "gp3"
  }
}
