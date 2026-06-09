# Rapport de Validation AWS — Marché CM
**Rôles :** Principal Cloud Architect AWS · Principal DevOps Engineer · Site Reliability Engineer (SRE)  
**Date :** 2026-06-06  
**Statut :** VALIDE AVEC RECOMMANDATIONS  

---

## 1. Résumé de l'Audit Zero Trust
Ce rapport présente la validation technique de l'infrastructure cloud hébergeant la plateforme **Marché CM**. Toutes les informations présentées ci-dessous découlent de requêtes directes exécutées sur l'API AWS avec les accès administrateur fournis.

| Composant | Statut | Constations Techniques |
| :--- | :---: | :--- |
| **1. Compute (EC2)** | 🟢 Conforme | 1 instance `t3.large` active (`market-CM-API`). Instance doublon résiliée. |
| **2. Base de Données (RDS)** | 🟢 Conforme | PostgreSQL 18.3, `db.t3.medium`, Haute Disponibilité (Multi-AZ) activée. |
| **3. Stockage (S3)** | 🟡 Réserves | Versioning activé sur `market-cm`. Absence de politique de cycle de vie (coût). |
| **4. Sécurité Réseau (SGs)** | 🟢 Conforme | Port SSH 22 totalement fermé à l'univers. Accès via SSM Session Manager. |
| **5. Cloisonnement IAM** | 🟢 Conforme | Rôle applicatif `accessRoles3` limité au bucket S3 et au chemin SSM prod. |
| **6. Secrets (SSM)** | 🟢 Conforme | Secrets stockés sous `/marche-cm/prod/*` et chiffrés par KMS. |
| **7. DNS & SSL (Route53/ACM)**| ℹ️ N/A | Non utilisés. TLS géré localement sur l'hôte EC2 via Let's Encrypt. |

---

## 2. Validation Détaillée par Ressource

### 2.1 Compute (EC2)
* **Instance Unique** : Une seule instance running est détectée pour le projet :
  * **ID Instance** : `i-09e104c1cd49c757e`
  * **Type d'Instance** : `t3.large` (2 vCPUs, 8 Go RAM)
  * **Statut** : `running`
  * **Tags** :
    * `Name` : `market-CM-API`
    * `Env` : `prod`
    * `Project` : `marche-cm`
    * `ManagedBy` : `terraform`
* **Nettoyage Doublons** : L'instance doublon précédemment signalée a été résiliée et supprimée de l'inventaire AWS actif, évitant ainsi des coûts superflus.

### 2.2 Base de Données (RDS)
L'instance de base de données PostgreSQL de production a été inspectée en profondeur :
* **Identifiant** : `marchecm-postgres`
* **Moteur & Version** : `PostgreSQL 18.3`
* **Classe d'Instance** : `db.t3.medium` (2 vCPUs, 4 Go RAM)
* **Haute Disponibilité (Multi-AZ)** : 🟢 **Activée** (`MultiAZ = true`).
  * *Zone de Disponibilité Primaire* : `eu-north-1a`
  * *Zone de Disponibilité Secondaire* : `eu-north-1b`
  * *Bénéfice* : Réplication synchrone au niveau bloc. En cas de défaillance de la zone principale, le basculement DNS automatique s'effectue en moins de 60 secondes sans perte de données.
* **Chiffrement au Repos** : 🟢 **Activé** (`StorageEncrypted = true`).
  * *Clé KMS* : `arn:aws:kms:eu-north-1:958924735829:key/9debcc87-a38b-4aae-9d5f-ad3fb7f836eb`
* **Protection contre la Suppression** : 🟢 **Activée** (`DeletionProtection = true`).
* **Sauvegardes & Rétention** :
  * *Rétention des sauvegardes* : `7 jours` (`BackupRetentionPeriod = 7`).
  * *Fenêtre de sauvegarde préférée* : `05:24-05:54` UTC.
  * *Point-in-Time Recovery (PITR)* : **Actif** (dernière heure restaurable continuellement à jour).

### 2.3 Stockage (S3)
* **Bucket Actif** : `market-cm` (situé en région `eu-north-1`).
* **Versioning** : 🟢 **Activé** (`Status = Enabled`). Cette configuration garantit la conservation de l'historique de chaque document KYC et média chargé, protégeant contre la suppression accidentelle.
* **Politique de Cycle de Vie (Lifecycle)** : 🔴 **Inexistante** (`NoSuchLifecycleConfiguration`). Les versions obsolètes s'accumulent sans suppression automatique ni transition vers des classes de stockage moins coûteuses (ex. Glacier).

