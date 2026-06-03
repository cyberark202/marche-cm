MISSION : AUDIT E2E COMPLET APRÈS CORRECTIONS

Tu es un QA Lead, Security Engineer, Performance Engineer et Full Stack Architect.

Ton objectif est de vérifier que toutes les corrections apportées suite au premier rapport QA n'ont introduit aucune régression.

RÈGLE ABSOLUE :

Ne jamais supposer qu'un bug est corrigé.

Chaque fonctionnalité doit être testée réellement depuis le frontend jusqu'à la base de données.

Vérifier :

AUTH

* inscription
* connexion
* déconnexion
* reset password
* refresh token
* rôles

PRODUITS

* création
* édition
* suppression
* upload images
* upload vidéos
* visibilité

MARKETPLACE

* panier
* commande
* paiement
* annulation
* remboursement

WALLET

* dépôt
* retrait
* transfert
* verrouillage PIN
* historique

ESCROW

* création
* déblocage
* remboursement
* litige

LITIGES

* ouverture
* pièces jointes
* médiation
* résolution

MESSAGERIE

* temps réel
* images
* vidéos
* reconnexion websocket

ADMIN

* gestion utilisateurs
* validation KYC
* suspension
* réactivation

SÉCURITÉ

* SQL Injection
* XSS
* CSRF
* JWT forgé
* IDOR
* élévation de privilège
* brute force

Pour chaque anomalie :

* gravité
* reproduction
* endpoint concerné
* logs
* capture
* impact business

Produire :

QA_E2E_V2_REPORT.md

Ne clôturer la mission qu'après avoir validé 100% des parcours métier.



MISSION : LOAD TEST & STRESS TEST CENTRAL MARKET

Tu es :

* Principal Performance Engineer
* Cloud Architect AWS
* SRE
* Backend Expert

OBJECTIF :

Mesurer les limites réelles de Central Market.

Tester :

100
500
1000
2500
5000
7500
10000

utilisateurs simultanés.

Utiliser :

Locust
k6
ou JMeter

Créer des scénarios réalistes.

==================
SCÉNARIO 1
==========

60 %

navigation catalogue

* recherche
* filtres
* détails produit

==================
SCÉNARIO 2
==========

20 %

vendeurs

* connexion
* publication produit
* upload image

==================
SCÉNARIO 3
==========

10 %

acheteurs

* panier
* commande
* paiement

==================
SCÉNARIO 4
==========

5 %

wallet

* dépôt
* retrait
* consultation solde

==================
SCÉNARIO 5
==========

5 %

messagerie

* websocket
* envoi messages

MESURER :

* RPS
* CPU
* RAM
* IOPS
* Latence P50
* Latence P95
* Latence P99

Identifier :

* endpoints lents
* requêtes N+1
* locks PostgreSQL
* saturation Redis
* saturation websocket

OBJECTIFS :

Catalogue < 300 ms

API standard < 500 ms

Paiement < 2 s

95 % des requêtes < 1 s

Taux d'erreur < 1 %

Produire :

LOAD_TEST_REPORT.md

et

OPTIMIZATION_PLAN.md

avec toutes les optimisations nécessaires pour supporter 10000 utilisateurs simultanés.
