#!/bin/bash
set -e

echo "=== STARTING DEPLOYMENT ==="

# 1. Download tarball from S3
echo "Downloading backend.tar.gz from S3..."
aws s3 cp s3://market-cm/deploy/backend.tar.gz /tmp/backend.tar.gz --region eu-north-1

# 2. Extract tarball
echo "Extracting tarball..."
rm -rf /tmp/backend_deploy
mkdir -p /tmp/backend_deploy
tar -xzf /tmp/backend.tar.gz -C /tmp/backend_deploy

# 3. Create backup of current backend directory
TIMESTAMP=$(date +%Y%m%d%H%M%S)
BACKUP_DIR="/opt/marche-cm/backend_backup_$TIMESTAMP"
echo "Creating backup at $BACKUP_DIR..."
cp -r /opt/marche-cm/backend "$BACKUP_DIR"

# 4. Copy new code files (excluding .env.aws, certs, db.sqlite3)
echo "Copying new code files..."
cp -rf /tmp/backend_deploy/backend/* /opt/marche-cm/backend/
chmod -R 777 /opt/marche-cm/backend

# 5. Build and restart containers
cd /opt/marche-cm/backend
echo "Rebuilding and restarting docker compose..."
docker compose -f docker-compose.aws.yml --env-file .env.aws up -d --build

# 6. Collect static files
echo "Collecting static files..."
docker compose -f docker-compose.aws.yml --env-file .env.aws run --rm web python manage.py collectstatic --noinput

# 7. Check health
echo "Verifying health..."
curl -fsS -H "X-Forwarded-Proto: https" -H "Host: localhost" http://localhost:8000/api/health/

echo "=== DEPLOYMENT COMPLETED SUCCESSFULLY ==="
