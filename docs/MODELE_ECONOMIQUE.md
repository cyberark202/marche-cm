# Marché CM — Modèle économique & bouclier de responsabilité

> Objectif : permettre à la plateforme de **gagner de l'argent sur chaque transaction**
> tout en **ne portant ni le risque produit, ni le risque transport, ni le risque de
> paiement**. Modèle retenu : **place de marché intermédiaire à séquestre (escrow)**.

⚠️ **Avertissement** : ce document conçoit le modèle commercial et technique. Sa **validité
juridique au Cameroun (OHADA, CEMAC/COBAC, loi e-commerce, GIMAC/BEAC)** doit être
confirmée par un avocat local avant exploitation. Les écrans de consentement décrits ici
sont la condition *technique* du bouclier, pas une garantie *légale*.

---

## 1. Principe fondateur

**Marché CM n'est jamais ni vendeur, ni acheteur, ni transporteur, ni propriétaire de la
marchandise, ni établissement de paiement.**

C'est un **intermédiaire technique de mise en relation** + un **agent de séquestre**.

- Le **contrat de vente** se forme directement entre l'**acheteur** et le **vendeur**.
- Le **contrat de transport** se forme directement entre le **client** et le **transitaire**.
- Tout l'argent transite par un **PSP agréé tiers (NotchPay)** — la plateforme n'encaisse
  jamais en nom propre ; elle **instruit** la libération du séquestre selon des règles
  automatiques (preuve de livraison), jamais de façon discrétionnaire.

C'est cette neutralité, matérialisée par le consentement dans l'app, qui sépare
juridiquement la plateforme du risque.

---

## 2. Schéma — Flux d'argent (escrow) + zones de responsabilité

```mermaid
flowchart TB
    subgraph BUYER["🛒 ACHETEUR — responsable paiement & usage"]
        A1[Commande + paiement]
    end
    subgraph PLATFORM["⚖️ MARCHÉ CM — intermédiaire neutre + agent de séquestre (NE porte PAS le risque produit/transport)"]
        P1[Séquestre / Escrow<br/>fonds gelés via PSP]
        P2{Preuve de livraison<br/>code 4 chiffres + photo}
        P3[Arbitrage si litige<br/>décision documentée]
    end
    subgraph PSP["🏦 NOTCHPAY — PSP agréé, porte la responsabilité du paiement"]
        N1[MoMo / OM / Carte]
    end
    subgraph SELLER["📦 VENDEUR — responsable conformité & qualité produit"]
        S1[Expédie la marchandise]
    end
    subgraph CARRIER["🚚 TRANSITAIRE — responsable du transport & de l'intégrité"]
        C1[Livre + collecte le code]
    end

    A1 -->|paie| N1
    N1 -->|crédite le séquestre| P1
    P1 --> S1
    S1 --> C1
    C1 --> P2
    P2 -->|livraison confirmée| REL[💰 Libération automatique]
    P2 -->|contestée| P3
    REL -->|montant - commission| SELLER
    REL -->|frais de course| CARRIER
    REL -->|take rate + frais| FEE[Revenus plateforme]
    P3 -->|en faveur vendeur| SELLER
    P3 -->|remboursement| BUYER
    P3 -->|partage 50/50| BOTH[Répartition]
```

---

## 3. Matrice de transfert de responsabilité

| Risque / Obligation | Porté par | Mécanisme qui décharge la plateforme |
|---|---|---|
| Qualité / conformité du **produit** | **Vendeur** | KYB (RCCM), CGU vendeur, séquestre conditionné à la livraison |
| Intégrité pendant le **transport** | **Transitaire** | KYC transitaire, preuve d'enlèvement, code de livraison |
| Légalité de **l'usage** du produit | **Acheteur** | Acceptation CGU + KYC acheteur |
| **Traitement du paiement** (fraude, AML) | **PSP NotchPay** (agréé) | La plateforme n'encaisse pas en nom propre |
| **Détention des fonds** | Séquestre automatisé | Mandat de séquestre signé, libération par règle |
| **Litige** | Parties au contrat | Arbitrage tripartite **documenté** (preuves), décision opposable |
| **Données / KYC** | Plateforme (conformité LCB-FT) | Consentement horodaté + signature électronique |

---

## 4. Schéma — Points de capture de revenus (8 sources, sans porter le risque)

```mermaid
flowchart LR
    TXN[Transaction] --> R1[1. Commission vendeur<br/>take rate 5–8%]
    TXN --> R2[2. Frais de service acheteur<br/>fixe ou %]
    TXN --> R3[3. Commission transitaire<br/>10–15% de la course]
    ESC[Séquestre] --> R4[4. Float sur fonds gelés*]
    WTH[Retrait MoMo/OM] --> R5[5. Frais de retrait]
    SELLER2[Vendeurs] --> R6[6. Abonnement Premium<br/>vitrine · RFQ illimités]
    SELLER2 --> R7[7. Mise en avant / pub<br/>ranking · promo]
    LIT[Litige] --> R8[8. Frais d'arbitrage<br/>à la partie perdante]
```

\* Le float sur fonds séquestrés est soumis à la réglementation CEMAC/COBAC — à valider
avec le PSP, sinon le retirer du modèle.

---

## 5. Conditions à matérialiser dans l'app (lien modèle ↔ code)

Le bouclier ne tient que si l'app **capture le consentement** de façon traçable :

1. **CGU + statut d'intermédiaire** affichés et **acceptés** (case + horodatage) à l'inscription.
2. **KYC/KYB avec signature électronique** (wizard 6 écrans — `screens-kyc.jsx`).
   Backend : `POST /api/auth/kyc/submit/` (`doc_type`, `file`, `signature`, `consent_accepted`
   → `consent_accepted_at` horodaté serveur).
3. **Mandat de séquestre** accepté au **premier paiement**.
4. **Preuve de livraison** (code 4 chiffres — déjà présent côté livreur).
5. **Traçabilité d'arbitrage** (preuves horodatées — hub de litige multi-vue).
6. **Mentions de déni de responsabilité** sur les écrans produit / panier / litige.

---

## 6. Statut d'implémentation

| Condition | État |
|---|---|
| KYC + signature + `consent_accepted_at` | ✅ backend ; ⚠️ front : flux `app` à re-skiner, `Clients` à créer |
| CGU/statut intermédiaire à l'inscription | ❌ à ajouter |
| Mandat de séquestre au 1er paiement | ❌ à ajouter |
| Code de livraison 4 chiffres | ✅ Driver |
| Arbitrage documenté | 🟠 partiel (hub multi-vue à unifier) |
| Mentions déni de responsabilité | ❌ à ajouter |
