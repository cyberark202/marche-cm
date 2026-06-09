# Déploiement AWS — EC2 (VPS) + RDS PostgreSQL + S3

Date : 2026-06-04
Portée : héberger le backend Marché CM sur un **VPS AWS EC2**, avec base de
données **RDS PostgreSQL managée** et stockage des médias sur **S3**.

> Alternative managée tout-en-un : `docs/RENDER_DEPLOIEMENT.md`. Ce document
> couvre le scénario **AWS auto-géré sur EC2** demandé. Fichier compose associé :
> `backend/docker-compose.aws.yml`.

---

## 0. Architecture cible

```
                Internet
                   │  443 (HTTPS)
            ┌──────▼───────┐
            │  EC2 (VPS)   │  Docker Compose : nginx + daphne(web) + redis + finops
            │  nginx ──► web (ASGI:8000)                         │
            └──┬────────┬──┘                                     │
   5432 (TLS)  │        │  443 (HTTPS, API S3)                   │
        ┌──────▼──┐  ┌──▼─────────┐                             │
        │  RDS    │  │   S3        │  (médias : KYC, preuves,    │
        │ Postgres│  │  bucket     │   images produit)           │
        └─────────┘  └─────┬───────┘                             │
                           │ (optionnel) CloudFront CDN ─────────┘
```

- **EC2** : calcul (conteneurs). Redis reste local au conteneur (option ElastiCache).
- **RDS** : base managée (backups auto, patches, Multi-AZ possible).
- **S3** : médias persistants (indispensable : un EC2 est éphémère/remplaçable).
- **CloudFront** (optionnel) : CDN devant S3 pour servir les images publiques vite.

---

## 1. Pré-requis AWS

| Ressource | Détail |
|---|---|
| VPC | 1 VPC, 2 sous-réseaux (public pour EC2, privés pour RDS — bonne pratique) |
| EC2 | Ubuntu 22.04+, t3.small mini (2 vCPU / 2 Go), EBS 20 Go gp3 |
| RDS | PostgreSQL 16, db.t4g.micro mini, stockage chiffré (KMS), Multi-AZ recommandé en prod |
| S3 | 1 bucket privé (ex. `marche-cm-media`) dans la même région que l'EC2 |
| IAM | 1 utilisateur (ou rôle EC2) avec accès **least-privilege** au bucket |
| Elastic IP | attachée à l'EC2 (IP stable pour DNS + allowlist) |

### Security Groups
- **sg-ec2** : entrant 80/443 depuis `0.0.0.0/0`, 22 depuis votre IP admin uniquement.
- **sg-rds** : entrant 5432 **depuis `sg-ec2` uniquement** (jamais public).

---

## 2. RDS PostgreSQL

1. Créer l'instance RDS PostgreSQL 16, `Publicly accessible = No`, dans `sg-rds`.
2. Activer le chiffrement au repos (KMS) + backups automatiques (7 j mini).
3. Noter l'endpoint : `marche-cm.xxxx.eu-west-3.rds.amazonaws.com`.
4. Le backend force le TLS via `DB_SSLMODE=require` (déjà câblé dans `settings.py`).
   Pour la vérification stricte du certificat (`verify-full`), télécharger le
   bundle CA RDS et le monter dans le conteneur :
   ```bash
   curl -o certs/rds-global-bundle.pem \
     https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
   # puis : DB_SSLMODE=verify-full  DB_SSLROOTCERT=/etc/nginx/certs/rds-global-bundle.pem
   ```
5. `DATABASE_URL` =
   `postgres://USER:PASSWORD@marche-cm.xxxx.eu-west-3.rds.amazonaws.com:5432/marchecm`

> ⚠️ Mot de passe RDS : caractères spéciaux à **URL-encoder** dans `DATABASE_URL`
> (`@`→`%40`, `:`→`%3A`, etc.). Le parseur les décode (`unquote`).

---

## 3. S3 (médias)

