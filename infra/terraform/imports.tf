# Adoption de l'infra EXISTANTE via import blocks (Terraform 1.5+).
# Aucune ressource n'est créée : ces blocs rattachent l'existant à l'état Terraform.
# Génération du HCL correspondant :
#   terraform plan -generate-config-out=generated.tf
# Puis on relit generated.tf, on lance `terraform plan` et on vise "No changes".
#
# IDs relevés le 2026-06-04 (eu-north-1, compte 958924735829) — cf. INVENTORY.md.

# ── S3 ───────────────────────────────────────────────────────────────────────
import {
  to = aws_s3_bucket.media
  id = "market-cm"
}

# ── RDS ──────────────────────────────────────────────────────────────────────
import {
  to = aws_db_instance.postgres
  id = "marchecm-postgres"
}
import {
  to = aws_db_subnet_group.rds
  id = "rds-ec2-db-subnet-group-1"
}

# ── Sous-réseaux privés dédiés RDS (custom, non-défaut) ──────────────────────
import {
  to = aws_subnet.rds_1
  id = "subnet-02149f54ff8bd6afa" # RDS-Pvt-subnet-1 (eu-north-1a)
}
import {
  to = aws_subnet.rds_2
  id = "subnet-0f9d62c77fb7280c1" # RDS-Pvt-subnet-2 (eu-north-1b)
}
import {
  to = aws_subnet.rds_3
  id = "subnet-0fbbcef65bad04e66" # RDS-Pvt-subnet-3 (eu-north-1-cph-1a)
}
import {
  to = aws_subnet.rds_4
  id = "subnet-068e00df939c6941d" # RDS-Pvt-subnet-4 (eu-north-1c)
}

# ── Security groups ──────────────────────────────────────────────────────────
import {
  to = aws_security_group.group_secure_marketcm
  id = "sg-083d7a0e9c9eed317"
}
import {
  to = aws_security_group.ec2_rds
  id = "sg-0819d0a49a7c50f85"
}
import {
  to = aws_security_group.rds_ec2
  id = "sg-0650f15be757d09e3"
}
import {
  to = aws_security_group.launch_wizard_1
  id = "sg-03833d09622cb36b0"
}
import {
  to = aws_security_group.secure_group_mcm
  id = "sg-0883ba2a8933d59ba"
}

# ── EC2 (prod canonique) + Elastic IP ────────────────────────────────────────
import {
  to = aws_instance.api
  id = "i-09e104c1cd49c757e" # market-CM-API
}
import {
  to = aws_eip.api
  id = "eipalloc-0b7ac1be31be19bfa" # 16.170.68.148
}

# ── IAM ──────────────────────────────────────────────────────────────────────
import {
  to = aws_iam_role.ec2_s3
  id = "accessRoles3"
}
import {
  to = aws_iam_instance_profile.ec2_s3
  id = "accessRoles3"
}
import {
  to = aws_iam_role.rds_monitoring
  id = "rds-monitoring-role"
}
