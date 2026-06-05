# Déploiement — market-CM-API (AWS EC2)

CI/CD : **build sur l'EC2**. GitHub Actions teste (CI existant) → rsync du code →
`deploy.sh` sur l'EC2 (build + compose up). Domaine **cm.digital-get.com**, TLS
Let's Encrypt. App servie par `backend/docker-compose.aws.yml` (nginx + daphne +
redis + finops).

## Architecture

```
 push main ─► CI (tests) ─► Deploy workflow ─► rsync backend/+infra/ ─► EC2 /opt/marche-cm
                                                                            │
                              bootstrap (1x) : docker+certbot+cert          ▼
                                                            deploy.sh : fetch_env(SSM) + compose up --build
```

## Prérequis (une fois)

### 1. DNS
Créer un enregistrement **A** : `cm.digital-get.com` → **16.170.68.148**.
Vérifier : `nslookup cm.digital-get.com` avant le bootstrap (sinon Let's Encrypt échoue).

### 2. Secrets SSM peuplés
Voir `infra/secrets/README.md` : remplir `values.local.env` puis
`powershell -File infra/secrets/put_parameters.ps1`. **ALLOWED_HOSTS** et
**BACKEND_PUBLIC_URL** doivent valoir `cm.digital-get.com` / `https://cm.digital-get.com`.

### 3. Clé SSH (instance `neue-key-api`)
La GitHub Action et le bootstrap se connectent en `ubuntu@`. Il faut la **clé privée
OpenSSH** correspondant à `neue-key-api`. Si tu n'as que `Aws/new-key-api.ppk`
(format PuTTY), la convertir :
```
puttygen Aws\new-key-api.ppk -O private-openssh -o neue-key-api.pem
```

### 4. Secrets GitHub (repo → Settings → Secrets and variables → Actions)
| Secret | Valeur |
|---|---|
| `EC2_SSH_KEY` | contenu de `neue-key-api.pem` (clé privée OpenSSH) |
| `EC2_HOST` | `cm.digital-get.com` (ou `16.170.68.148`) |

### 5. Bootstrap de l'EC2 (une fois)
```bash
ssh -i neue-key-api.pem ubuntu@cm.digital-get.com 'sudo bash -s' < infra/deploy/bootstrap_ec2.sh
```
Installe docker + compose + certbot et émet le certificat TLS.

## Déploiement

- **Auto** : à chaque push sur `main`, après le CI vert, le workflow `Deploy` se lance.
- **Manuel** : onglet *Actions* → *Deploy — market-CM-API* → *Run workflow*.

Le déploiement : rsync → `deploy.sh` → `fetch_env.sh` (lit SSM via le rôle EC2) →
`docker compose up -d --build` → collectstatic → `preflight` → healthcheck HTTPS.

## Webhooks NotchPay (après 1er déploiement)
Pointer le dashboard NotchPay vers :
- `https://cm.digital-get.com/api/wallets/notchpay/checkout/webhook/`
- `https://cm.digital-get.com/api/wallets/notchpay/disburse/webhook/`

## Smoke tests
```
curl -fsS https://cm.digital-get.com/api/health/        # 200
```
Upload KYC → objet visible dans le bucket S3 `market-cm` (pas sur le disque EC2).

## Bascule depuis Render
Quand AWS est validé : pointer le domaine public des apps Flutter
(`--dart-define=API_BASE_URL=https://cm.digital-get.com`) puis rebuild/redeploy des apps.