1. Créer le bucket `marche-cm-media` (région = celle de l'EC2), **Block Public
   Access = ON** (on sert via URLs signées ou via CloudFront/OAC).
2. Activer le chiffrement SSE-S3 (ou SSE-KMS) par défaut.
3. CORS (uploads/affichage depuis les apps) — `Permissions ▸ CORS` :
   ```json
   [
     {
       "AllowedOrigins": ["https://app.marche-cm.com", "https://api.marche-cm.com"],
       "AllowedMethods": ["GET", "PUT", "POST", "HEAD"],
       "AllowedHeaders": ["*"],
       "ExposeHeaders": ["ETag"],
       "MaxAgeSeconds": 3000
     }
   ]
   ```
4. **IAM least-privilege** — politique attachée à l'utilisateur/rôle backend :
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Sid": "MarcheCmObjectAccess",
         "Effect": "Allow",
         "Action": ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"],
         "Resource": "arn:aws:s3:::marche-cm-media/*"
       },
       {
         "Sid": "MarcheCmListBucket",
         "Effect": "Allow",
         "Action": ["s3:ListBucket", "s3:GetBucketLocation"],
         "Resource": "arn:aws:s3:::marche-cm-media"
       }
     ]
   }
   ```
   > Préférer un **rôle IAM attaché à l'EC2** (pas de clés en clair). Dans ce cas,
   > laisser `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` vides : boto3 utilise le
   > rôle d'instance automatiquement.

### Confidentialité des médias sensibles
KYC et preuves de livraison sont **sensibles**. Deux stratégies :
- **Bucket privé + `AWS_QUERYSTRING_AUTH=True`** → URLs signées expirantes (recommandé pour KYC).
- **CloudFront + OAC** devant le bucket privé, `AWS_S3_CUSTOM_DOMAIN=dXXXX.cloudfront.net`
  pour les images produit publiques (perf CDN).

---

## 4. Réglages backend déjà câblés (à vérifier)

`backend/config/settings.py` (vérifié cette passe) :
- **Stockage** : réglage **`STORAGES`** (API Django 5.x). `USE_S3_STORAGE=True`
  bascule `STORAGES["default"]` sur `S3Boto3Storage`. ⚠️ Les anciens
  `DEFAULT_FILE_STORAGE`/`STATICFILES_STORAGE` sont **ignorés** par Django 5.1 —
  ne pas s'y fier (corrigé : on passe désormais par `STORAGES`).
- **TLS RDS** : `DB_SSLMODE` (+ `DB_SSLROOTCERT` optionnel) injectés dans
  `DATABASES["default"]["OPTIONS"]`.
- **Static** : WhiteNoise (`CompressedManifestStaticFilesStorage`) via `STORAGES["staticfiles"]`.

Variables d'env (cf. `backend/.env.aws.example`) — bloc bloquant :

```env
DEBUG=False
SECRET_KEY=<aléatoire ≥50 chars>
DATA_ENCRYPTION_KEY=<clé Fernet>
ALLOWED_HOSTS=api.marche-cm.com
BACKEND_PUBLIC_URL=https://api.marche-cm.com
USE_X_FORWARDED_PROTO=True
SECURE_SSL_REDIRECT=True

# RDS
DATABASE_URL=postgres://USER:PASS@<rds-endpoint>:5432/marchecm
DB_SSLMODE=require

# Redis (conteneur EC2)
REDIS_PASSWORD=<aléatoire>

# S3
USE_S3_STORAGE=True
REQUIRE_REMOTE_PROOF_STORAGE=True
AWS_STORAGE_BUCKET_NAME=marche-cm-media
AWS_S3_REGION_NAME=eu-west-3
AWS_ACCESS_KEY_ID=...      # vide si rôle IAM EC2
AWS_SECRET_ACCESS_KEY=...  # vide si rôle IAM EC2

# NotchPay (live)
NOTCHPAY_ENABLED=True
NOTCHPAY_MODE=live
NOTCHPAY_PUBLIC_KEY=...
NOTCHPAY_PRIVATE_KEY=...
NOTCHPAY_CHECKOUT_WEBHOOK_SECRET=<obligatoire>
NOTCHPAY_DISBURSE_WEBHOOK_SECRET=<obligatoire>

