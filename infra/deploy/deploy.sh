#!/usr/bin/env bash
# Déploiement de l'app sur market-CM-API. Exécuté SUR l'EC2 (par la GitHub Action,
# après rsync de backend/ + infra/ dans /opt/marche-cm). Idempotent.
#
# Layout EC2 attendu :
#   /opt/marche-cm/backend/docker-compose.aws.yml   (compose, contexte build = backend/)
#   /opt/marche-cm/infra/secrets/fetch_env.sh
#   /opt/marche-cm/infra/deploy/deploy.sh   (ce script)
set -euo pipefail

DOMAIN="cm.digital-get.com"
APP_DIR="/opt/marche-cm"
COMPOSE="backend/docker-compose.aws.yml"
# Relatif au compose (backend/) — d'où --project-directory backend.
DC=(docker compose -f "$COMPOSE" --project-directory backend --env-file backend/.env.aws)
cd "$APP_DIR"

echo "== 1. Certificats TLS -> backend/certs =="
mkdir -p backend/certs
if [ -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  cp -L "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" backend/certs/fullchain.pem
  cp -L "/etc/letsencrypt/live/$DOMAIN/privkey.pem"   backend/certs/privkey.pem
else
  echo "⚠ Pas de certificat Let's Encrypt — lance d'abord infra/deploy/bootstrap_ec2.sh"
fi

echo "== 2. Génération du .env.aws depuis SSM (rôle d'instance) =="
bash infra/secrets/fetch_env.sh backend/.env.aws

echo "== 3. Build + (re)démarrage des conteneurs =="
"${DC[@]}" up -d --build --remove-orphans

echo "== 4. Collectstatic (volume servi par nginx) =="
"${DC[@]}" run --rm web python manage.py collectstatic --noinput || true

echo "== 5. Préflight (gate de prod) =="
"${DC[@]}" run --rm web python manage.py preflight || echo "⚠ preflight a signalé un problème (voir ci-dessus)."

echo "== 6. Healthcheck =="
ok=0
for i in $(seq 1 12); do
  if curl -fsS "https://$DOMAIN/api/health/" >/dev/null 2>&1; then echo "→ Santé OK"; ok=1; break; fi
  echo "  attente du service… ($i/12)"; sleep 5
done
[ "$ok" = 1 ] || { echo "✗ Healthcheck KO"; "${DC[@]}" logs --tail=50 web nginx; exit 1; }

echo "== 7. Ménage images =="
docker image prune -f >/dev/null 2>&1 || true
echo "== Déploiement terminé =="
