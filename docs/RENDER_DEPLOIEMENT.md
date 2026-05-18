# Déploiement Marche CM sur Render — Guide complet
> Niveau : débutant. Aucune connaissance serveur requise.
> Temps estimé : 45 minutes à 1 heure.

---

## Sommaire

1. [Ce dont tu as besoin](#1-ce-dont-tu-as-besoin)
2. [Préparer le code sur GitHub](#2-préparer-le-code-sur-github)
3. [Créer un compte Render](#3-créer-un-compte-render)
4. [Créer la base de données PostgreSQL](#4-créer-la-base-de-données-postgresql)
5. [Créer Redis](#5-créer-redis)
6. [Créer le Web Service (backend)](#6-créer-le-web-service-backend)
7. [Configurer toutes les variables d'environnement](#7-configurer-toutes-les-variables-denvironnement)
8. [Lancer les migrations](#8-lancer-les-migrations)
9. [Configurer le domaine personnalisé](#9-configurer-le-domaine-personnalisé)
10. [Activer les paiements NotchPay](#10-activer-les-paiements-notchpay)
11. [Configurer le stockage fichiers (KYC/médias)](#11-configurer-le-stockage-fichiers-kycmédias)
12. [Connecter les apps Flutter au backend](#12-connecter-les-apps-flutter-au-backend)
13. [Mettre à jour l'application](#13-mettre-à-jour-lapplication)
14. [Surveillance et logs](#14-surveillance-et-logs)
15. [Sauvegardes](#15-sauvegardes)
16. [Checklist finale avant lancement](#16-checklist-finale-avant-lancement)
17. [Prix et plan recommandé](#17-prix-et-plan-recommandé)
18. [En cas de problème](#18-en-cas-de-problème)

---

## 1. Ce dont tu as besoin

### Obligatoire

| Élément | Où l'obtenir | Coût |
|---|---|---|
| Compte **GitHub** | github.com | Gratuit |
| Compte **Render** | render.com | Gratuit (plan payant pour prod) |
| **Nom de domaine** | Namecheap / OVH / Gandi | ~12€/an |
| Clés **NotchPay Live** | notchpay.co (après validation KYC) | Gratuit |

### Optionnel mais recommandé en production

| Élément | Pourquoi | Coût |
|---|---|---|
| **Cloudflare R2** | Stockage sécurisé des documents KYC et médias | ~0–5€/mois |
| **Mailjet / SendGrid** | Envoi d'emails (vérification, reset mdp) | Gratuit jusqu'à 200 emails/jour |

---

## 2. Préparer le code sur GitHub

### 2.1 — Créer le repo GitHub (si pas encore fait)

1. Aller sur **github.com** → cliquer **New repository**
2. Nommer le repo `marche-cm` (ou autre)
3. Choisir **Private** (recommandé — le code contient des configs)
4. Cliquer **Create repository**

### 2.2 — Pousser le code

Ouvrir PowerShell dans le dossier du projet :

```powershell
cd "e:\project\Marche CM"

# Initialiser git si pas encore fait
git init
git branch -M main

# Connecter au repo GitHub (remplacer TON_GITHUB par ton nom d'utilisateur)
git remote add origin https://github.com/TON_GITHUB/marche-cm.git

# Pousser le code
git add .
git commit -m "initial production deploy"
git push -u origin main
```

### 2.3 — Vérifier que le .env n'est pas commité

Le fichier `.env` contient des secrets. Il doit être dans `.gitignore`.

Vérifier que `backend/.gitignore` (ou le `.gitignore` racine) contient :
```
.env
*.pyc
__pycache__/
db.sqlite3
```

---

## 3. Créer un compte Render

1. Aller sur **render.com**
2. Cliquer **Get Started for Free**
3. Cliquer **Continue with GitHub** → autoriser Render à accéder à tes repos
4. Vérifier ton email si demandé

> Render est maintenant connecté à GitHub. Chaque `git push` déclenchera un redéploiement automatique.

---

## 4. Créer la base de données PostgreSQL

SQLite ne fonctionne pas en production multi-utilisateurs. Render fournit PostgreSQL géré.

### Étapes

1. Dans le dashboard Render → cliquer **New +** (bouton violet en haut à droite)
2. Sélectionner **PostgreSQL**
3. Remplir le formulaire :

| Champ | Valeur |
|---|---|
| **Name** | `marche-cm-db` |
| **Database** | `marche_cm` |
| **User** | `marche_user` |
| **Region** | `Frankfurt (EU Central)` |
| **PostgreSQL Version** | `16` |
| **Plan** | `Free` (pour tester) ou `Starter $7/mois` (production) |

4. Cliquer **Create Database**
5. Attendre 1–2 minutes que la base soit créée

### Récupérer l'URL de connexion

Une fois créée, aller dans la base de données → section **Connections** :

- Copier la valeur **Internal Database URL** (commence par `postgresql://`)
- **Garder cette URL précieusement** — tu en auras besoin à l'étape 7

> **Important** : utiliser `Internal Database URL` (pas External) pour que la
> connexion soit sécurisée et gratuite (même réseau interne Render).

---

## 5. Créer Redis

Redis permet les WebSockets multi-utilisateurs et le cache partagé.

### Étapes

1. **New +** → **Redis**
2. Remplir :

| Champ | Valeur |
|---|---|
| **Name** | `marche-cm-redis` |
| **Region** | `Frankfurt (EU Central)` ← même région que la DB |
| **Plan** | `Free` (25 Mo) pour tester, `Starter $10/mois` pour production |
| **Max Memory Policy** | `allkeys-lru` |

3. Cliquer **Create Redis**

### Récupérer l'URL Redis

Dans le service Redis créé → section **Connect** :

- Copier la valeur **Internal Redis URL** (commence par `redis://`)
- **Garder cette URL**

---

## 6. Créer le Web Service (backend)

C'est le cœur du déploiement : Render va builder le Dockerfile et lancer Django.

### Étapes

1. **New +** → **Web Service**
2. Sélectionner **Build and deploy from a Git repository**
3. Cliquer **Connect** à côté de ton repo `marche-cm`
4. Remplir le formulaire :

| Champ | Valeur |
|---|---|
| **Name** | `marche-cm-backend` |
| **Region** | `Frankfurt (EU Central)` ← même région |
| **Branch** | `main` |
| **Root Directory** | `backend` ← **CRITIQUE : sinon Render ne trouve pas le Dockerfile** |
| **Runtime** | `Docker` ← Render détecte le Dockerfile automatiquement |
| **Plan** | `Free` (s'éteint si inactif 15 min) ou `Starter $7/mois` |

> **Ne pas cliquer "Create Web Service" tout de suite** — configurer d'abord
> les variables d'environnement (étape suivante).

---

## 7. Configurer toutes les variables d'environnement

Toujours dans le formulaire de création du Web Service, scroller vers le bas jusqu'à la section **Environment Variables**.

### 7.1 — Générer les secrets

**Sur ton PC**, ouvrir PowerShell et taper ces commandes une par une :

```powershell
# Activer l'environnement Python
cd "e:\project\Marche CM\backend"
python -m venv venv_temp
.\venv_temp\Scripts\Activate.ps1
pip install django --quiet

# SECRET_KEY (clé principale Django)
python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"

# DATA_ENCRYPTION_KEY (chiffrement des données PII)
python -c "import base64, os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())"

# DEVICE_FINGERPRINT_SECRET
python -c "import secrets; print(secrets.token_hex(32))"

# NOTCHPAY_CHECKOUT_WEBHOOK_SECRET
python -c "import secrets; print(secrets.token_hex(32))"

# NOTCHPAY_DISBURSE_WEBHOOK_SECRET
python -c "import secrets; print(secrets.token_hex(32))"
```

Copier chaque valeur dans un fichier texte temporaire (Notepad).

### 7.2 — Ajouter les variables dans Render

Dans la section **Environment Variables** du Web Service, ajouter chaque ligne :

#### Obligatoires — Sécurité

| Clé | Valeur |
|---|---|
| `SECRET_KEY` | *(valeur générée ci-dessus)* |
| `DATA_ENCRYPTION_KEY` | *(valeur générée ci-dessus)* |
| `DEVICE_FINGERPRINT_SECRET` | *(valeur générée ci-dessus)* |
| `DEBUG` | `False` |

#### Obligatoires — Base de données et Redis

| Clé | Valeur |
|---|---|
| `DATABASE_URL` | *(Internal Database URL copiée à l'étape 4)* |
| `REDIS_URL` | *(Internal Redis URL copiée à l'étape 5)* |

#### Obligatoires — URLs et HTTPS

| Clé | Valeur |
|---|---|
| `BACKEND_PUBLIC_URL` | `https://marche-cm-backend.onrender.com` |
| `CSRF_TRUSTED_ORIGINS` | `https://marche-cm-backend.onrender.com` |
| `CORS_ALLOWED_ORIGINS` | `https://marche-cm-backend.onrender.com` |
| `USE_X_FORWARDED_PROTO` | `True` |
| `SECURE_SSL_REDIRECT` | `False` ← Render gère le SSL lui-même |
| `SESSION_COOKIE_SECURE` | `True` |
| `CSRF_COOKIE_SECURE` | `True` |
| `SECURE_HSTS_SECONDS` | `31536000` |
| `SECURE_HSTS_INCLUDE_SUBDOMAINS` | `True` |

#### Paiements NotchPay (mode test pour commencer)

| Clé | Valeur |
|---|---|
| `NOTCHPAY_ENABLED` | `False` ← activer après configuration complète |
| `NOTCHPAY_MODE` | `test` ← passer à `live` après validation |
| `NOTCHPAY_AUTO_PAYOUT` | `False` ← ne jamais activer sans tests |
| `NOTCHPAY_WEBHOOK_TOKEN` | *(générer un token aléatoire)* |
| `NOTCHPAY_CHECKOUT_WEBHOOK_SECRET` | *(valeur générée ci-dessus)* |
| `NOTCHPAY_DISBURSE_WEBHOOK_SECRET` | *(valeur générée ci-dessus)* |

#### Sécurité additionnelle

| Clé | Valeur |
|---|---|
| `SECURITY_HARD_BLOCK_SCANNERS` | `True` |
| `SENSITIVE_ACTION_2FA_ENABLED` | `True` |
| `RECONCILIATION_REQUIRE_PROVIDER_BALANCE` | `True` |

### 7.3 — Créer le service

Après avoir ajouté toutes les variables → cliquer **Create Web Service**.

Render va :
1. Cloner ton repo GitHub
2. Builder l'image Docker (5–10 minutes)
3. Lancer Daphne (le serveur ASGI)

Tu peux suivre le build en temps réel dans l'onglet **Logs**.

### 7.4 — Trouver l'URL Render de ton service

Une fois déployé, Render affiche en haut de la page :
```
https://marche-cm-backend.onrender.com
```

Retourner dans **Environment** et mettre à jour :
- `BACKEND_PUBLIC_URL` avec cette URL exacte
- `CSRF_TRUSTED_ORIGINS` avec cette URL exacte

Puis cliquer **Save Changes** → Render redéploie automatiquement.

---

## 8. Lancer les migrations

Les migrations créent les tables dans la base de données. À faire **une seule fois** après le premier déploiement.

### Depuis la console Render

1. Dans le service `marche-cm-backend` → onglet **Shell**
2. Taper les commandes :

```bash
# Appliquer toutes les migrations
python manage.py migrate

# Créer le premier administrateur
python manage.py createsuperuser
# → entrer un email, un username, un mot de passe fort
```

### Vérifier que ça a fonctionné

Ouvrir dans un navigateur :
```
https://marche-cm-backend.onrender.com/admin/
```

Se connecter avec les identifiants créés → tu dois voir l'interface d'administration Django.

---

## 9. Configurer le domaine personnalisé

Render donne une URL `.onrender.com` gratuite. Pour utiliser `api.ton-domaine.com` :

### Sur Render

1. Dans le service → onglet **Settings**
2. Section **Custom Domains** → **Add Custom Domain**
3. Taper `api.ton-domaine.com`
4. Render affiche un **CNAME record** à configurer chez ton registrar

### Chez ton registrar DNS (Namecheap, OVH, Gandi...)

Ajouter cet enregistrement DNS :

| Type | Nom (Host) | Valeur (Target) |
|---|---|---|
| `CNAME` | `api` | *(la valeur CNAME donnée par Render)* |

> La propagation DNS prend **5 à 30 minutes**.

### Mettre à jour les variables d'environnement

Une fois le domaine actif, modifier dans Render → **Environment** :

| Clé | Nouvelle valeur |
|---|---|
| `BACKEND_PUBLIC_URL` | `https://api.ton-domaine.com` |
| `CSRF_TRUSTED_ORIGINS` | `https://api.ton-domaine.com` |
| `CORS_ALLOWED_ORIGINS` | `https://api.ton-domaine.com` |
| `NOTCHPAY_CHECKOUT_CALLBACK_URL` | `https://api.ton-domaine.com` |
| `NOTCHPAY_DISBURSE_CALLBACK_URL` | `https://api.ton-domaine.com/api/wallets/notchpay/disburse/webhook/` |

Render gère le certificat SSL automatiquement — HTTPS est actif sans configuration.

---

## 10. Activer les paiements NotchPay

### Obtenir les clés live NotchPay

1. Aller sur **notchpay.co**
2. Créer un compte business et compléter le KYC
3. Dans le dashboard NotchPay → **API Keys** → copier les clés **Live**

### Configurer les webhooks sur NotchPay

Les webhooks permettent à NotchPay de notifier ton backend quand un paiement est confirmé.

Dans le dashboard NotchPay → **Webhooks** → **Add Webhook** :

| Type | URL |
|---|---|
| Checkout (recharge) | `https://api.ton-domaine.com/api/wallets/notchpay/checkout/webhook/` |
| Disburse (retrait) | `https://api.ton-domaine.com/api/wallets/notchpay/disburse/webhook/` |

Le **secret** à entrer dans NotchPay est la valeur de `NOTCHPAY_CHECKOUT_WEBHOOK_SECRET` (ou `NOTCHPAY_DISBURSE_WEBHOOK_SECRET`) que tu as générée.

### Activer dans Render

Dans **Environment**, modifier :

| Clé | Valeur |
|---|---|
| `NOTCHPAY_ENABLED` | `True` |
| `NOTCHPAY_MODE` | `live` |
| `NOTCHPAY_LIVE_PUBLIC_KEY` | *(ta clé publique live NotchPay)* |
| `NOTCHPAY_LIVE_PRIVATE_KEY` | *(ta clé privée live NotchPay)* |
| `NOTCHPAY_CURRENCY` | `XAF` |
| `NOTCHPAY_DEFAULT_COUNTRY_CODE` | `237` |
| `NOTCHPAY_CHECKOUT_CHANNELS` | `cm.mtn,cm.orange` |

---

## 11. Configurer le stockage fichiers (KYC/médias)

Par défaut, les fichiers (photos profil, documents KYC, vidéos produits) sont stockés **localement sur le serveur Render**. Problème : Render efface ces fichiers à chaque redéploiement.

**Solution : utiliser Cloudflare R2** (compatible S3, 10 Go gratuits/mois).

### Créer un bucket Cloudflare R2

1. Aller sur **dash.cloudflare.com** → **R2 Object Storage**
2. Cliquer **Create bucket** → nommer `marche-cm-media`
3. Aller dans **Manage R2 API Tokens** → **Create API Token** avec droits `Object Read & Write`
4. Noter :
   - `Access Key ID`
   - `Secret Access Key`
   - `Endpoint URL` (format : `https://ACCOUNT_ID.r2.cloudflarestorage.com`)

### Configurer dans Render

| Clé | Valeur |
|---|---|
| `USE_S3_STORAGE` | `True` |
| `AWS_STORAGE_BUCKET_NAME` | `marche-cm-media` |
| `AWS_S3_ENDPOINT_URL` | `https://ACCOUNT_ID.r2.cloudflarestorage.com` |
| `AWS_ACCESS_KEY_ID` | *(ton Access Key ID R2)* |
| `AWS_SECRET_ACCESS_KEY` | *(ton Secret Access Key R2)* |
| `AWS_S3_ADDRESSING_STYLE` | `path` |
| `REQUIRE_REMOTE_PROOF_STORAGE` | `True` |

---

## 12. Connecter les apps Flutter au backend

Dans les deux apps Flutter (`frontend/app` et `frontend/Clients`), modifier la configuration :

### `frontend/app/lib/core/app_config.dart`

```dart
static const String apiBaseUrl = "https://api.ton-domaine.com";
```

### `frontend/Clients/lib/core/app_config.dart`

```dart
static const String apiBaseUrl = "https://api.ton-domaine.com";
```

Puis rebuilder les apps.

---

## 13. Mettre à jour l'application

Chaque modification du code se déploie automatiquement :

```powershell
cd "e:\project\Marche CM"

# Modifier le code...

git add .
git commit -m "description de la modification"
git push origin main
```

Render détecte le push, rebuild l'image Docker et redéploie en quelques minutes.

### Si une migration est nécessaire après la mise à jour

Dans Render → Shell :
```bash
python manage.py migrate
```

---

## 14. Surveillance et logs

### Voir les logs en temps réel

Dans le service Render → onglet **Logs**.

Les logs sont formatés en JSON structuré :
```json
{"time":"2026-05-14T10:00:00","level":"INFO","logger":"django","msg":"GET /api/health/ 200"}
```

### Indicateurs à surveiller

| Indicateur | Comment le voir |
|---|---|
| **Service actif** | Badge vert "Live" dans le dashboard |
| **Utilisation mémoire** | Onglet **Metrics** |
| **Erreurs 500** | Onglet **Logs** → filtrer "ERROR" |
| **Base de données** | Dans le service PostgreSQL → onglet **Metrics** |

### Health check automatique

L'URL `/api/health/` est configurée dans le Dockerfile comme health check. Render l'appelle toutes les 30 secondes. Si elle échoue 3 fois de suite, Render redémarre le service automatiquement.

---

## 15. Sauvegardes

### Sauvegardes automatiques PostgreSQL

Render sauvegarde automatiquement la base de données :
- **Plan Free** : pas de sauvegardes automatiques
- **Plan Starter ($7/mois)** : sauvegardes journalières, rétention 7 jours
- **Plan Standard ($20/mois)** : sauvegardes journalières, rétention 30 jours

### Sauvegarde manuelle (depuis la console Render)

Dans le service PostgreSQL → onglet **Backups** → **Create Backup**.

Ou via la console Shell du Web Service :

```bash
# Exporter la base (remplacer DATABASE_URL par la vraie valeur)
pg_dump $DATABASE_URL > backup_$(date +%Y%m%d).sql
```

### Restaurer une sauvegarde

Dans PostgreSQL → onglet **Backups** → cliquer sur une sauvegarde → **Restore**.

---

## 16. Checklist finale avant lancement

### Infrastructure Render

- [ ] Service PostgreSQL créé et actif (plan Starter recommandé)
- [ ] Service Redis créé et actif
- [ ] Web Service créé, build réussi, badge "Live"
- [ ] L'URL Render répond : `https://marche-cm-backend.onrender.com/api/health/`
- [ ] L'admin Django est accessible et fonctionnel

### Sécurité

- [ ] `DEBUG=False`
- [ ] `SECRET_KEY` généré aléatoirement (pas la valeur exemple)
- [ ] `DATA_ENCRYPTION_KEY` généré aléatoirement
- [ ] `DEVICE_FINGERPRINT_SECRET` généré aléatoirement
- [ ] Les clés NotchPay de `.env.example` ne sont PAS dans les variables Render (utiliser les vraies clés live)
- [ ] `NOTCHPAY_AUTO_PAYOUT=False`
- [ ] `SECURE_SSL_REDIRECT=False` (Render gère le SSL)
- [ ] `USE_X_FORWARDED_PROTO=True`

### Domaine

- [ ] DNS configuré (`api.TON_DOMAINE.com` → CNAME Render)
- [ ] HTTPS actif (cadenas dans le navigateur)
- [ ] `BACKEND_PUBLIC_URL` mis à jour avec le vrai domaine
- [ ] `CSRF_TRUSTED_ORIGINS` mis à jour
- [ ] `CORS_ALLOWED_ORIGINS` mis à jour

### Base de données

- [ ] `python manage.py migrate` exécuté
- [ ] Superadmin créé
- [ ] Sauvegardes automatiques actives (plan Starter+)

### Paiements

- [ ] `NOTCHPAY_ENABLED=True`
- [ ] `NOTCHPAY_MODE=live`
- [ ] Clés live NotchPay configurées
- [ ] Webhooks configurés sur le dashboard NotchPay
- [ ] Test de paiement effectué en mode test avant de passer live

### Médias

- [ ] Cloudflare R2 configuré (`USE_S3_STORAGE=True`)
- [ ] Upload d'une image de test réussi

### Apps Flutter

- [ ] `apiBaseUrl` pointe vers `https://api.ton-domaine.com` dans les deux apps
- [ ] Login fonctionne depuis l'app
- [ ] WebSockets (notifications temps réel) fonctionnent

---

## 17. Prix et plan recommandé

### Configuration minimale pour lancement

| Service Render | Plan | Prix/mois |
|---|---|---|
| Web Service (backend) | **Starter** | $7 |
| PostgreSQL | **Starter** | $7 |
| Redis | **Starter** | $10 |
| **Total** | | **$24/mois** |

> Le plan **Free** existe mais le Web Service s'éteint après 15 minutes sans trafic
> (la première requête prend 30–60 secondes pour "réveiller" le service).
> Pour une application en production, le plan Starter est obligatoire.

### Si tu as beaucoup d'utilisateurs (100+)

| Service Render | Plan | Prix/mois |
|---|---|---|
| Web Service | Standard (2 instances) | $25 |
| PostgreSQL | Standard | $20 |
| Redis | Standard | $25 |
| **Total** | | **$70/mois** |

---

## 18. En cas de problème

### Le build échoue

→ Regarder les logs de build dans Render → onglet **Logs** (filtrer "Build").

Causes fréquentes :
- **Root Directory incorrect** : doit être `backend`
- **requirements.txt manquant** : vérifier que `backend/requirements.txt` est dans le repo
- **Erreur psycopg2** : normal avec certaines versions, le Dockerfile compile libpq

### `ImproperlyConfigured` au démarrage

→ Une variable d'environnement obligatoire manque.
Lire le message d'erreur dans les logs — il indique exactement quelle variable est manquante.

### Erreur 502 Bad Gateway

→ Le service Django a crashé.
Regarder les logs → chercher `ERROR` ou `Exception`.

### Les migrations échouent

→ Vérifier que `DATABASE_URL` est correct (copier depuis Render → PostgreSQL → Internal URL).

### Les WebSockets ne fonctionnent pas

→ Vérifier que `REDIS_URL` est défini et que le service Redis est actif.

### Les fichiers uploadés disparaissent après un redéploiement

→ Configurer Cloudflare R2 (étape 11). Render a un système de fichiers éphémère.

### Le plan Free s'endort

→ C'est normal. Passer au plan Starter ($7/mois) pour éviter cela.

---

## Référence rapide — Variables d'environnement complètes

```dotenv
# Sécurité (à générer)
SECRET_KEY=
DATA_ENCRYPTION_KEY=
DEVICE_FINGERPRINT_SECRET=
SECURITY_HARD_BLOCK_SCANNERS=True

# App
DEBUG=False
BACKEND_PUBLIC_URL=https://api.ton-domaine.com

# Base de données et cache
DATABASE_URL=postgresql://...  # depuis Render PostgreSQL
REDIS_URL=redis://...          # depuis Render Redis

# HTTPS
USE_X_FORWARDED_PROTO=True
SECURE_SSL_REDIRECT=False
SESSION_COOKIE_SECURE=True
CSRF_COOKIE_SECURE=True
SECURE_HSTS_SECONDS=31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS=True
CSRF_TRUSTED_ORIGINS=https://api.ton-domaine.com
CORS_ALLOWED_ORIGINS=https://api.ton-domaine.com

# Paiements NotchPay
NOTCHPAY_ENABLED=True
NOTCHPAY_MODE=live
NOTCHPAY_LIVE_PUBLIC_KEY=pk.xxx
NOTCHPAY_LIVE_PRIVATE_KEY=sk.xxx
NOTCHPAY_CURRENCY=XAF
NOTCHPAY_DEFAULT_COUNTRY_CODE=237
NOTCHPAY_CHECKOUT_CHANNELS=cm.mtn,cm.orange
NOTCHPAY_CHECKOUT_CALLBACK_URL=https://api.ton-domaine.com
NOTCHPAY_CHECKOUT_WEBHOOK_SECRET=  # à générer
NOTCHPAY_DISBURSE_WEBHOOK_SECRET=  # à générer
NOTCHPAY_DISBURSE_CALLBACK_URL=https://api.ton-domaine.com/api/wallets/notchpay/disburse/webhook/
NOTCHPAY_AUTO_PAYOUT=False
NOTCHPAY_WEBHOOK_TOKEN=  # à générer

# Stockage fichiers (Cloudflare R2)
USE_S3_STORAGE=True
AWS_STORAGE_BUCKET_NAME=marche-cm-media
AWS_S3_ENDPOINT_URL=https://ACCOUNT_ID.r2.cloudflarestorage.com
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
AWS_S3_ADDRESSING_STYLE=path
REQUIRE_REMOTE_PROOF_STORAGE=True

# JWT
JWT_ACCESS_TOKEN_MINUTES=15
JWT_REFRESH_TOKEN_DAYS=7

# MFA
SENSITIVE_ACTION_2FA_ENABLED=True
RECONCILIATION_REQUIRE_PROVIDER_BALANCE=True
```
