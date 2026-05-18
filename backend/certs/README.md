# Certificats SSL locaux

Ces fichiers sont destines uniquement au developpement local.

Generation:

```bash
cd backend
python scripts/generate_dev_ssl_cert.py
```

Sorties:
- `dev-localhost.key.pem`
- `dev-localhost.crt.pem`

Important:
- Ne pas utiliser ces certificats auto-signes en production.
- Sur Render, le SSL/TLS public est fourni automatiquement par la plateforme pour `*.onrender.com` et les domaines custom verifies.
