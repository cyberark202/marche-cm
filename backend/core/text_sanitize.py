"""Redaction des liens/URLs dans le contenu généré par les utilisateurs.

Anti-désintermédiation + anti-hameçonnage : la marketplace ne doit pas servir
de canal pour partager des liens externes (sites, wa.me / t.me, redirections)
ni des adresses e-mail permettant de contourner l'escrow et la plateforme.

La redaction est appliquée côté ÉCRITURE (à la source : serializers + consumer
WebSocket) : le contenu est stocké déjà propre, donc TOUTES les réponses API le
restent sans surcoût de sérialisation ni risque d'abîmer les URLs légitimes
(images produit, pièces jointes) portées par des champs distincts.

Pas de dépendance externe : `re` de la stdlib suffit. Les motifs sont bornés
(pas de quantificateur imbriqué) pour rester linéaires — insensibles au ReDoS.
"""
from __future__ import annotations

import re

LINK_PLACEHOLDER = "[lien retiré]"
EMAIL_PLACEHOLDER = "[contact retiré]"

# TLD courants + ceux fréquemment utilisés pour contourner (raccourcisseurs,
# messageries). Liste curée : un domaine nu n'est masqué que si son TLD y figure,
# ce qui limite les faux positifs sur du texte ordinaire ("Node.js", "S.A.R.L").
_TLDS = (
    "com|net|org|io|co|app|dev|me|ly|gg|to|cc|xyz|info|biz|shop|store|online|"
    "site|link|page|pro|tv|fm|cm|fr|ng|gh|sn|ci|ma|tg|bj|cd|ga|cf|ml|tk|us|uk|"
    "ca|de|es|it|be|nl|ru|cn|in|tr|br"
)

# Obfuscations « point » les plus courantes — uniquement les formes entre
# crochets/parenthèses, jamais les mots " dot "/" point " (trop de faux positifs
# en français : "point de vente", "point relais"...).
_DOT_OBFUSCATION = re.compile(r"\s*[\[({]\s*(?:\.|dot|point)\s*[\])}]\s*", re.IGNORECASE)

# URL avec schéma explicite, y compris la forme obfusquée « hxxp:// ».
_SCHEME_URL = re.compile(r"(?i)\b(?:h(?:tt|xx)ps?|ftp)://[^\s]+")

# Préfixe www. explicite (avec ou sans schéma).
_WWW_URL = re.compile(r"(?i)\bwww\.[^\s]+")

# Adresse e-mail (masquée avant les domaines nus pour ne pas la couper en deux).
_EMAIL = re.compile(r"(?i)\b[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}\b")

# Domaine nu (avec sous-domaines et chemin/port optionnels) dont le TLD est curé.
_BARE_DOMAIN = re.compile(
    r"(?i)\b(?:[a-z0-9](?:[a-z0-9\-]{0,61}[a-z0-9])?\.)+(?:" + _TLDS + r")"
    r"(?=[\s/:?#]|$)(?:[:/?#][^\s]*)?"
)

# Numéros de téléphone (opt-in — voir `redact_phones`). VOLONTAIREMENT conservateur
# pour ne PAS masquer les montants FCFA (souvent écrits « 2 320 000 » / « 85.000 »
# avec séparateurs) :
#   * tout numéro au format international « +… » (quasi zéro faux positif) ;
#   * un bloc de 9 chiffres CONTIGUS commençant par 6 ou 2 (mobile/fixe CM),
#     forme d'un numéro copié tel quel — les montants portent des séparateurs.
_PHONE = re.compile(r"(?<!\d)(?:\+\d[\d\s().\-]{6,15}\d|[62]\d{8})(?!\d)")


def redact_links(text: str, *, redact_phones: bool = False) -> str:
    """Remplace URLs, domaines nus et e-mails par un libellé neutre.

    Avec ``redact_phones=True``, masque aussi les numéros de téléphone (opt-in,
    car ambigu avec les montants dans ce marché — cf. `_PHONE`).

    Retourne la valeur inchangée si ``text`` n'est pas une chaîne ou est vide.
    Idempotent : les libellés de remplacement ne contiennent ni schéma ni TLD.
    """
    if not text or not isinstance(text, str):
        return text
    cleaned = _DOT_OBFUSCATION.sub(".", text)
    cleaned = _EMAIL.sub(EMAIL_PLACEHOLDER, cleaned)
    cleaned = _SCHEME_URL.sub(LINK_PLACEHOLDER, cleaned)
    cleaned = _WWW_URL.sub(LINK_PLACEHOLDER, cleaned)
    cleaned = _BARE_DOMAIN.sub(LINK_PLACEHOLDER, cleaned)
    if redact_phones:
        cleaned = _PHONE.sub(EMAIL_PLACEHOLDER, cleaned)
    return cleaned
