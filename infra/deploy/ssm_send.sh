#!/usr/bin/env bash
# Lance le déploiement sur l'EC2 via SSM (utilisé par GitHub Actions, runner Linux).
# Auth : rôle OIDC assumé par le workflow (cf. cicd_oidc.tf). Pas de clé statique.
set -euo pipefail
REGION="${AWS_REGION:-eu-north-1}"
INSTANCE="${DEPLOY_INSTANCE_ID:-i-09e104c1cd49c757e}"

# Séquence exécutée sur l'EC2 : re-sync du bundle (déjà uploadé sur S3 par le job)
# puis déploiement. Chaque entrée = une ligne du script (cd persiste).
PARAMS='{"commands":[
  "export PATH=$PATH:/usr/local/bin:/snap/bin",
  "mkdir -p /opt/marche-cm && cd /opt/marche-cm",
  "aws s3 cp s3://market-cm/deploy/code.tar.gz /tmp/code.tar.gz --region eu-north-1",
  "tar xzf /tmp/code.tar.gz -C /opt/marche-cm",
  "bash infra/deploy/_redeploy_ssm.sh"
]}'

CID=$(aws ssm send-command --region "$REGION" --instance-ids "$INSTANCE" \
  --document-name AWS-RunShellScript --comment "GitHub Actions deploy" \
  --parameters "$PARAMS" --query Command.CommandId --output text)
echo "CommandId=$CID"
sleep 5

for i in $(seq 1 90); do
  STATUS=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CID" \
    --instance-id "$INSTANCE" --query Status --output text 2>/dev/null || echo Pending)
  echo "[$i] status=$STATUS"
  case "$STATUS" in Success|Failed|Cancelled|TimedOut) break ;; esac
  sleep 10
done

echo "----- STDOUT -----"
aws ssm get-command-invocation --region "$REGION" --command-id "$CID" --instance-id "$INSTANCE" --query StandardOutputContent --output text
echo "----- STDERR -----"
aws ssm get-command-invocation --region "$REGION" --command-id "$CID" --instance-id "$INSTANCE" --query StandardErrorContent --output text || true
FINAL=$(aws ssm get-command-invocation --region "$REGION" --command-id "$CID" --instance-id "$INSTANCE" --query Status --output text)
echo "FINAL=$FINAL"
[ "$FINAL" = "Success" ] || exit 1
