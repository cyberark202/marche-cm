# Guide de mise en ligne — Marche CM (A → Z)
> Niveau requis : aucun. Chaque commande est expliquée.

---

## Sommaire

1. [Ce dont tu as besoin](#1-ce-dont-tu-as-besoin)
2. [Acheter un serveur (VPS)](#2-acheter-un-serveur-vps)
3. [Se connecter au serveur](#3-se-connecter-au-serveur)
4. [Sécuriser le serveur](#4-sécuriser-le-serveur)
5. [Installer les logiciels système](#5-installer-les-logiciels-système)
6. [Installer PostgreSQL (base de données)](#6-installer-postgresql-base-de-données)
7. [Installer Redis (cache + WebSockets)](#7-installer-redis-cache--websockets)
8. [Déployer le backend Django](#8-déployer-le-backend-django)
9. [Configurer les variables d'environnement](#9-configurer-les-variables-denvironnement)
10. [Lancer le backend comme service permanent](#10-lancer-le-backend-comme-service-permanent)
11. [Installer et configurer Nginx](#11-installer-et-configurer-nginx)
12. [Obtenir un certificat SSL gratuit (HTTPS)](#12-obtenir-un-certificat-ssl-gratuit-https)
13. [Configurer ton nom de domaine](#13-configurer-ton-nom-de-domaine)
14. [Vérifier que tout fonctionne](#14-vérifier-que-tout-fonctionne)
15. [Mettre à jour l'application](#15-mettre-à-jour-lapplication)
16. [Sauvegardes](#16-sauvegardes)
17. [Checklist finale](#17-checklist-finale)

---

## 1. Ce dont tu as besoin

### À acheter / avoir avant de commencer

| Élément | Où acheter | Prix estimé | Obligatoire |
|---|---|---|---|
| **Serveur VPS** | Hetzner, Contabo, DigitalOcean | 5–15 €/mois | ✅ |
| **Nom de domaine** | Namecheap, OVH, Gandi | 10–15 €/an | ✅ |
| **Compte GitHub** | github.com | Gratuit | ✅ |
| Clés NotchPay Live | notchpay.co | Gratuit (compte) | Pour paiements réels |
| Bucket S3/R2 (fichiers) | Cloudflare R2, AWS S3 | ~0–5 €/mois | Pour KYC/documents |

### Recommandation serveur
> **Hetzner CX22** (Allemagne/Finlande) : 2 vCPU, 4 GB RAM, 40 GB SSD → **~4 €/mois**
> URL : https://www.hetzner.com/cloud
> Choisir **Ubuntu 22.04 LTS** comme système d'exploitation.

---

## 2. Acheter un serveur (VPS)

### Sur Hetzner (recommandé)

1. Créer un compte sur **hetzner.com**
2. Aller dans **Cloud → Projects → New Project** → nommer "Marche CM"
3. Cliquer **Add Server**
4. Choisir :
   - **Location** : Nuremberg (EU) ou Ashburn (USA)
   - **Image** : Ubuntu 22.04
   - **Type** : CX22 (4€/mois) ou CX32 (9€/mois) si tu as du trafic
   - **SSH Key** : créer une clé SSH (expliqué ci-dessous)
5. Cliquer **Create & Buy**
6. **Noter l'adresse IP** donnée (ex: `49.13.XXX.XXX`)

### Créer une clé SSH (pour se connecter sans mot de passe)

**Sur Windows**, ouvrir PowerShell :
```powershell
ssh-keygen -t ed25519 -C "marche-cm-server"
# Appuyer Entrée 3 fois (pas de mot de passe)
# La clé publique est dans C:\Users\TON_NOM\.ssh\id_ed25519.pub
```

Copier le contenu de `id_ed25519.pub` et le coller dans Hetzner lors de la création du serveur.

---

## 3. Se connecter au serveur

### Depuis Windows (PowerShell ou Terminal)

```powershell
ssh root@49.13.XXX.XXX
# Remplacer XXX.XXX par l'IP de ton serveur
# Taper "yes" à la première connexion
```

Tu es maintenant dans le serveur. Tout ce qui suit se tape dans ce terminal.

---

## 4. Sécuriser le serveur

### Créer un utilisateur dédié (ne jamais travailler en root)

```bash
adduser marchecm
# Entrer un mot de passe fort, appuyer Entrée pour le reste

# Donner les droits administrateur
usermod -aG sudo marchecm

# Copier ta clé SSH pour ce nouvel utilisateur
rsync --archive --chown=marchecm:marchecm ~/.ssh /home/marchecm
```

### Configurer le pare-feu

```bash
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw enable
# Taper "y" pour confirmer
```

### Se reconnecter avec le bon utilisateur

```bash
exit
ssh marchecm@49.13.XXX.XXX
```

---

## 5. Installer les logiciels système

```bash
# Mettre à jour le système
sudo apt update && sudo apt upgrade -y

# Installer les outils essentiels
sudo apt install -y \
    git \
    python3.12 \
    python3.12-venv \
    python3-pip \
    python3-dev \
    build-essential \
    libpq-dev \
    libjpeg-dev \
    libwebp-dev \
    curl \
    unzip \
    nano
```

### Vérifier Python

```bash
python3 --version
# Doit afficher Python 3.12.x
```

---

## 6. Installer PostgreSQL (base de données)

SQLite ne supporte pas plusieurs utilisateurs simultanés. En production, on utilise PostgreSQL.

```bash
# Installer PostgreSQL
sudo apt install -y postgresql postgresql-contrib

# Démarrer le service
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Créer la base de données et l'utilisateur
sudo -u postgres psql << 'EOF'
CREATE DATABASE marche_cm;
CREATE USER marche_user WITH PASSWORD 'MOT_DE_PASSE_FORT_ICI';
GRANT ALL PRIVILEGES ON DATABASE marche_cm TO marche_user;
ALTER DATABASE marche_cm OWNER TO marche_user;
\q
EOF
```

> **Important** : remplace `MOT_DE_PASSE_FORT_ICI` par un vrai mot de passe et note-le.

### Vérifier la connexion

```bash
psql -U marche_user -d marche_cm -h 127.0.0.1
# Si ça s'ouvre, taper \q pour quitter
```

---

## 7. Installer Redis (cache + WebSockets)

```bash
# Installer Redis
sudo apt install -y redis-server

# Configurer Redis pour démarrer automatiquement
sudo systemctl enable redis-server
sudo systemctl start redis-server

# Vérifier
redis-cli ping
# Doit répondre : PONG
```

### Sécuriser Redis (accès local seulement)

```bash
sudo nano /etc/redis/redis.conf
```

Vérifier que cette ligne existe (pas commentée) :
```
bind 127.0.0.1 ::1
```

```bash
sudo systemctl restart redis-server
```

---

## 8. Déployer le backend Django

### Cloner le projet depuis GitHub

```bash
cd /home/marchecm
git clone https://github.com/TON_GITHUB/Marche-CM.git
cd Marche-CM/backend
```

> Si ton repo est privé, configure d'abord un **SSH Deploy Key** dans GitHub :
> `Settings → Deploy keys → Add deploy key` → coller `cat ~/.ssh/id_ed25519.pub`

### Créer l'environnement Python isolé

```bash
python3 -m venv venv
source venv/bin/activate
# Tu verras (venv) devant le prompt — c'est normal
```

### Installer les dépendances

```bash
pip install --upgrade pip
pip install -r requirements.txt

# Installer Gunicorn pour la production
pip install gunicorn uvicorn
```

---

## 9. Configurer les variables d'environnement

```bash
nano /home/marchecm/Marche-CM/backend/.env
```

Coller et **remplir** ce contenu :

```dotenv
# ── Application ────────────────────────────────────────────────────────────
DEBUG=False
SECRET_KEY=GENERER_CI_DESSOUS

# ── Domaine ────────────────────────────────────────────────────────────────
ALLOWED_HOSTS=api.TON_DOMAINE.com,TON_IP_SERVEUR
BACKEND_PUBLIC_URL=https://api.TON_DOMAINE.com
CSRF_TRUSTED_ORIGINS=https://api.TON_DOMAINE.com
CORS_ALLOWED_ORIGINS=https://app.TON_DOMAINE.com

# ── Base de données ────────────────────────────────────────────────────────
DATABASE_URL=postgresql://marche_user:MOT_DE_PASSE_FORT_ICI@127.0.0.1:5432/marche_cm

# ── Redis ──────────────────────────────────────────────────────────────────
REDIS_URL=redis://127.0.0.1:6379/0

# ── Chiffrement ────────────────────────────────────────────────────────────
DATA_ENCRYPTION_KEY=GENERER_CI_DESSOUS
DEVICE_FINGERPRINT_SECRET=GENERER_CI_DESSOUS

# ── HTTPS ──────────────────────────────────────────────────────────────────
SECURE_SSL_REDIRECT=True
SESSION_COOKIE_SECURE=True
CSRF_COOKIE_SECURE=True
SECURE_HSTS_SECONDS=31536000
SECURE_HSTS_INCLUDE_SUBDOMAINS=True
SECURE_HSTS_PRELOAD=True
USE_X_FORWARDED_PROTO=True

# ── NotchPay (paiements) ───────────────────────────────────────────────────
NOTCHPAY_ENABLED=True
NOTCHPAY_MODE=live
NOTCHPAY_LIVE_PUBLIC_KEY=pk.TA_CLE_LIVE_PUBLIQUE
NOTCHPAY_LIVE_PRIVATE_KEY=sk.TA_CLE_LIVE_PRIVEE
NOTCHPAY_CHECKOUT_WEBHOOK_SECRET=GENERER_CI_DESSOUS
NOTCHPAY_DISBURSE_WEBHOOK_SECRET=GENERER_CI_DESSOUS
NOTCHPAY_CHECKOUT_CALLBACK_URL=https://api.TON_DOMAINE.com
NOTCHPAY_DISBURSE_CALLBACK_URL=https://api.TON_DOMAINE.com/api/wallets/notchpay/disburse/webhook/

# ── Fichiers média (si tu utilises Cloudflare R2) ──────────────────────────
# USE_S3_STORAGE=True
# AWS_STORAGE_BUCKET_NAME=marche-cm-media
# AWS_S3_ENDPOINT_URL=https://XXXX.r2.cloudflarestorage.com
# AWS_ACCESS_KEY_ID=
# AWS_SECRET_ACCESS_KEY=

# ── Sécurité ───────────────────────────────────────────────────────────────
SECURITY_HARD_BLOCK_SCANNERS=True
NOTCHPAY_AUTO_PAYOUT=False
```

### Générer les secrets (dans le venv actif)

```bash
# SECRET_KEY
python3 -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"

# DATA_ENCRYPTION_KEY
python3 -c "import base64, os; print(base64.urlsafe_b64encode(os.urandom(32)).decode())"

# DEVICE_FINGERPRINT_SECRET
python3 -c "import secrets; print(secrets.token_hex(32))"

# Tokens webhook (répéter 2 fois, pour CHECKOUT et DISBURSE)
python3 -c "import secrets; print(secrets.token_hex(32))"
```

Copier chaque valeur générée dans le `.env` à la bonne ligne.

### Appliquer les migrations et collecter les fichiers statiques

```bash
source /home/marchecm/Marche-CM/backend/venv/bin/activate
cd /home/marchecm/Marche-CM/backend

python manage.py migrate
python manage.py collectstatic --noinput
```

### Créer le superadmin Django

```bash
python manage.py createsuperuser
# Entrer email, username, mot de passe
```

---

## 10. Lancer le backend comme service permanent

On crée un **service systemd** : il démarre automatiquement, redémarre si ça plante.

```bash
sudo nano /etc/systemd/system/marchecm.service
```

Coller exactement ceci (remplacer les chemins si nécessaire) :

```ini
[Unit]
Description=Marche CM Backend (Daphne ASGI)
After=network.target postgresql.service redis.service

[Service]
Type=simple
User=marchecm
WorkingDirectory=/home/marchecm/Marche-CM/backend
ExecStart=/home/marchecm/Marche-CM/backend/venv/bin/daphne \
    -b 127.0.0.1 \
    -p 8000 \
    config.asgi:application
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

### Démarrer le service

```bash
sudo systemctl daemon-reload
sudo systemctl enable marchecm
sudo systemctl start marchecm

# Vérifier que ça tourne
sudo systemctl status marchecm
# Doit afficher "active (running)" en vert
```

### Voir les logs en temps réel

```bash
sudo journalctl -u marchecm -f
# Ctrl+C pour quitter
```

---

## 11. Installer et configurer Nginx

Nginx est le "portier" : il reçoit les connexions HTTPS et les redirige vers Django.

```bash
sudo apt install -y nginx
sudo systemctl enable nginx
```

### Créer la configuration du site

```bash
sudo nano /etc/nginx/sites-available/marchecm
```

Coller ceci (remplacer `api.TON_DOMAINE.com`) :

```nginx
server {
    listen 80;
    server_name api.TON_DOMAINE.com;

    # Taille max des fichiers uploadés (documents KYC, vidéos...)
    client_max_body_size 250M;

    # Fichiers statiques Django (admin, etc.)
    location /static/ {
        alias /home/marchecm/Marche-CM/backend/staticfiles/;
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    # Fichiers média (avatars, images produits...)
    location /media/ {
        alias /home/marchecm/Marche-CM/backend/media/;
        expires 7d;
    }

    # WebSockets
    location /ws/ {
        proxy_pass http://127.0.0.1:8000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 86400;
    }

    # Tout le reste → Django
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 60s;
        proxy_read_timeout 60s;
    }
}
```

### Activer le site

```bash
sudo ln -s /etc/nginx/sites-available/marchecm /etc/nginx/sites-enabled/
sudo nginx -t
# Doit afficher : syntax is ok / test is successful

sudo systemctl restart nginx
```

---

## 12. Obtenir un certificat SSL gratuit (HTTPS)

Let's Encrypt donne des certificats HTTPS **gratuits** valables 90 jours (renouvelés automatiquement).

> **Prérequis** : le domaine doit pointer vers ton serveur AVANT cette étape (voir étape 13).

```bash
sudo apt install -y certbot python3-certbot-nginx

sudo certbot --nginx -d api.TON_DOMAINE.com
# Entrer ton email
# Accepter les conditions (Y)
# Choisir "2" pour redirection automatique HTTP→HTTPS
```

Certbot modifie automatiquement la config Nginx pour HTTPS.

### Vérifier le renouvellement automatique

```bash
sudo certbot renew --dry-run
# Doit dire "Congratulations, all simulated renewals succeeded"
```

---

## 13. Configurer ton nom de domaine

### Chez ton registrar (Namecheap, OVH, Gandi...)

Aller dans la gestion DNS de ton domaine et ajouter ces enregistrements :

| Type | Nom | Valeur | TTL |
|---|---|---|---|
| `A` | `api` | `49.13.XXX.XXX` (ton IP serveur) | 300 |
| `A` | `@` ou `www` | `49.13.XXX.XXX` | 300 |

> La propagation DNS prend **5 à 30 minutes**. Pour vérifier :
> ```bash
> nslookup api.TON_DOMAINE.com
> # Doit afficher ton IP serveur
> ```

---

## 14. Vérifier que tout fonctionne

### Test 1 — Backend répond

```bash
curl https://api.TON_DOMAINE.com/api/health/
# Doit répondre : {"status": "ok"} ou similaire
```

### Test 2 — Admin Django accessible

Ouvrir dans un navigateur :
```
https://api.TON_DOMAINE.com/admin/
```
Se connecter avec les identifiants créés à l'étape 9.

### Test 3 — WebSocket (optionnel)

```bash
# Installer wscat
npm install -g wscat

wscat -c wss://api.TON_DOMAINE.com/ws/notifications/
# Si ça se connecte, les WebSockets fonctionnent
```

### Test 4 — Redis actif

```bash
sudo systemctl status redis-server
# → active (running)

redis-cli ping
# → PONG
```

### Test 5 — Base de données

```bash
cd /home/marchecm/Marche-CM/backend
source venv/bin/activate
python manage.py showmigrations
# Toutes les migrations doivent avoir un [X]
```

---

## 15. Mettre à jour l'application

À chaque fois que tu modifies le code et que tu veux déployer :

```bash
cd /home/marchecm/Marche-CM
git pull origin main

cd backend
source venv/bin/activate
pip install -r requirements.txt
python manage.py migrate
python manage.py collectstatic --noinput

sudo systemctl restart marchecm
sudo systemctl status marchecm
```

---

## 16. Sauvegardes

### Sauvegarde automatique de la base de données

```bash
sudo nano /home/marchecm/backup_db.sh
```

Coller :

```bash
#!/bin/bash
BACKUP_DIR="/home/marchecm/backups"
DATE=$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

pg_dump -U marche_user -h 127.0.0.1 marche_cm \
    > $BACKUP_DIR/db_$DATE.sql

# Garder seulement les 7 dernières sauvegardes
ls -t $BACKUP_DIR/db_*.sql | tail -n +8 | xargs rm -f

echo "Sauvegarde terminée : $BACKUP_DIR/db_$DATE.sql"
```

```bash
chmod +x /home/marchecm/backup_db.sh

# Configurer la sauvegarde automatique chaque nuit à 2h
crontab -e
# Ajouter cette ligne :
0 2 * * * /home/marchecm/backup_db.sh >> /home/marchecm/backup.log 2>&1
```

### Restaurer une sauvegarde

```bash
psql -U marche_user -h 127.0.0.1 marche_cm < /home/marchecm/backups/db_YYYYMMDD_HHMMSS.sql
```

---

## 17. Checklist finale

Avant de lancer officiellement :

### Infrastructure
- [ ] Serveur VPS actif et accessible en SSH
- [ ] Domaine acheté et DNS configuré
- [ ] PostgreSQL installé et base de données créée
- [ ] Redis installé et actif (`redis-cli ping` → PONG)
- [ ] Certificat SSL installé (`https://api.TON_DOMAINE.com` fonctionne)

### Backend
- [ ] `.env` rempli avec de vrais secrets (pas les valeurs exemple)
- [ ] `DEBUG=False` dans `.env`
- [ ] `python manage.py migrate` exécuté
- [ ] `python manage.py collectstatic` exécuté
- [ ] Service `marchecm` actif (`systemctl status marchecm`)
- [ ] `/api/health/` répond en HTTPS
- [ ] Admin Django accessible

### Sécurité
- [ ] Les clés NotchPay de l'`.env.example` remplacées par les vraies clés live
- [ ] `NOTCHPAY_AUTO_PAYOUT=False` (activer seulement après tests)
- [ ] Pare-feu actif (`sudo ufw status`)
- [ ] Connexion root SSH désactivée (optionnel mais recommandé)

### Données
- [ ] Sauvegarde automatique configurée (crontab)
- [ ] Superadmin créé

---

## Commandes utiles (référence rapide)

```bash
# Voir les logs du backend en temps réel
sudo journalctl -u marchecm -f

# Redémarrer le backend
sudo systemctl restart marchecm

# Redémarrer Nginx
sudo systemctl restart nginx

# Vérifier l'espace disque
df -h

# Vérifier la mémoire
free -h

# Voir les connexions actives
ss -tlnp

# Accéder à PostgreSQL
psql -U marche_user -h 127.0.0.1 marche_cm

# Accéder à Redis
redis-cli

# Voir les erreurs Nginx
sudo tail -f /var/log/nginx/error.log
```

---

## En cas de problème

| Symptôme | Solution |
|---|---|
| `502 Bad Gateway` | Le backend ne tourne pas → `systemctl restart marchecm` et voir les logs |
| `Connection refused` | Nginx non démarré → `systemctl restart nginx` |
| `PONG` absent de Redis | `systemctl start redis-server` |
| Migration échoue | Vérifier `DATABASE_URL` dans `.env` |
| Certificat SSL expiré | `sudo certbot renew` |
| `ImproperlyConfigured` au démarrage | Lire le message d'erreur dans les logs — souvent une variable `.env` manquante |