### 2.4 Sécurité Réseau (Security Groups)
* **Security Group Applicatif** : `sg-03833d09622cb36b0` ("launch-wizard-1") protégeant l'instance EC2.
* **Règles d'Entrée (Ingress)** :
  * **Port 80 (HTTP)** : Ouvert à `0.0.0.0/0`.
  * **Port 443 (HTTPS)** : Ouvert à `0.0.0.0/0`.
  * **Port 22 (SSH)** : 🟢 **Totalement Fermé**. Aucun accès SSH direct n'est autorisé depuis l'extérieur.
* **Bascule SSM Session Manager** : La connexion shell sécurisée à l'instance s'effectue via **AWS Systems Manager (SSM)** grâce à la présence de l'agent SSM sur l'instance et de la politique `AmazonSSMManagedInstanceCore` dans le rôle IAM de l'EC2. Les sessions et commandes administratives sont ainsi 100% auditées dans CloudTrail.

### 2.5 Observabilité (CloudWatch Logs)
* **Groupe de Logs** : `/aws/container/marche-cm`
* **Flux de Logs (Streams)** :
  * `web` : Flux actif recueillant les logs Django/Daphne.
  * `nginx` : Flux actif recueillant les logs du serveur proxy Nginx.
  * `finops-retries` : Flux actif recueillant les logs des commandes asynchrones de réconciliation financière.
* **Configuration** : Les conteneurs poussent leurs sorties standards directement dans CloudWatch Logs grâce au driver Docker `awslogs`.

### 2.6 Rôles IAM & Gestion des Privilèges
* **Rôle Instance** : `accessRoles3` attaché à l'EC2.
* **Politique Inline** : `marche-cm-app-access` restrictives :
  * *SSM Parameter Store* : Limité à `arn:aws:ssm:eu-north-1:958924735829:parameter/marche-cm/prod` et sous-chemins (`/prod/*`).
  * *Décryptage KMS* : Limité à la clé SSM.
  * *S3* : Autorise GetObject, PutObject, DeleteObject uniquement sur `arn:aws:s3:::market-cm/*` et ListBucket sur `arn:aws:s3:::market-cm`.
  * *CloudWatch Logs* : Autorise la création et l'envoi de flux.

### 2.7 SSM Parameter Store
* **Chemin Principal** : `/marche-cm/prod`
* **Secrets Présents** :
  * `/marche-cm/prod/SECRET_KEY` (SecureString)
  * `/marche-cm/prod/DATABASE_URL` / `DB_HOST` / `DB_USER` / `DB_NAME` (String)
  * `/marche-cm/prod/DB_SSLMODE` = `require` (String)
  * `/marche-cm/prod/REDIS_PASSWORD` (SecureString)
  * `/marche-cm/prod/JWT_ALGORITHM` = `RS256` (String)
  * `/marche-cm/prod/NOTCHPAY_LIVE_PRIVATE_KEY` / `NOTCHPAY_LIVE_PUBLIC_KEY` (SecureString)
  * `/marche-cm/prod/AWS_STORAGE_BUCKET_NAME` = `market-cm` (String)

---

## 3. Recommandations P1/P2

> [!WARNING]
> **R-AWS-001 : Configuration d'une politique de cycle de vie S3 (Priorité 2 / FinOps)**  
> Afin d'éviter l'explosion des coûts S3 liée à la conservation indéfinie des anciennes versions de documents volumineux, configurer une règle déplaçant les versions non-courantes vers Glacier Flexible Retrieval après 90 jours et les supprimant définitivement après 180 jours.

> [!NOTE]
> **R-AWS-002 : Migration vers HTTPS ALB / ACM (Priorité 3)**  
> Actuellement, TLS est géré directement sur l'instance unique via Let's Encrypt. Pour supporter l'autoscaling horizontal (plusieurs EC2 applicatifs), il faudra déployer un Application Load Balancer (ALB) gérant le certificat SSL via ACM, libérant ainsi l'instance EC2 de la charge du déchiffrement TLS.
