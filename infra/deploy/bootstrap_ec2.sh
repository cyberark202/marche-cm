#!/usr/bin/env bash
# Bootstrap UNIQUE de l'EC2 market-CM-API (Ubuntu). À lancer une fois, en SSH :
#   ssh -i <clé neue-key-api>.pem ubuntu@cm.digital-get.com 'sudo bash -s' < bootstrap_ec2.sh
#
# Pré-requis : cm.digital-get.com doit DÉJÀ pointer (A record) vers 16.170.68.148
# (sinon l'émission Let's Encrypt échoue).
set -euo pipefail

DOMAIN="cm.digital-get.com"
EMAIL="${CERTBOT_EMAIL:-admin@digital-get.com}"   # passer CERTBOT_EMAIL=... si besoin
APP_DIR="/opt/marche-cm"

echo "== 1. Paquets système =="
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y ca-certificates curl gnupg git rsync awscli certbot

echo "== 2. Docker + compose plugin =="
if ! command -v docker >/dev/null; then
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi
usermod -aG docker ubuntu || true
systemctl enable --now docker

echo "== 3. Arborescence app =="
mkdir -p "$APP_DIR"
chown -R ubuntu:ubuntu "$APP_DIR"

echo "== 4. Certificat Let's Encrypt ($DOMAIN) =="
# Émission en standalone (rien n'écoute encore sur 80). deploy.sh recopie ensuite
# les certs dans backend/certs (monté par nginx). Renouvellement : hook ci-dessous.
if [ ! -d "/etc/letsencrypt/live/$DOMAIN" ]; then
  certbot certonly --standalone --non-interactive --agree-tos -m "$EMAIL" -d "$DOMAIN"
fi

echo "== 5. Renouvellement auto (hook : recopie dans backend/certs + reload nginx) =="
cat > /etc/letsencrypt/renewal-hooks/deploy/marche-cm.sh <<HOOK
#!/usr/bin/env bash
B="$APP_DIR/backend"
mkdir -p "\$B/certs"
cp -L "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" "\$B/certs/fullchain.pem"
cp -L "/etc/letsencrypt/live/$DOMAIN/privkey.pem"   "\$B/certs/privkey.pem"
cd "$APP_DIR" && docker compose -f backend/docker-compose.aws.yml --project-directory backend exec -T nginx nginx -s reload || true
HOOK
chmod +x /etc/letsencrypt/renewal-hooks/deploy/marche-cm.sh

echo "== Bootstrap terminé =="
echo "Prochaine étape : pousser le code (GitHub Action deploy) puis deploy.sh."
