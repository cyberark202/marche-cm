# Marché CM — Déploiement Kubernetes (prod)

Le **docker-compose** reste la cible **locale/dev** (`backend/docker-compose.*.yml`).
Ce dossier est la cible **production** sur **Kubernetes / EKS**.

## Architecture (backend)

| Composant | K8s | Notes |
|---|---|---|
| `web` | Deployment + Service + Ingress(ALB) + HPA + PDB | Django ASGI (daphne), `/api/health/` |
| `worker-default` | Deployment (2) | Celery `-Q default,outbox -c 2` |
| `worker-financial` | Deployment (1, Recreate) | Celery `-Q financial -c 1` — **série** (intégrité financière) |
| `beat` | Deployment (1, Recreate) | Scheduler Celery — **singleton strict** |
| `finops` | Deployment (1) | Boucle `run_financial_ops` |
| `redis` | StatefulSet + PVC | ou ElastiCache (`redis.enabled=false`) |
| migrations | Job (hook `pre-install/pre-upgrade`) | `manage.py migrate` avant le rollout |

Secrets : **External Secrets Operator** ← AWS SSM Parameter Store (prod), ou
`Secret` créé depuis les valeurs (dev/CI).

## Pré-requis (outils dans `E:\tools\bin`)
`kubectl`, `helm`, `kubeconform` (déjà installés), `terraform`, `aws`, `docker`.

## 1. Provisionner l'infra EKS (Terraform)

```bash
cd infra/terraform-eks
cp terraform.tfvars.example terraform.tfvars   # renseigner vpc_id/subnets/...
terraform init
terraform apply
# Récupérer les sorties :
terraform output ecr_repository_url
terraform output app_irsa_role_arn
$(terraform output -raw configure_kubectl)     # configure kubectl
```

Crée : cluster EKS + node group managé, ECR, AWS Load Balancer Controller,
rôle IRSA app (S3 média + SSM), namespace `marche-cm`.

> Réutiliser le **VPC de RDS** (`vpc_id`/subnets) pour que les pods joignent la base.

## 2. (Prod) External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace
```
Renseigner les paramètres SSM sous `/marche-cm/prod/*` (SECRET_KEY, DATABASE_URL,
REDIS_URL, CACHE_URL, REDIS_PASSWORD, DATA_ENCRYPTION_KEY, NOTCHPAY_*, …).

## 3. Build + push de l'image

```bash
ECR_URL=$(terraform -chdir=infra/terraform-eks output -raw ecr_repository_url) \
AWS_REGION=eu-north-1 ./k8s/build-and-push.sh
```

## 4. Déployer le backend (Helm)

```bash
cp k8s/marche-cm/values-prod.example.yaml k8s/marche-cm/values-prod.yaml
# éditer: image.repository (ECR), serviceAccount role-arn (IRSA), ingress.certificateArn

helm upgrade --install marche-cm k8s/marche-cm \
  -n marche-cm --create-namespace \
  -f k8s/marche-cm/values-prod.yaml \
  --set image.tag=<sha>
```

Mode **dev sans SSM** (Secret en clair, hors-repo) :
```bash
helm upgrade --install marche-cm k8s/marche-cm -n marche-cm --create-namespace \
  --set externalSecrets.enabled=false --set secret.create=true \
  -f mes-secrets.yaml   # fichier NON committé contenant secret.data.*
```

## 5. Vérifier

```bash
kubectl -n marche-cm get pods,svc,ingress,hpa
kubectl -n marche-cm logs deploy/marche-cm-web -f
kubectl -n marche-cm get ingress marche-cm   # ADDRESS = DNS de l'ALB
```

## Validation des manifests (offline, sans cluster)

```bash
helm lint k8s/marche-cm
helm template r k8s/marche-cm | kubeconform -strict -summary -ignore-missing-schemas
```

## Notes prod
- **worker-financial** et **beat** restent à 1 réplique (jamais d'HPA) — invariants financiers / pas de tâches dupliquées.
- Migrations jouées par le **Job hook** avant chaque upgrade ; avec ESO sur le **premier** install, le Secret peut ne pas être prêt → lancer les migrations manuellement une fois (`kubectl create job --from=...` ou un premier `helm install` avec `secret.create=true`).
- Le `nginx` du compose est remplacé par l'**Ingress ALB** (TLS via ACM `certificateArn`).
- `pull_policy`/tags **immuables** (ECR `IMMUTABLE`) : taguer par `sha`.
