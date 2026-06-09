# Rapport d'Alignement Mobile ↔ Backend — Marché CM
**Rôles :** Principal DevOps Engineer · Principal Django Engineer · Flutter Lead  
**Date :** 2026-06-06  
**Statut :** KO (RÉSERVES BLOQUANTES)  

---

## 1. Résumé de l'Audit d'Alignement des APIs
L'audit a pour but de valider que les contrats d'interfaces entre les applications mobiles Flutter (`app`, `Clients`, `Driver App`, `admin`) et le backend Django sont parfaitement cohérents. Un script automatisé d'extraction et de comparaison statique (`compare.py`) a été exécuté.

| Indicateur | Valeur | Gravité | Verdict |
| :--- | :---: | :---: | :--- |
| **Appels Mobiles absents du Backend** | **3** | 🔴 Critique | Les applications mobiles appellent des fonctionnalités inexistantes côté serveur. |
| **Routes Backend non utilisées par le Mobile**| **69** | 🟡 Faible | Routes mortes, d'administration ou destinées à des fonctionnalités futures. |

---

## 2. Incohérences Majeures Détectées (Cibles de Remédiation)

Les 3 endpoints suivants sont appelés par le code Flutter des applications mobiles mais **n'ont aucune route correspondante** exposée sur le backend Django :

### 🔴 1. `/api/driver/reviews/` (GET)
* **Application** : `Driver App`
* **Fichier Frontend** : [reviews_page.dart:11](file:///e:/project/Marche%20CM/frontend/Driver%20App/app/lib/features/profile/presentation/reviews_page.dart#L11)
* **Comportement Observé** : La Driver App tente de récupérer les avis laissés par les acheteurs sur le livreur via un appel `DriverDioClient.dio.get("/api/driver/reviews/")` alimentant le Riverpod `_reviewsProvider`.
* **Impact** : L'écran "Mes avis" de l'application livreur affiche une erreur de chargement systématique en production (HTTP 404).

### 🔴 2. `/api/seller/stats/` (GET)
* **Application** : `Vendeur (app)`
* **Fichier Frontend** : [supplier_stats_page.dart:51](file:///e:/project/Marche%20CM/frontend/app/lib/features/supplier/supplier_stats_page.dart#L51)
* **Comportement Observé** : L'application vendeur tente d'afficher les statistiques de CA, volumes et top produits du fournisseur via un appel `_api.getObject("/api/seller/stats/?range=...")`.
* **Impact** : L'onglet de performance vendeur de l'application mobile est totalement inutilisable et vide en production (HTTP 404).

### 🔴 3. `/api/shipments/{param}/resend_otp/` (POST)
* **Application** : `Driver App`
* **Fichier Frontend** : [delivery_proof_page.dart:85](file:///e:/project/Marche%20CM/frontend/Driver%20App/app/lib/features/delivery/presentation/delivery_proof_page.dart#L85)
* **Comportement Observé** : Lors de la livraison, si l'acheteur n'a pas reçu son code PIN temporaire de validation par SMS, le livreur peut cliquer sur "Renvoyer le code à l'acheteur". Cela déclenche un POST vers `/api/shipments/{shipmentId}/resend_otp/`.
* **Impact** : L'action de renvoi échoue systématiquement en production avec une erreur HTTP 404, bloquant potentiellement le livreur sur place si le premier SMS de l'acheteur a été perdu par le réseau télécom.

---

## 3. Endpoints Backend Non Utilisés par le Mobile (Synthèse)
Le script identifie 69 endpoints exposés par Django qui ne sont pas référencés dans le code Flutter. Les principales catégories sont :
* **Routes de Gestion de Litiges / Audit** (`/api/audit/events/`, `/api/disputes/{id}/decide/`, `/api/compliance/kyc/{id}/approve/`) : Ces routes sont principalement consommées par le client API interne de l'administration ou les scripts d'opérations financières.
* **Webhooks de prestataires de paiement** (`/api/wallets/notchpay/checkout/webhook/`, `/api/wallets/paydunya/checkout/webhook/`) : Destinés uniquement à être appelés par les serveurs tiers (NotchPay, PayDunya) pour la réconciliation des recharges.
* **Fonctionnalités administratives ou de sécurité** (`/api/users/{id}/suspend/`, `/api/partner-api-keys/`) : Utilisées via des consoles dédiées ou non encore intégrées dans le frontend mobile actuel.

---

## 4. Recommandations et Plan de Résolution

> [!IMPORTANT]
> **Action Immédiate : Implémenter les Shims Backend (Priorité 1 / Bloquant)**  
> Afin de ne pas bloquer la sortie des applications mobiles et d'éviter des plantages HTTP 404, le backend Django doit au minimum implémenter des endpoints de fallback (shims) renvoyant des données par défaut ou une structure vide correcte :
> 
> 1. **Pour `/api/driver/reviews/`** : Exposer un endpoint dans le module logistics renvoyant une liste d'avis vide avec une moyenne de 5.0 :
>    ```json
>    {
>      "average_rating": 5.0,
>      "reviews_count": 0,
>      "distribution": {"1":0,"2":0,"3":0,"4":0,"5":0},
>      "tags": [],
>      "reviews": []
>    }
>    ```
> 2. **Pour `/api/seller/stats/`** : Exposer un endpoint dans le module catalog/orders calculant les ventes réelles ou renvoyant un tableau de bord vide conforme :
>    ```json
>    {
>      "total_revenue": 0.0,
>      "delta_pct": 0.0,
>      "orders_count": 0,
>      "buyers_count": 0,
>      "new_buyers_count": 0,
>      "avg_rating": 5.0,
>      "reviews_count": 0,
>      "acceptance_rate": 100.0,
>      "on_time_rate": 100.0,
>      "series": [],
>      "top_products": []
>    }
>    ```
> 3. **Pour `/api/shipments/{id}/resend_otp/`** : Implémenter la route sur `ShipmentViewSet` qui récupère le code de confirmation associé au shipment, ré-envoie le SMS via le provider de messagerie configuré, et retourne un statut HTTP 200.
