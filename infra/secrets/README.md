# Secrets — AWS SSM Parameter Store

Les secrets de l'app ne vivent plus dans un `.env` en clair : ils sont stockés
**chiffrés** dans SSM Parameter Store sous `/marche-cm/prod/*`, et l'EC2 les lit
au déploiement via son **rôle d'instance** `accessRoles3` (aucune clé statique).

## Schéma

```
  values.local.env (toi, local)        SSM Parameter Store            EC2 (déploiement)
  ├─ secrets externes  ─ put_parameters.ps1 ─►  /marche-cm/prod/*  ─ fetch_env.sh ─►  .env.aws
  └─ (Django générés auto)                       (SecureString/String)                 │
                                                                         docker compose up
```

## Paramètres

| Nom (`/marche-cm/prod/…`) | Type | Source |
|---|---|---|
| `SECRET_KEY`, `DATA_ENCRYPTION_KEY`, `REDIS_PASSWORD`, `DEVICE_FINGERPRINT_SECRET` | SecureString | **généré** par put_parameters.ps1 |
| `DB_PASSWORD` | SecureString | toi (mot de passe maître RDS) |
| `NOTCHPAY_*` (4) | SecureString | toi (clés live) |
| `EMAIL_HOST_PASSWORD` | SecureString | toi |
| `DB_HOST/PORT/USER/NAME/SSLMODE`, `AWS_*`, `EMAIL_HOST/USER`, `DEFAULT_FROM_EMAIL`, `ALLOWED_HOSTS`, `BACKEND_PUBLIC_URL` | String | config |

`DATABASE_URL` est **assemblée** sur l'EC2 par `fetch_env.sh` (URL-encode du mot de passe).

## Utilisation

```powershell
# 1. (une fois) IAM d'accès EC2 -> SSM/S3 : appliqué via Terraform (infra/terraform/ssm_access.tf)
# 2. Renseigner les vrais secrets externes
cp infra/secrets/values.local.env.example infra/secrets/values.local.env   # puis éditer
# 3. Pousser dans SSM (génère aussi les secrets Django)
powershell -File infra/secrets/put_parameters.ps1
```

Au déploiement, l'EC2 exécute `fetch_env.sh .env.aws` puis
`docker compose -f docker-compose.aws.yml --env-file .env.aws up -d`.

## Sécurité
- `values.local.env` et `.env.aws` sont **gitignorés** (jamais committés).
- Secrets en SecureString (chiffrés KMS). Accès EC2 limité au préfixe `/marche-cm/prod/*`.
- Rotation : modifier la valeur (`put_parameters.ps1` ré-exécuté) puis redéployer.
  Pour une rotation automatique, basculer `DB_PASSWORD` vers Secrets Manager.