# Email
EMAIL_HOST=smtp.sendgrid.net
EMAIL_HOST_USER=...
EMAIL_HOST_PASSWORD=...
DEFAULT_FROM_EMAIL=no-reply@marche-cm.com
```

---

## 5. Mise en route sur l'EC2

```bash
# 1. Docker + compose
sudo apt-get update && sudo apt-get install -y docker.io docker-compose-plugin
sudo usermod -aG docker $USER && newgrp docker

# 2. Récupérer le code
git clone <repo> && cd "Marché CM/backend"

# 3. Renseigner les secrets
cp .env.aws.example .env.aws && nano .env.aws

# 4. TLS : certificat (Let's Encrypt via certbot, ou ACM derrière un ALB)
#    Déposer fullchain.pem + privkey.pem dans backend/certs/ (cf. nginx.conf)

# 5. Démarrer (migrate auto au lancement du service web)
docker compose -f docker-compose.aws.yml --env-file .env.aws up -d --build

# 6. Collectstatic (une fois, vers le volume servi par nginx)
docker compose -f docker-compose.aws.yml --env-file .env.aws \
  run --rm web python manage.py collectstatic --noinput

# 7. Superuser admin (rôle GENERAL_ADMIN)
docker compose -f docker-compose.aws.yml --env-file .env.aws \
  run --rm web python manage.py createsuperuser

# 8. Préflight (gate de prod) + healthcheck
docker compose -f docker-compose.aws.yml --env-file .env.aws \
  run --rm web python manage.py preflight
curl -fsS https://api.marche-cm.com/api/health/
```

---

## 6. Webhooks NotchPay

Dashboard NotchPay → pointer vers l'EC2 (HTTPS) :
- Checkout : `https://api.marche-cm.com/api/wallets/notchpay/checkout/webhook/`
- Disburse : `https://api.marche-cm.com/api/wallets/notchpay/disburse/webhook/`
- Renseigner les secrets HMAC correspondants (sinon **403** — voulu).

> Le paiement in-app **Direct Charge** (mobile money) initialise puis charge le
> paiement côté serveur : NotchPay pousse une demande USSD sur le téléphone du
> client. La confirmation finale arrive par le webhook checkout ci-dessus —
> donc ces webhooks sont **indispensables** même en flux in-app.

Si le compte NotchPay impose une **allowlist IP** pour l'API Transfer/Charge :
ajouter l'**Elastic IP** de l'EC2.

---

## 7. Smoke tests post-déploiement

- [ ] `GET /api/health/` → 200
- [ ] `POST /api/auth/login/` (compte test) → tokens
- [ ] Upload KYC → l'objet apparaît **dans le bucket S3** (pas sur le disque EC2)
- [ ] `python manage.py preflight` → vert (vérifie RDS, S3, secrets webhooks)
- [ ] Recharge wallet mobile money → push USSD reçu, statut PENDING→SUCCESS après webhook
- [ ] Webhook checkout signé → 200 ; non signé → 403
- [ ] Redémarrer l'EC2 → les médias restent accessibles (preuve que S3 ≠ disque local)

---

## 8. Sauvegarde, MAJ, observabilité

- **RDS** : snapshots auto + snapshot manuel avant migration majeure.
- **S3** : activer le versioning du bucket (récupération d'objets supprimés).
- **MAJ applicative** : `git pull` puis
  `docker compose -f docker-compose.aws.yml --env-file .env.aws up -d --build`
  (le service `web` rejoue `migrate` au démarrage).
- **Logs** : `docker compose logs -f web nginx`. Métriques Prometheus sur
  `/metrics/` (réservé `GENERAL_ADMIN`).
- **Rollback** : conserver l'image Docker précédente (`IMAGE_TAG`) ; migrations
  réversibles.

---

## 9. Go / No-Go

**GO** si : RDS joignable en TLS (`DB_SSLMODE=require`), upload KYC visible dans
S3, `preflight` vert, secrets webhooks en place, smoke tests §7 OK, EC2 derrière
HTTPS valide.

**NO-GO** tant que : S3 non effectif (médias sur disque EC2 = perte à chaque
remplacement d'instance), `DB_SSLMODE` absent, `REQUIRE_REMOTE_PROOF_STORAGE`
non respecté, ou secrets webhooks manquants.
