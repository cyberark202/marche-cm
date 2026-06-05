#!/usr/bin/env bash
# Déploiement de l'app via SSM : code depuis S3 -> build -> up. Idempotent.
set -uo pipefail
DOMAIN="cm.digital-get.com"
APP=/opt/marche-cm
export DEBIAN_FRONTEND=noninteractive

echo "== 0. Pre-requis =="
export PATH="$PATH:/usr/local/bin:/snap/bin"
if ! command -v aws >/dev/null 2>&1; then
  echo "Installation AWS CLI v2..."
  apt-get update -y -qq; apt-get install -y -qq unzip curl
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  (cd /tmp && unzip -oq awscliv2.zip && ./aws/install --update)
  hash -r
fi
echo "aws: $(aws --version 2>&1 | head -1)"
systemctl start docker 2>/dev/null || true
echo "compose: $(docker compose version 2>/dev/null || echo ABSENT)"

echo "== 1. Code depuis S3 =="
mkdir -p "$APP"
aws s3 cp s3://market-cm/deploy/code.tar.gz /tmp/code.tar.gz --region eu-north-1
tar xzf /tmp/code.tar.gz -C "$APP"
echo "contenu: $(ls "$APP")"

echo "== 2. Certificats -> backend/certs =="
mkdir -p "$APP/backend/certs"
cp -L /etc/letsencrypt/live/$DOMAIN/fullchain.pem "$APP/backend/certs/fullchain.pem"
cp -L /etc/letsencrypt/live/$DOMAIN/privkey.pem   "$APP/backend/certs/privkey.pem"

echo "== 3. .env.aws depuis SSM =="
cd "$APP"
bash infra/secrets/fetch_env.sh backend/.env.aws
echo "  variables: $(grep -c '=' backend/.env.aws)"
export JWT_SIGNING_KEY="$(aws ssm get-parameter --name /marche-cm/prod/JWT_SIGNING_KEY --with-decryption --region eu-north-1 --query Parameter.Value --output text)"
export JWT_VERIFYING_KEY="$(aws ssm get-parameter --name /marche-cm/prod/JWT_VERIFYING_KEY --with-decryption --region eu-north-1 --query Parameter.Value --output text)"

echo "== 3b. S'assurer que la base existe sur RDS =="
set -a; source backend/.env.aws; set +a
command -v psql >/dev/null 2>&1 || apt-get install -y -qq postgresql-client
export PGPASSWORD="${DB_PASSWORD:-}"
CONN="host=$DB_HOST port=${DB_PORT:-5432} user=$DB_USER dbname=postgres sslmode=require"
if psql "$CONN" -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" 2>/dev/null | grep -q 1; then
  echo "  base '${DB_NAME}' existe deja"
else
  echo "  creation de la base '${DB_NAME}'"
  psql "$CONN" -c "CREATE DATABASE \"${DB_NAME}\"" && echo "  cree" || echo "  ECHEC creation base"
fi
unset PGPASSWORD

echo "== 4. Build + up =="
DC=(docker compose -f backend/docker-compose.aws.yml --project-directory backend --env-file backend/.env.aws)
"${DC[@]}" up -d --build --remove-orphans

echo "== 5. Collectstatic =="
"${DC[@]}" run --rm web python manage.py collectstatic --noinput 2>&1 | tail -3 || true

echo "== 6. Etat des conteneurs =="
"${DC[@]}" ps

echo "== 7. Healthcheck HTTPS =="
ok=0
for i in $(seq 1 18); do
  code=$(curl -s -o /dev/null -w '%{http_code}' "https://$DOMAIN/api/health/" 2>/dev/null || echo 000)
  echo "  try $i: HTTP $code"
  if [ "$code" = "200" ]; then echo "HEALTH-OK"; ok=1; break; fi
  sleep 5
done
if [ "$ok" != 1 ]; then echo "HEALTH-KO — logs web:"; "${DC[@]}" logs --tail=40 web; fi
echo "== fin deploy =="
