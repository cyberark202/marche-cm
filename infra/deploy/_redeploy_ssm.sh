#!/usr/bin/env bash
export PATH="$PATH:/usr/local/bin:/snap/bin"
set -uo pipefail
DOMAIN="cm.digital-get.com"; APP=/opt/marche-cm
mkdir -p "$APP"; cd "$APP"

echo "== sync code (S3) =="
aws s3 cp s3://market-cm/deploy/code.tar.gz /tmp/code.tar.gz --region eu-north-1 >/dev/null
tar xzf /tmp/code.tar.gz -C "$APP"

echo "== certs + .env.aws =="
mkdir -p backend/certs
cp -L /etc/letsencrypt/live/$DOMAIN/fullchain.pem backend/certs/fullchain.pem
cp -L /etc/letsencrypt/live/$DOMAIN/privkey.pem   backend/certs/privkey.pem
bash infra/secrets/fetch_env.sh backend/.env.aws >/dev/null 2>&1
echo "  .env.aws: $(grep -c '=' backend/.env.aws) variables"

echo "== JWT keys (PEM multi-lignes -> env shell) =="
export JWT_SIGNING_KEY="$(aws ssm get-parameter --name /marche-cm/prod/JWT_SIGNING_KEY --with-decryption --region eu-north-1 --query Parameter.Value --output text)"
export JWT_VERIFYING_KEY="$(aws ssm get-parameter --name /marche-cm/prod/JWT_VERIFYING_KEY --with-decryption --region eu-north-1 --query Parameter.Value --output text)"
echo "  signing=${#JWT_SIGNING_KEY}c verifying=${#JWT_VERIFYING_KEY}c"

DC=(docker compose -f backend/docker-compose.aws.yml --project-directory backend --env-file backend/.env.aws)
export COMPOSE_BAKE=false DOCKER_BUILDKIT=1
echo "== up -d (recreate) =="
"${DC[@]}" up -d 2>&1 | grep -vE 'variable is not set|obsolete' | tail -20
sleep 20
# nginx garde en cache l'IP du conteneur web (résolue au démarrage) : si web a
# été recréé, son IP change -> on relance nginx pour re-résoudre l'upstream.
"${DC[@]}" restart nginx >/dev/null 2>&1 || true
sleep 3

echo "== ps =="
"${DC[@]}" ps --format '{{.Service}}  {{.Status}}'
echo "== web logs (migrate/daphne) =="
"${DC[@]}" logs --tail=25 web 2>&1 | grep -vE 'variable is not set|obsolete' | tail -25
echo "== health =="
ok=0
for i in $(seq 1 12); do
  c=$(curl -s -o /dev/null -w '%{http_code}' http://localhost:8000/api/health/ 2>/dev/null||echo 000)
  p=$(curl -s -o /dev/null -w '%{http_code}' https://$DOMAIN/api/health/ 2>/dev/null||echo 000)
  echo "  web:8000=$c  public=$p"
  if [ "$p" = "200" ]; then echo "PUBLIC-OK"; ok=1; break; fi
  sleep 6
done
[ "$ok" = 1 ] || echo "encore KO — voir logs ci-dessus"
