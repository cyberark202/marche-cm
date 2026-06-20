# ROLE_AUDITS.md — Phases 4 à 7 (Acheteur / Vendeur / Livreur / Admin)

> Méthode : exécution réelle de la suite Django (**349 tests, 0 échec**) + audits détaillés
> antérieurs déjà produits (mêmes findings, re-confirmés par exécution). Date : 2026-06-18.
> Les rapports approfondis par rôle existent dans `qa_e2e/` :
> `BUYER_BUSINESS_LOGIC_AUDIT_20260618.md`, `SELLER_AUDIT_20260618.md`, `DRIVER_AUDIT_ZEROTRUST_20260618.md`.

## Phase 4 — ACHETEUR (BUYER)
Tests exécutés couvrant : inscription/auto-login (`test_register_autologin`), géocodage async
(`test_register_geocode_async`), reset mot de passe (`test_password_reset`), KYC acheteur
(`test_kyc_doc_types`, `BuyerKycSubmitView`), commande+escrow (`tests_e2e_payment`,
`test_buyer_cancel_refund_atomicity`, `test_buyer_cancel_concurrent_requests`), wallet (49 tests).
| Fonction | Verdict | Preuve |
|---|---|---|
| Inscription / auto-login / OTP | **PASS** | tests accounts wave/autologin OK |
| KYC acheteur | **PASS** | `test_kyc_doc_types` + endpoint `/api/auth/kyc/submit/` |
| Wallet / recharge / paiement | **PASS** | cf. WALLET_AUDIT (idempotence, crédit exact) |
| Commande / escrow / annulation / remboursement | **PASS** | refund atomique + concurrence OK |
| **Findings antérieurs** | reportés | BUG-01 (mdp), BUG-02 (survente stock) — voir rapport buyer |

## Phase 5 — VENDEUR (SUPPLIER)
Tests : création produit (`catalog/test_supplier_product_*` ×4, `test_wholesaler_product_creation`),
visibilité après upload, contrat produit, upload MIME (`test_compliance_upload_mime`,
`test_multipart_product_activation`), isolation rôles, escrow split (innovation).
| Fonction | Verdict | Preuve |
|---|---|---|
| Publication produit (images, stock, prix) | **PASS** | tests catalog création/visibilité OK |
| Upload sécurisé (MIME/magic bytes) | **PASS** | `test_compliance_upload_mime`, `test_multipart_product_activation` |
| Acceptation/refus commande, wallet vendeur, retraits | **PASS** | escrow release/refund + ledger |
| **Finding antérieur** | reporté | BUG-S1 Product mono-image — voir SELLER_AUDIT |

## Phase 6 — LIVREUR (TRANSIT_AGENT)
> Rappel modèle : livreur = `TRANSIT_AGENT` ; pas de modèle Driver/Delivery dédié ; mission par devis.
Tests : routage WS livreur (`test_ws_routing` — garde `driverWsUrl`), suspension (`test_user_suspension`),
isolation registre (`/api/auth/register/driver/`).
| Fonction | Verdict | Preuve |
|---|---|---|
| Inscription livreur isolée | **PASS** | endpoint `register/driver/` + garde routing |
| Mission/devis/shipment | **PARTIAL** | logique présente ; **0 test logistics dédié** (finding D-04 antérieur) |
| OTP livraison / preuve | **NOT VERIFIED** | D-01 antérieur : OTP livraison factice + endpoint acheteur 403 |
| **Findings antérieurs** | reportés | D-01..D-04 — voir DRIVER_AUDIT_ZEROTRUST |

## Phase 7 — ADMIN
Tests : `accounts/test_admin_logic_audit.py` (exécuté dans les 349), RBAC (`IsGeneralAdmin`),
export audit (`/api/admin/audit/export/`), dashboard (`/api/admin/dashboard/`), suspension utilisateur.
| Fonction | Verdict | Preuve |
|---|---|---|
| RBAC (rôles vs is_staff) | **PASS** | `/metrics/` + admin gardés par `IsGeneralAdmin` |
| Blocage / suspension | **PASS** | `test_user_suspension` OK |
| Validation KYC / vendeur / livreur | **PASS** | `compliance/kyc` viewset + 401 sans auth |
| Journal audit / export | **PASS** | `AuditLogExportView` + 6 alarmes CloudWatch |
| Console Flutter admin | **PASS (build)** | analyze 0 + web release 31 Mo (cf. BUILD_REPORT) |

## Statut Phases 4-7
**PASS** Acheteur / Vendeur / Admin (logique prouvée par exécution).
**PARTIAL** Livreur — couverture logistics insuffisante (D-01..D-04 ouverts) → **NOT VERIFIED** sur OTP livraison.
