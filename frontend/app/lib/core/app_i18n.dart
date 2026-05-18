import "package:flutter/widgets.dart";

class AppI18n {
  static const Map<String, Map<String, String>> _messages = {
    "state.loading": {"fr": "Chargement...", "en": "Loading..."},
    "state.retry": {"fr": "Reessayer", "en": "Retry"},
    "state.refresh": {"fr": "Rafraichir", "en": "Refresh"},
    "state.error.title": {
      "fr": "Une erreur est survenue",
      "en": "Something went wrong"
    },
    "common.cancel": {"fr": "Annuler", "en": "Cancel"},
    "common.close": {"fr": "Fermer", "en": "Close"},
    "common.send": {"fr": "Envoyer", "en": "Send"},
    "common.created": {"fr": "Cree", "en": "Created"},
    "common.updated": {"fr": "Mis a jour", "en": "Updated"},
    "common.assigned": {"fr": "Assigne", "en": "Assigned"},
    "common.at": {"fr": "a", "en": "at"},
    "common.hours_value": {
      "fr": "Lundi - Samedi, 08:00 - 18:00",
      "en": "Monday - Saturday, 08:00 AM - 06:00 PM"
    },
    "common.unknown": {"fr": "Inconnu", "en": "Unknown"},
    "notifications.title": {"fr": "Notifications", "en": "Notifications"},
    "notifications.empty": {
      "fr": "Aucune notification",
      "en": "No notifications"
    },
    "notifications.empty_unread": {
      "fr": "Aucune notification non lue",
      "en": "No unread notifications"
    },
    "notifications.all_read": {
      "fr": "Toutes vos notifications ont ete lues.",
      "en": "All your notifications are read."
    },
    "notifications.new_hint": {
      "fr": "Les nouvelles alertes apparaitront ici.",
      "en": "New alerts will appear here."
    },
    "notifications.all": {"fr": "Toutes", "en": "All"},
    "notifications.unread": {"fr": "Non lues", "en": "Unread"},
    "notifications.mark_all": {"fr": "Tout marquer lu", "en": "Mark all read"},
    "notifications.clear": {"fr": "Vider", "en": "Clear"},
    "notifications.sync_error": {
      "fr": "Impossible de charger les notifications.",
      "en": "Unable to load notifications."
    },
    "notifications.mark_read_error": {
      "fr": "Echec de mise a jour de la notification.",
      "en": "Failed to update notification."
    },
    "notifications.mark_all_error": {
      "fr": "Echec de mise a jour des notifications.",
      "en": "Failed to update notifications."
    },
    "support.title": {"fr": "Support & Aide", "en": "Support & Help"},
    "support.center_title": {"fr": "Centre d'assistance", "en": "Help center"},
    "support.center_subtitle": {
      "fr": "Accedez rapidement aux reponses frequentes et aux canaux de support.",
      "en": "Quick access to common answers and support channels."
    },
    "support.my_tickets": {"fr": "Mes tickets support", "en": "My support tickets"},
    "support.my_tickets_subtitle": {
      "fr": "Suivi des demandes et reponses en temps reel",
      "en": "Track requests and replies in real time"
    },
    "support.email": {"fr": "Email support", "en": "Support email"},
    "support.email_copied": {
      "fr": "Email support affiche.",
      "en": "Support email displayed."
    },
    "support.hours": {
      "fr": "Heures de disponibilite",
      "en": "Support working hours"
    },
    "support.faq": {"fr": "FAQ rapide", "en": "Quick FAQ"},
    "support.faq.q1": {
      "fr": "Comment suivre ma commande ?",
      "en": "How can I track my order?"
    },
    "support.faq.a1": {
      "fr": "Ouvrez l'onglet Orders puis detail de la commande pour voir les statuts.",
      "en": "Open Orders then order details to view the latest statuses."
    },
    "support.faq.q2": {
      "fr": "Pourquoi un paiement peut etre refuse ?",
      "en": "Why can a payment be rejected?"
    },
    "support.faq.a2": {
      "fr": "Verifiez votre PIN wallet et les limites KYC configurees sur votre compte.",
      "en": "Check your wallet PIN and KYC limits configured on your account."
    },
    "support.faq.q3": {
      "fr": "Comment devenir vendeur verifie ?",
      "en": "How to become a verified seller?"
    },
    "support.faq.a3": {
      "fr": "Dans Profil > Conformite/KYC, soumettez vos documents puis attendez la revue admin.",
      "en": "In Profile > Compliance/KYC, submit your documents and wait for admin review."
    },
    "tickets.title": {"fr": "Tickets support", "en": "Support tickets"},
    "tickets.loading": {
      "fr": "Chargement des tickets...",
      "en": "Loading tickets..."
    },
    "tickets.new": {"fr": "Nouveau ticket", "en": "New ticket"},
    "tickets.created": {"fr": "Ticket cree.", "en": "Ticket created."},
    "tickets.empty": {"fr": "Aucun ticket", "en": "No ticket"},
    "tickets.empty_subtitle": {
      "fr": "Creez un ticket pour contacter le support.",
      "en": "Create a ticket to contact support."
    },
    "tickets.subject": {"fr": "Sujet", "en": "Subject"},
    "tickets.description": {"fr": "Description", "en": "Description"},
    "tickets.category": {"fr": "Categorie", "en": "Category"},
    "tickets.priority": {"fr": "Priorite", "en": "Priority"},
    "tickets.status": {"fr": "Statut", "en": "Status"},
    "tickets.assigned_to": {"fr": "Assigne", "en": "Assigned"},
    "tickets.ticket_label": {"fr": "Ticket", "en": "Ticket"},
    "tickets.filter.all": {"fr": "Tous", "en": "All"},
    "tickets.filter.open": {"fr": "Ouvert", "en": "Open"},
    "tickets.filter.in_progress": {"fr": "En cours", "en": "In progress"},
    "tickets.filter.resolved": {"fr": "Resolu", "en": "Resolved"},
    "tickets.filter.closed": {"fr": "Ferme", "en": "Closed"},
    "tickets.priority.low": {"fr": "Faible", "en": "Low"},
    "tickets.priority.medium": {"fr": "Moyenne", "en": "Medium"},
    "tickets.priority.high": {"fr": "Haute", "en": "High"},
    "tickets.priority.urgent": {"fr": "Urgente", "en": "Urgent"},
    "tickets.status.open": {"fr": "Ouvert", "en": "Open"},
    "tickets.status.in_progress": {"fr": "En cours", "en": "In progress"},
    "tickets.status.resolved": {"fr": "Resolu", "en": "Resolved"},
    "tickets.status.closed": {"fr": "Ferme", "en": "Closed"},
    "tickets.refresh": {"fr": "Rafraichir", "en": "Refresh"},
    "tickets.close": {"fr": "Fermer", "en": "Close"},
    "tickets.closed": {"fr": "Ticket ferme.", "en": "Ticket closed."},
    "tickets.message_label": {"fr": "Votre message", "en": "Your message"},
    "tickets.send": {"fr": "Envoyer", "en": "Send"},
    "tickets.meta_line": {
      "fr": "{ticket} #{id} | {priority} | {category}",
      "en": "{ticket} #{id} | {priority} | {category}"
    },
    "tickets.details.status_priority": {
      "fr": "Statut: {status} | Priorite: {priority}",
      "en": "Status: {status} | Priority: {priority}"
    },
    "tickets.details.category_assigned": {
      "fr": "Categorie: {category} | Assigne: {assigned}",
      "en": "Category: {category} | Assigned: {assigned}"
    },
    "tickets.send_pending": {"fr": "...", "en": "..."},
    "tickets.event.created": {
      "fr": "Ticket #{ticket_id} cree.",
      "en": "Ticket #{ticket_id} created."
    },
    "tickets.event.updated": {
      "fr": "Ticket #{ticket_id} mis a jour.",
      "en": "Ticket #{ticket_id} updated."
    },
    "tickets.event.message": {
      "fr": "Nouveau message sur ticket #{ticket_id}.",
      "en": "New message on ticket #{ticket_id}."
    },
    "tickets.event.closed": {
      "fr": "Ticket #{ticket_id} ferme.",
      "en": "Ticket #{ticket_id} closed."
    },
    "tickets.event.assigned": {
      "fr": "Ticket #{ticket_id} assigne.",
      "en": "Ticket #{ticket_id} assigned."
    },
    "tickets.messages.empty": {"fr": "Aucun message", "en": "No messages"},
    "tickets.messages.empty_subtitle": {
      "fr": "Commencez la discussion avec le support.",
      "en": "Start the conversation with support."
    },
    "public.products.title": {
      "fr": "Produits disponibles",
      "en": "Available products"
    },
    "public.support": {"fr": "Support", "en": "Support"},
    "public.hero.title": {
      "fr": "Marketplace B2B Cameroun",
      "en": "Cameroon B2B Marketplace"
    },
    "public.hero.subtitle": {
      "fr": "Consultez les produits disponibles puis connectez-vous pour commander, publier et gerer vos operations.",
      "en": "Browse available products, then sign in to order, publish and manage your operations."
    },
    "public.hero.login": {"fr": "Se connecter", "en": "Sign in"},
    "public.hero.signup": {"fr": "S'inscrire", "en": "Sign up"},
    "public.products.empty": {
      "fr": "Aucun produit actif",
      "en": "No active products"
    },
    "public.products.loading": {
      "fr": "Chargement du catalogue...",
      "en": "Loading catalog..."
    },
    "public.products.load_error": {
      "fr": "Impossible de charger les produits publics.",
      "en": "Unable to load public products."
    },
    "public.products.empty_subtitle": {
      "fr": "Le catalogue sera visible des qu'un vendeur publie.",
      "en": "The catalog will appear once a seller publishes products."
    },
    "auth.session_expired": {
      "fr": "Session expiree. Veuillez vous reconnecter.",
      "en": "Session expired. Please sign in again."
    },
    "realtime.generic_update": {"fr": "mise a jour", "en": "update"},
  };

  static String tr(
    BuildContext context,
    String key, {
    Map<String, String> params = const {},
  }) {
    final locale = Localizations.localeOf(context).languageCode;
    return trForLocale(locale, key, params: params);
  }

  static String trForLocale(
    String languageCode,
    String key, {
    Map<String, String> params = const {},
  }) {
    final locale = languageCode.toLowerCase();
    var value = _messages[key]?[locale] ?? _messages[key]?["fr"] ?? key;
    for (final entry in params.entries) {
      value = value.replaceAll("{${entry.key}}", entry.value);
    }
    return value;
  }
}

extension AppI18nBuildContext on BuildContext {
  String tr(String key, {Map<String, String> params = const {}}) {
    return AppI18n.tr(this, key, params: params);
  }
}
