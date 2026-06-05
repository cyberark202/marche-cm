# Terraform — Infra AWS Marché CM (compte `central-market`)

Codifie l'infrastructure AWS **déjà créée** (VPC, EC2 `market-CM-API`, RDS, S3,
IAM, Security Groups, Elastic IP). Approche **import** : on ne recrée rien, on
adopte l'existant dans l'état Terraform pour le gérer ensuite proprement.

> ⚠️ Aucune ressource n'est créée/détruite sans validation explicite. Le flux
> normal est : `terraform plan` → on relit ensemble → `terraform apply` seulement
> après accord. Pour l'adoption initiale, on utilise `terraform import` (ne
> modifie pas l'infra, remplit juste l'état local).

---

## 0. Pré-requis (une fois)

1. **Outils** : AWS CLI v2 + Terraform ≥ 1.6 (installés via winget).
2. **Profil AWS** — à configurer **par toi** (le secret ne transite pas par le chat) :
   ```powershell
   # Dans la console AWS : IAM → Users → central-market → Security credentials
   #   → Create access key → "Command Line Interface (CLI)"
   aws configure --profile central-market_credentials
   #   AWS Access Key ID     : <coller>
   #   AWS Secret Access Key  : <coller>
   #   Default region name    : <la région de l'infra, ex. eu-west-3>
   #   Default output format  : json
   ```
3. **Vérifier l'accès** :
   ```powershell
   aws sts get-caller-identity --profile central-market_credentials
   # → doit afficher Account "958924735829" et l'ARN de central-market
   ```

---

## 1. Inventaire (read-only)

```powershell
pwsh -File infra/terraform/inventory.ps1 -Profile central-market_credentials
# (ajouter -Region xxx si le profil n'a pas de région par défaut)
```
Génère `infra/terraform/inventory/*.json`. On s'en sert pour écrire les `.tf` et
récupérer les IDs nécessaires aux `terraform import`.

---

## 2. Structure

```
infra/terraform/
├── versions.tf        # versions providers + (option) backend S3 d'état
├── providers.tf       # provider aws (profil + région + tags par défaut)
├── variables.tf       # variables d'entrée
├── terraform.tfvars   # valeurs réelles (gitignoré) — copier .example
├── inventory.ps1      # inventaire read-only
├── inventory/         # sorties JSON (gitignoré)
└── (à venir après inventaire)
    ├── vpc.tf           network.tf      # VPC, subnets, RT, IGW
    ├── security.tf      # security groups (sg-ec2, sg-rds)
    ├── ec2.tf           # instance market-CM-API + EIP + key pair
    ├── rds.tf           # instance PostgreSQL + subnet group
    ├── s3.tf            # bucket médias + policy + versioning
    └── iam.tf           # user/role + policies least-privilege
```

---

## 3. Adoption de l'existant (import)

Pour chaque ressource (exemple EC2) :
```powershell
# 1. on écrit le bloc resource "aws_instance" "api" {...} dans ec2.tf
# 2. on l'importe (remplace i-0xxx par l'ID réel issu de l'inventaire)
terraform import 'aws_instance.api' i-0123456789abcdef0
# 3. terraform plan → doit montrer "No changes" (ou des diffs mineurs à aligner)
```
On répète VPC → subnets → SG → RDS → S3 → IAM → EC2 → EIP.

Cible : `terraform plan` **sans changement** = le code reflète exactement la prod.

---

## 4. État distant (recommandé ensuite)

Une fois l'import stabilisé, migrer l'état local vers un backend **S3 + DynamoDB**
(verrouillage) — voir le bloc commenté dans `versions.tf`. Cela évite la perte
d'état et permet le travail à plusieurs / la CI.

---

## Règles de sécurité

- `terraform.tfvars`, `*.tfstate`, `inventory/`, `.terraform/` sont **gitignorés**
  (l'état peut contenir des secrets : mots de passe RDS, etc.).
- Jamais de clés d'accès en clair dans les `.tf`. On passe par le profil AWS CLI.
