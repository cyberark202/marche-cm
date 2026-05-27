import 'package:flutter/material.dart';

import '../../core/app_theme.dart';

/// Discussion — devis transitaire (PDF 12).
///
/// Page autonome qui rend le design du catalogue : bulles texte
/// (envoyée / reçue), événements système, carte devis transitaire avec actions
/// Accepter / Décliner. Les flux WebSocket réels passent par [ChatHubPage] ;
/// ce widget supporte une utilisation autonome via la liste [messages].
class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    this.peerName = "Tropical Foods SARL",
    this.peerInitials = "TF",
    this.presence = "En ligne · répond en 2 h",
    this.messages = const <ChatItem>[],
  });

  final String peerName;
  final String peerInitials;
  final String presence;
  final List<ChatItem> messages;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final TextEditingController _input = TextEditingController();
  late List<ChatItem> _messages;
  String? _quoteDecision;

  @override
  void initState() {
    super.initState();
    _messages = widget.messages.isEmpty ? _demoConversation() : [...widget.messages];
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  List<ChatItem> _demoConversation() => const [
        ChatDay(label: "Aujourd'hui"),
        ChatBubble(
          fromMe: false,
          text:
              "Bonjour Awa  Votre commande de 200 bidons est confirmée. Je sollicite un devis chez Express Logistics.",
          time: "09:48",
        ),
        ChatBubble(
          fromMe: true,
          text: "Parfait. Délai souhaité : avant le 20 mai.",
          time: "09:51",
          read: true,
        ),
        ChatSystem(
          label: "Express Logistics a soumis un devis",
          icon: Icons.local_shipping_outlined,
        ),
        ChatQuoteCard(
          transitaire: "Express Logistics",
          amount: 85000,
          route: "Douala → Yaoundé",
          etaDays: 5,
          assuranceIncluded: true,
        ),
        ChatBubble(
          fromMe: false,
          text:
              "Le devis est dans votre commande. Validez quand vous voulez et l'enlèvement se fera dès demain matin.",
          time: "10:14",
        ),
        ChatBubble(
          fromMe: true,
          text: "Devis accepté ",
          time: "10:16",
          read: true,
        ),
        ChatSystem(
          label: "Séquestre HELD — 2 320 000 FCFA bloqués",
          icon: Icons.lock_outline,
          tone: ChatSystemTone.success,
        ),
      ];

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(ChatBubble(
        fromMe: true,
        text: text,
        time: TimeOfDay.now().format(context),
        read: false,
      ));
      _input.clear();
    });
  }

  void _onQuote(bool accepted) {
    setState(() {
      _quoteDecision = accepted ? "accepted" : "declined";
      _messages.add(ChatBubble(
        fromMe: true,
        text: accepted ? "Devis accepté " : "Devis décliné.",
        time: TimeOfDay.now().format(context),
        read: false,
      ));
      if (accepted) {
        _messages.add(const ChatSystem(
          label: "Séquestre HELD — fonds bloqués",
          icon: Icons.lock_outline,
          tone: ChatSystemTone.success,
        ));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ChatHeader(
              name: widget.peerName,
              initials: widget.peerInitials,
              presence: widget.presence,
              onBack: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                itemCount: _messages.length,
                itemBuilder: (_, i) {
                  final item = _messages[i];
                  if (item is ChatDay) return _DayDivider(label: item.label);
                  if (item is ChatSystem) return _SystemEvent(item: item);
                  if (item is ChatQuoteCard) {
                    return _QuoteCardWidget(
                      data: item,
                      decision: _quoteDecision,
                      onAccept: () => _onQuote(true),
                      onDecline: () => _onQuote(false),
                    );
                  }
                  if (item is ChatBubble) return _Bubble(item: item);
                  return const SizedBox.shrink();
                },
              ),
            ),
            _Composer(
              controller: _input,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MODELS
// ─────────────────────────────────────────────────────────────────────────────

abstract class ChatItem {
  const ChatItem();
}

class ChatDay extends ChatItem {
  const ChatDay({required this.label});
  final String label;
}

class ChatBubble extends ChatItem {
  const ChatBubble({
    required this.fromMe,
    required this.text,
    this.time,
    this.read = false,
  });
  final bool fromMe;
  final String text;
  final String? time;
  final bool read;
}

enum ChatSystemTone { neutral, success, warning }

class ChatSystem extends ChatItem {
  const ChatSystem({
    required this.label,
    required this.icon,
    this.tone = ChatSystemTone.neutral,
  });
  final String label;
  final IconData icon;
  final ChatSystemTone tone;
}

class ChatQuoteCard extends ChatItem {
  const ChatQuoteCard({
    required this.transitaire,
    required this.amount,
    required this.route,
    required this.etaDays,
    this.assuranceIncluded = false,
  });
  final String transitaire;
  final int amount;
  final String route;
  final int etaDays;
  final bool assuranceIncluded;
}

// ─────────────────────────────────────────────────────────────────────────────
// HEADER
// ─────────────────────────────────────────────────────────────────────────────

class _ChatHeader extends StatelessWidget {
  const _ChatHeader({
    required this.name,
    required this.initials,
    required this.presence,
    required this.onBack,
  });
  final String name;
  final String initials;
  final String presence;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 14),
      decoration: const BoxDecoration(
        gradient: AppPalette.gradientHero,
        borderRadius:
            BorderRadius.vertical(bottom: Radius.circular(AppRadii.xl)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(AppRadii.md),
              border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
            ),
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.2,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: AppPalette.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        presence,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.phone_outlined, color: Colors.white),
          ),
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.more_vert, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DAY DIVIDER
// ─────────────────────────────────────────────────────────────────────────────

class _DayDivider extends StatelessWidget {
  const _DayDivider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppPalette.borderSoft)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppPalette.bgSoft,
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppPalette.textMuted,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppPalette.borderSoft)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SYSTEM EVENT
// ─────────────────────────────────────────────────────────────────────────────

class _SystemEvent extends StatelessWidget {
  const _SystemEvent({required this.item});
  final ChatSystem item;

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    switch (item.tone) {
      case ChatSystemTone.success:
        bg = AppPalette.primarySoft;
        fg = AppPalette.primaryDark;
      case ChatSystemTone.warning:
        bg = AppPalette.warningSoft;
        fg = AppPalette.warning;
      case ChatSystemTone.neutral:
        bg = AppPalette.bgSoft;
        fg = AppPalette.textMuted;
    }
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(item.icon, size: 13, color: fg),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                item.label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: fg,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BUBBLE
// ─────────────────────────────────────────────────────────────────────────────

class _Bubble extends StatelessWidget {
  const _Bubble({required this.item});
  final ChatBubble item;

  @override
  Widget build(BuildContext context) {
    final alignment =
        item.fromMe ? Alignment.centerRight : Alignment.centerLeft;
    final color = item.fromMe ? AppPalette.primary : AppPalette.card;
    final textColor =
        item.fromMe ? Colors.white : AppPalette.text;
    final timeColor =
        item.fromMe ? Colors.white70 : AppPalette.textMuted;
    final radius = item.fromMe
        ? const BorderRadius.only(
            topLeft: Radius.circular(AppRadii.lg),
            topRight: Radius.circular(AppRadii.lg),
            bottomLeft: Radius.circular(AppRadii.lg),
            bottomRight: Radius.circular(6),
          )
        : const BorderRadius.only(
            topLeft: Radius.circular(AppRadii.lg),
            topRight: Radius.circular(AppRadii.lg),
            bottomRight: Radius.circular(AppRadii.lg),
            bottomLeft: Radius.circular(6),
          );

    return Align(
      alignment: alignment,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        decoration: BoxDecoration(
          color: color,
          borderRadius: radius,
          border: item.fromMe
              ? null
              : Border.all(color: AppPalette.borderSoft),
          boxShadow: item.fromMe ? null : AppPalette.shadowSoft,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.text,
              style: TextStyle(
                fontSize: 13.5,
                color: textColor,
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (item.time != null) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.time!,
                    style: TextStyle(
                      fontSize: 10,
                      color: timeColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (item.fromMe) ...[
                    const SizedBox(width: 4),
                    Icon(
                      item.read ? Icons.done_all : Icons.done,
                      size: 12,
                      color: item.read
                          ? AppPalette.accent
                          : Colors.white70,
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QUOTE CARD
// ─────────────────────────────────────────────────────────────────────────────

class _QuoteCardWidget extends StatelessWidget {
  const _QuoteCardWidget({
    required this.data,
    required this.decision,
    required this.onAccept,
    required this.onDecline,
  });

  final ChatQuoteCard data;
  final String? decision;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    final accepted = decision == "accepted";
    final declined = decision == "declined";
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppPalette.card,
          borderRadius: BorderRadius.circular(AppRadii.lg),
          border: Border.all(color: AppPalette.borderSoft),
          boxShadow: AppPalette.shadowMedium,
        ),
        child: Column(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: const BoxDecoration(
                gradient: AppPalette.gradientOcean,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(AppRadii.lg)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.assignment_outlined,
                      color: Colors.white, size: 16),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text(
                      "DEVIS TRANSITAIRE",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                  if (data.assuranceIncluded)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius:
                            BorderRadius.circular(AppRadii.pill),
                      ),
                      child: const Text(
                        "ASSURÉ",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.6,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.transitaire,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppPalette.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        "${data.amount}",
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: AppPalette.primaryDark,
                          letterSpacing: -0.8,
                          height: 1,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text(
                          "FCFA",
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppPalette.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.alt_route,
                          size: 13, color: AppPalette.textMuted),
                      const SizedBox(width: 5),
                      Text(
                        data.route,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppPalette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Icon(Icons.schedule,
                          size: 13, color: AppPalette.textMuted),
                      const SizedBox(width: 5),
                      Text(
                        "ETA ${data.etaDays} jours",
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppPalette.text,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (decision == null)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onDecline,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppPalette.danger,
                              side: const BorderSide(
                                  color: AppPalette.danger, width: 1.2),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                            ),
                            child: const Text("Décliner"),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: onAccept,
                            icon: const Icon(Icons.check, size: 16),
                            label: const Text("Accepter"),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 9),
                      decoration: BoxDecoration(
                        color: accepted
                            ? AppPalette.successSoft
                            : AppPalette.dangerSoft,
                        borderRadius:
                            BorderRadius.circular(AppRadii.md),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            accepted ? Icons.check_circle : Icons.cancel,
                            size: 16,
                            color: accepted
                                ? AppPalette.success
                                : AppPalette.danger,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            accepted
                                ? "Devis accepté — séquestre activé"
                                : declined
                                    ? "Devis décliné"
                                    : "",
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: accepted
                                  ? AppPalette.success
                                  : AppPalette.danger,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// COMPOSER
// ─────────────────────────────────────────────────────────────────────────────

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});
  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        decoration: BoxDecoration(
          color: AppPalette.card,
          border: const Border(
              top: BorderSide(color: AppPalette.borderSoft, width: 1)),
          boxShadow: AppPalette.shadowSoft,
        ),
        child: Row(
          children: [
            IconButton(
              onPressed: () {},
              icon: const Icon(Icons.add_circle_outline,
                  color: AppPalette.textMuted),
            ),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppPalette.bgSoft,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: TextField(
                  controller: controller,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => onSend(),
                  style: const TextStyle(fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: "Écrire un message...",
                    hintStyle: TextStyle(color: AppPalette.textFaint),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(vertical: 12, horizontal: 0),
                    filled: false,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                gradient: AppPalette.gradientPrimary,
                shape: BoxShape.circle,
                boxShadow: AppPalette.shadowSoft,
              ),
              child: IconButton(
                onPressed: onSend,
                icon: const Icon(Icons.send, color: Colors.white, size: 18),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
