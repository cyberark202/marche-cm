# Configuration NotchPay (Production / Sandbox)

Ce projet utilise NotchPay pour:
- checkout wallet (`POST /payments`)
- disbursement/payout (`POST /transfers`)
- webhooks checkout + transfer

## 1) Configuration cote dashboard NotchPay

1. Creez/ouvrez votre application NotchPay.
2. Recuperez vos cles:
- `public_key`
- `private_key` (utilisee comme `X-Grant` pour les transfers)
3. Configurez les webhooks:
- checkout webhook URL: `https://<backend>/api/wallets/notchpay/checkout/webhook/`
- disburse webhook URL: `https://<backend>/api/wallets/notchpay/disburse/webhook/`
4. Activez une signature HMAC webhook et copiez la valeur secrete.
5. Pour les transfers/payouts:
- activez les channels necessaires (ex: `cm.mtn`, `cm.orange`)
- whitelistez les IP sortantes de votre backend si votre compte NotchPay l’exige pour l’API Transfer.

## 2) Variables a renseigner cote code (.env)

Obligatoires:
- `NOTCHPAY_ENABLED=True`
- `NOTCHPAY_API_BASE=https://api.notchpay.co`
- `NOTCHPAY_CURRENCY=XAF`
- `NOTCHPAY_PUBLIC_KEY=<votre_public_key>`
- `NOTCHPAY_PRIVATE_KEY=<votre_private_key>`
- `NOTCHPAY_CHECKOUT_WEBHOOK_SECRET=<secret_hmac_checkout>`
- `NOTCHPAY_DISBURSE_WEBHOOK_SECRET=<secret_hmac_disburse>`

Recommandees:
- `NOTCHPAY_WEBHOOK_TOKEN=<token_interne_optionnel>`
- `NOTCHPAY_CHECKOUT_CALLBACK_URL=<url_callback_front_ou_backend>`
- `NOTCHPAY_CHECKOUT_RETURN_URL=<url_retour_checkout>`
- `NOTCHPAY_DISBURSE_CALLBACK_URL=https://<backend>/api/wallets/notchpay/disburse/webhook/`

Channels payout:
- `NOTCHPAY_WITHDRAW_CHANNEL_MTN=cm.mtn`
- `NOTCHPAY_WITHDRAW_CHANNEL_ORANGE=cm.orange`
- `NOTCHPAY_WITHDRAW_CHANNEL_VISA=`
- `NOTCHPAY_WITHDRAW_CHANNEL_MASTERCARD=`
- `NOTCHPAY_WITHDRAW_CHANNEL_PAYPAL=`

Auto payout (si utilise):
- `NOTCHPAY_AUTO_PAYOUT=True|False`
- `NOTCHPAY_MTN_NUMBER=<numero_destination_auto_payout>`
- `NOTCHPAY_STORE_NAME=<nom_affichage>`

## 3) Endpoints backend exposes

- `POST /api/wallets/notchpay/checkout/webhook/`
- `POST /api/wallets/notchpay/disburse/webhook/`

Compatibilite legacy maintenue temporairement:
- `POST /api/wallets/paydunya/checkout/webhook/`
- `POST /api/wallets/paydunya/disburse/webhook/`

## 4) Verification rapide apres configuration

1. `python manage.py check`
2. `python manage.py test apps.wallets.tests`
3. Topup test:
- `POST /api/wallets/topup/` -> verifier `checkout_url` present
4. Webhook test:
- envoyer un event signe sur `/api/wallets/notchpay/checkout/webhook/`
- verifier passage transaction `PENDING -> SUCCESS|FAILED`
