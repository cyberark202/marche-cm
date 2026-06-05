# Observabilité — alarmes CloudWatch (RDS + EC2) + notifications SNS.
# Métriques natives (pas d'agent requis). Pour la mémoire/disque OS de l'EC2,
# installer le CloudWatch agent ultérieurement (voir note en bas).

resource "aws_sns_topic" "alerts" {
  name = "marche-cm-alerts"
}

resource "aws_sns_topic_subscription" "alerts_email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
  # ⚠ L'abonnement reste "pending" tant que tu n'as pas cliqué le lien de
  # confirmation reçu par email.
}

locals {
  alarm_actions = [aws_sns_topic.alerts.arn]
}

# ── RDS : marchecm-postgres ──────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "marche-cm-rds-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "CPU RDS > 80% sur 15 min"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions          = { DBInstanceIdentifier = aws_db_instance.postgres.identifier }
}

resource "aws_cloudwatch_metric_alarm" "rds_storage" {
  alarm_name          = "marche-cm-rds-storage-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FreeStorageSpace"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 20000000000 # 20 Go (sur 200 alloués, autoscaling jusqu'à 1000)
  alarm_description   = "Espace disque RDS < 20 Go"
  alarm_actions       = local.alarm_actions
  dimensions          = { DBInstanceIdentifier = aws_db_instance.postgres.identifier }
}

resource "aws_cloudwatch_metric_alarm" "rds_memory" {
  alarm_name          = "marche-cm-rds-memory-low"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 1000000000 # 1 Go libre
  alarm_description   = "Mémoire libre RDS < 1 Go"
  alarm_actions       = local.alarm_actions
  dimensions          = { DBInstanceIdentifier = aws_db_instance.postgres.identifier }
}

resource "aws_cloudwatch_metric_alarm" "rds_connections" {
  alarm_name          = "marche-cm-rds-connections-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 200
  alarm_description   = "Connexions RDS > 200"
  alarm_actions       = local.alarm_actions
  dimensions          = { DBInstanceIdentifier = aws_db_instance.postgres.identifier }
}

# ── EC2 : market-CM-API ──────────────────────────────────────────────────────
resource "aws_cloudwatch_metric_alarm" "ec2_status" {
  alarm_name          = "marche-cm-ec2-status-check-failed"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  alarm_description   = "Échec status check EC2 (instance ou système)"
  alarm_actions       = local.alarm_actions
  ok_actions          = local.alarm_actions
  dimensions          = { InstanceId = aws_instance.api.id }
}

resource "aws_cloudwatch_metric_alarm" "ec2_cpu" {
  alarm_name          = "marche-cm-ec2-cpu-high"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 85
  alarm_description   = "CPU EC2 > 85% sur 15 min"
  alarm_actions       = local.alarm_actions
  dimensions          = { InstanceId = aws_instance.api.id }
}

# NOTE : mémoire & disque OS de l'EC2 ne sont pas des métriques natives — elles
# nécessitent le CloudWatch agent (à installer dans bootstrap_ec2.sh si voulu).

output "sns_alerts_topic_arn" {
  value       = aws_sns_topic.alerts.arn
  description = "Topic SNS des alertes (abonner d'autres endpoints au besoin)."
}
