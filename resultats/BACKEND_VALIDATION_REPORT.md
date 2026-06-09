# Rapport de Validation Backend — Marché CM
**Rôles :** Principal Django Engineer · Security Engineer · Principal Database Engineer  
**Date :** 2026-06-06  
**Statut :** CONFORME AVEC REMARQUES  

---

## 1. Résumé de l'Audit de Sécurité du Code
L'audit read-only du code source Django/DRF de production a été effectué selon une méthodologie **Zero Trust** afin de confirmer l'existence et l'efficacité des correctifs de sécurité critiques et majeurs déclarés.

| Domaine | Risque Initial | Niveau de Sécurité Validé | Preuves Techniques |
| :--- | :--- | :---: | :--- |
| **1. Authentification & Sessions** | Vol de jetons / comptes dormants | 🟢 Élevé | SimpleJWT rotation + blacklist + invalidation sessions active |
| **2. Gestion du Wallet** | Double débit / Race condition | 🟢 Élevé | `select_for_update` + Idempotence cryptographique |
| **3. Séquestre & Transact.** | Argent bloqué en cas d'erreur | 🟢 Élevé | `transaction.atomic()` unifiant annulation & remboursement |
| **4. KYC & Fichiers** | IDOR / Upload malveillant (shell) | 🟢 Élevé | Magic bytes verification + EXIF strip + BOLA checks |

---

## 2. Analyse Technique & Preuves de Code

### 2.1 Authentification & Suspension (SecOps)
* **Configuration SimpleJWT** : Les jetons d'accès ont une durée de vie réduite de **15 minutes** et les jetons de rafraîchissement de **7 jours**. La rotation des jetons de rafraîchissement est activée et couplée au mécanisme de mise en liste noire (`BlacklistMixin`), invalidant instantanément l'ancien jeton de rafraîchissement lors d'un `token_refresh`.
* **Révocation de Session (Logout)** : La vue `LogoutView` effectue la mise en liste noire explicite du Refresh Token fourni, bloquant toute tentative de réutilisation.
* **Blocage / Suspension Utilisateur** : Les actions `@action` `suspend` et `unsuspend` du `UserViewSet` permettent de suspendre un utilisateur (bascule `is_active = False` en base) et d'invalider immédiatement toutes ses sessions Django actives via une suppression groupée dans la table de sessions (`django.contrib.sessions.models.Session`), coupant instantanément les connexions actives et rejetant les futurs rafraîchissements de jetons.

### 2.2 Sécurité Financière & Idempotence (Wallet)
* **Race Conditions (Mutations Wallet)** : Toutes les opérations de débit, crédit et blocage de fonds utilisent le verrouillage pessimiste via la clause `select_for_update(of=('self',))` sur l'enregistrement du portefeuille de l'utilisateur concerné. Cela sérialise les transactions concurrentes et prévient toute incohérence de solde ou dépassement de solde disponible.
* **Idempotence des Dépôts** : L'implémentation repose sur le modèle `IdempotencyRecord` stockant l'empreinte SHA-256 du corps de la requête.
  * *Hardening* : Afin d'éviter des rejeux malveillants à travers le changement d'informations dynamiques (comme un code PIN ou un code OTP), la logique de hachage de la clé d'idempotence filtre et exclut ces données dynamiques du calcul de l'empreinte de la payload.
* **Protection du PIN Wallet** : Un mécanisme de blocage temporaire est implémenté : après un nombre maximal de tentatives échouées de saisie du code PIN (`max_attempts`), le portefeuille est verrouillé pour une durée configurée (`lock_minutes`), prévenant les attaques de force brute.

### 2.3 Séquestre & Commandes (Escrow)
* **Séquestre Centralisé** : Les opérations d'écriture directes sur `EscrowService` sont désactivées pour prévenir les états fantômes (double débit / solde incohérent). Toutes les mutations transitent par le service d'orchestration financière unifié `OrderFinanceService`.
* **Atomisme de l'Annulation** : 
  * *Audit Ref C-3* : La fonction `cancel_order` dans `OrderFinanceService` enveloppe la transition de statut de la commande en `CANCELLED` et le remboursement des fonds bloqués de l'acheteur dans un bloc `with transaction.atomic()`. Si le remboursement de l'escrow échoue, la commande n'est pas modifiée en base de données, évitant ainsi le blocage permanent de l'argent de l'acheteur.

### 2.4 KYC & Uploads (Compliance)
* **Support des Documents KYC** : Les types de documents `PROOF_ADDRESS` et `SELFIE` sont désormais acceptés et correctement traités par le validateur `ComplianceDocumentSerializer`.
* **Protection IDOR / BOLA** : L'accès aux documents de conformité est strictement cloisonné au niveau de la requête SQL dans `ComplianceDocumentViewSet.get_queryset()`. Un utilisateur ne peut lister ou récupérer que ses propres documents ou les documents liés à ses transactions logistiques. Toute tentative d'accès à un document étranger retourne une erreur HTTP `404 Not Found` (anti-énumération) au lieu d'un `403 Forbidden`.
* **Sécurisation des Médias Chargés** :
  * *Magic Bytes* : Le fichier chargé est vérifié au niveau binaire (signature hexadécimale) dans `upload_security.py` pour s'assurer que le contenu correspond réellement à l'extension déclarée, bloquant le chargement de scripts PHP/Python déguisés en JPEG.
  * *Sanitisation EXIF* : Les métadonnées EXIF (comprenant les coordonnées GPS et les métadonnées de l'appareil photo de l'utilisateur) sont purgées à la volée lors de la validation des images d'identité ou des preuves de livraison.

---

## 3. Recommandations P1/P2

> [!IMPORTANT]
> **R-BACK-001 : Découplage de `broadcast_event` (Priorité 1 / Résilience)**  
> La fonction `broadcast_event` appelle de manière synchrone le layer de communication Redis Channels. Si le cache Redis est indisponible ou subit une micro-coupure réseau, l'appel lève une exception 500 et interrompt la transaction métier parente (ex: création de produit ou modification de profil).  
> *Action requise* : Envelopper l'appel dans un bloc `try/except` avec logging d'erreur pour que l'échec de la notification temps réel ne fasse jamais crasher une action utilisateur critique.

> [!WARNING]
> **R-BACK-002 : Durcissement du JWT_SECRET (Priorité 2 / SecOps)**  
> Actuellement, le jeton JWT utilise l'algorithme asymétrique `RS256` avec une clé stockée en variable d'environnement. S'assurer de la rotation semestrielle de cette paire de clés privées/publiques via des scripts automatisés.
