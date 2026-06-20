# WEBSOCKET_AUDIT.md — Phase 10 (Zero-Trust)

> Méthode : exécution réelle de `apps.realtime.test_ws_routing` (13 tests) +
> inventaire des consumers/routing. Date : 2026-06-18.

## Surface WebSocket
- Consumers : `chat/consumers.py`, `notifications/consumers.py`, `realtime/consumers.py`.
- Routing : `chat/routing.py`, `notifications/routing.py`, `realtime/routing.py`.
- Transport ASGI : Channels (`config/asgi.py`), backing Redis (channel layer).

## Preuves d'exécution (`Ran 13 tests … OK`)
| Test | Résultat | Ce qu'il prouve |
|---|---|---|
| `test_known_events_route_accepts_with_jwt` | **ok** | Connexion WS acceptée **avec JWT valide** sur `/ws/events/` |
| `test_unknown_driver_path_is_rejected_cleanly` | **ok** | Chemin livreur inconnu rejeté proprement (pas de crash) |
| `test_other_unknown_path_is_rejected_cleanly` | **ok** | Tout chemin inconnu rejeté proprement |
| Garde `driverWsUrl → /ws/events/` | **ok** | Régression front (mauvaise URL WS) verrouillée par test |
| (9 autres du module) | **ok** | Routage/auth/rejets |

## Couvert vs non couvert
| Aspect | Verdict | Note |
|---|---|---|
| Auth JWT à la connexion | **PASS** | prouvé par `…accepts_with_jwt` |
| Rejet chemins inconnus | **PASS** | 2 tests dédiés |
| Routage events/chat/notifications | **PASS** | routing + consumers présents, test routing OK |
| Expiration de token en cours de session | **NOT VERIFIED** | pas de test sur révocation/expiry mid-session |
| Connexions multiples / reconnexion / montée en charge WS | **NOT VERIFIED** | non testé en charge (hors périmètre validé) |
| « aucun message perdu » sous charge | **NOT VERIFIED** | nécessite test de charge WS dédié |

## Findings
- **WS-1 (MOYEN) — Pas de test d'expiration de token mid-session.** Un JWT qui expire pendant
  une session WS ouverte : comportement non prouvé. *Reco* : test fermeture/renégociation à l'expiry.
- **WS-2 (BAS) — Pas de test de charge WS.** Reconnexion massive / fan-out notifications non mesurés.

## Statut Phase 10
**PASS (routage + auth JWT + rejets)** ; **PARTIAL** sur résilience (expiry mid-session, charge) → NOT VERIFIED.
