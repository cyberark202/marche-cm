#!/usr/bin/env bash
# Génère le fichier d'environnement de l'app à partir de SSM Parameter Store.
# À exécuter SUR l'EC2 market-CM-API (utilise le rôle d'instance accessRoles3 —
# aucune clé statique). Lancé par le déploiement avant `docker compose up`.
#
#   ./fetch_env.sh /chemin/vers/.env.aws
set -euo pipefail

PREFIX="/marche-cm/prod"
REGION="${AWS_REGION:-eu-north-1}"
OUT="${1:-.env.aws}"
TMP="$(mktemp)"

echo "→ Lecture de $PREFIX depuis SSM ($REGION)…"

# Récupère tous les paramètres (déchiffrés) en paires NAME<TAB>VALUE.
# Parsing en JSON via python3 : robuste pour les valeurs contenant des virgules
# (ex. ALLOWED_HOSTS) ou autres caractères, contrairement à --output text.
# Les clés JWT (PEM multi-lignes) sont exclues : injectées via l'environnement
# shell (compose ${VAR}) par le script de déploiement.
aws ssm get-parameters-by-path \
  --path "$PREFIX" --recursive --with-decryption \
  --region "$REGION" --output json \
  | python3 -c '
import json, sys
data = json.load(sys.stdin)
skip = {"JWT_SIGNING_KEY", "JWT_VERIFYING_KEY"}
for p in data.get("Parameters", []):
    key = p["Name"].rsplit("/", 1)[-1]
    if key in skip:
        continue
    sys.stdout.write("%s=%s\n" % (key, p["Value"]))
' > "$TMP"

# Charge les valeurs pour assembler DATABASE_URL.
# shellcheck disable=SC1090
set -a; source "$TMP"; set +a

# URL-encode du mot de passe (caractères spéciaux).
enc_pw="$(python3 -c "import urllib.parse,os;print(urllib.parse.quote(os.environ.get('DB_PASSWORD',''), safe=''))")"
DATABASE_URL="postgres://${DB_USER}:${enc_pw}@${DB_HOST}:${DB_PORT}/${DB_NAME}"

{
  cat "$TMP"
  echo "DATABASE_URL=${DATABASE_URL}"
  # Constantes de prod non stockées dans SSM
  echo "DEBUG=False"
  echo "USE_S3_STORAGE=True"
  echo "REQUIRE_REMOTE_PROOF_STORAGE=True"
  echo "SECURE_SSL_REDIRECT=True"
  echo "USE_X_FORWARDED_PROTO=True"
  echo "NOTCHPAY_ENABLED=True"
  echo "NOTCHPAY_MODE=live"
} > "$OUT"

chmod 600 "$OUT"
rm -f "$TMP"
echo "→ Écrit : $OUT ($(grep -c '=' "$OUT") variables)"
