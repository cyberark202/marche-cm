import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/format.dart';
import 'arbitration_page.dart';
import 'dispute_helpers.dart';

/// Litige multi-vue (design `screens-extras.jsx`) — outil d'arbitrage admin.
///
/// L'admin inspecte un litige depuis chaque perspective (acheteur plaignant,
/// vendeur témoin, livreur mis en cause) puis bascule vers la conversation
/// tripartite réelle ([ArbitrationPage]). Les perspectives sont alimentées par
/// les vraies métadonnées du litige ; les preuves par partie restent à brancher
/// sur l'API détaillée.
class DisputeMultiviewPage extends StatelessWidget {
  const DisputeMultiviewPage({
    super.key,
    required this.disputeId,
    required this.dispute,
  });

  final int disputeId;
  final Map<String, dynamic> dispute;

  @override
  Widget build(BuildContext context) {
    final opener = DisputeHelpers.partyName(dispute['opened_by_display']);
    final accused = DisputeHelpers.partyName(dispute['accused_party_display']);
    final amount = DisputeHelpers.amount(dispute);
    final reason = '${dispute['reason'] ?? 'Litige'}';
    final shortId = DisputeHelpers.short(disputeId);

    final perspectives = <_Perspective>[
      _Perspective(
        role: 'Acheteur',
        name: opener,
        sub: 'Plaignant · vue acheteur',
        icon: Icons.shopping_bag_outlined,
        tone: _Tone.info,
        kind: _PerspectiveKind.buyer,
      ),
      _Perspective(
        role: 'Vendeur',
        name: 'Vendeur concerné',
        sub: 'Témoin · vue vendeur',
        icon: Icons.inventory_2_outlined,
        tone: _Tone.success,
        kind: _PerspectiveKind.vendor,
      ),
      _Perspective(
        role: 'Livreur',
        name: accused,
        sub: 'Mis en cause · vue transitaire',
        icon: Icons.local_shipping_outlined,
        tone: _Tone.warn,
        kind: _PerspectiveKind.carrier,
      ),
    ];

    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
        title: Text('Litige #$shortId'),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(18),
          child: Padding(
            padding: EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('Visualiser depuis chaque rôle',
                  style:
                      TextStyle(fontSize: 12, color: AppPalette.textMuted)),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          _frozenEscrowBanner(reason, amount),
          const SizedBox(height: 14),
          const _SectionLabel('3 perspectives + arbitrage'),
          const SizedBox(height: 10),
          for (final p in perspectives)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PerspectiveCard(
                perspective: p,
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _PerspectiveDetailPage(
                    perspective: p,
                    disputeId: disputeId,
                    dispute: dispute,
                  ),
                )),
              ),
            ),
          _PerspectiveCard(
            perspective: const _Perspective(
              role: 'Arbitre',
              name: 'Conversation tripartite',
              sub: 'Chat avec admin · 3 parties',
              icon: Icons.forum_outlined,
              tone: _Tone.coral,
              kind: _PerspectiveKind.arbiter,
            ),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ArbitrationPage(disputeId: disputeId),
            )),
          ),
        ],
      ),
    );
  }

  Widget _frozenEscrowBanner(String reason, num amount) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppPalette.danger, Color(0xFFB91C1C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Text('SÉQUESTRE GELÉ',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4)),
          ),
          const SizedBox(height: 8),
          Text(reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(
            amount > 0
                ? '${Fmt.fcfa(amount)} séquestrés en attente'
                : 'Montant séquestré en attente',
            style: const TextStyle(color: Colors.white70, fontSize: 11.5),
          ),
        ],
      ),
    );
  }
}

enum _Tone { info, success, warn, coral }

enum _PerspectiveKind { buyer, vendor, carrier, arbiter }

class _Perspective {
  const _Perspective({
    required this.role,
    required this.name,
    required this.sub,
    required this.icon,
    required this.tone,
    required this.kind,
  });
  final String role, name, sub;
  final IconData icon;
  final _Tone tone;
  final _PerspectiveKind kind;
}

({Color bg, Color fg}) _toneColors(_Tone tone) {
  switch (tone) {
    case _Tone.info:
      return (bg: AppPalette.infoSoft, fg: AppPalette.info);
    case _Tone.success:
      return (bg: AppPalette.successSoft, fg: AppPalette.success);
    case _Tone.warn:
      return (bg: AppPalette.accentSoft, fg: const Color(0xFF8E5A00));
    case _Tone.coral:
      return (bg: AppPalette.dangerSoft, fg: AppPalette.danger);
  }
}

class _PerspectiveCard extends StatelessWidget {
  const _PerspectiveCard({required this.perspective, required this.onTap});
  final _Perspective perspective;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = _toneColors(perspective.tone);
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppPalette.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppPalette.border),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(perspective.icon, size: 20, color: c.fg),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(perspective.role.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppPalette.textMuted,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4)),
                  const SizedBox(height: 1),
                  Text(perspective.name,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppPalette.text)),
                  const SizedBox(height: 1),
                  Text(perspective.sub,
                      style: const TextStyle(
                          fontSize: 11, color: AppPalette.textMuted)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppPalette.textMuted),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: AppPalette.textMuted,
            letterSpacing: 0.6),
      );
}

// ── Perspective detail (acheteur / vendeur / livreur) ─────────────────────
class _PerspectiveDetailPage extends StatelessWidget {
  const _PerspectiveDetailPage({
    required this.perspective,
    required this.disputeId,
    required this.dispute,
  });
  final _Perspective perspective;
  final int disputeId;
  final Map<String, dynamic> dispute;

  @override
  Widget build(BuildContext context) {
    final shortId = DisputeHelpers.short(disputeId);
    final amount = DisputeHelpers.amount(dispute);
    final c = _toneColors(perspective.tone);
    final (bannerText, claimLabel) = switch (perspective.kind) {
      _PerspectiveKind.buyer => (
          'Le plaignant déclare un préjudice sur la commande. Notre équipe arbitre.',
          'Demande : remboursement / résolution',
        ),
      _PerspectiveKind.vendor => (
          'Le vendeur n\'est pas mis en cause mais son témoignage est utile à l\'arbitrage.',
          'Statut : témoin',
        ),
      _PerspectiveKind.carrier => (
          'Le transitaire est mis en cause. Son paiement est gelé en attendant arbitrage.',
          'Issues possibles : faveur / 50-50 / défaveur',
        ),
      _PerspectiveKind.arbiter => ('', ''),
    };

    return Scaffold(
      backgroundColor: AppPalette.bg,
      appBar: AppBar(
        title: Text('${perspective.role} · vue'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(18),
          child: Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('LIT #$shortId · vue ${perspective.role}',
                  style: const TextStyle(
                      fontSize: 12, color: AppPalette.textMuted)),
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.bg,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(bannerText,
                style: TextStyle(
                    color: c.fg,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    height: 1.5)),
          ),
          const SizedBox(height: 14),
          _infoCard(
            title: 'Partie',
            rows: [
              ('Rôle', perspective.role),
              ('Nom', perspective.name),
              (claimLabel.split(' : ').first, claimLabel.contains(' : ') ? claimLabel.split(' : ').last : '—'),
              if (amount > 0) ('Montant séquestré', Fmt.fcfa(amount)),
            ],
          ),
          const SizedBox(height: 14),
          _evidencePlaceholder(),
          if (perspective.kind == _PerspectiveKind.carrier) ...[
            const SizedBox(height: 14),
            _possibleOutcomes(amount),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => ArbitrationPage(disputeId: disputeId),
              )),
              icon: const Icon(Icons.forum_outlined, size: 18),
              label: const Text('Ouvrir la conversation arbitrage'),
              style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(
      {required String title, required List<(String, String)> rows}) {
    return Container(
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _SectionLabel(title),
            ),
          ),
          for (int i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                border: Border(
                  top: i == 0
                      ? const BorderSide(color: AppPalette.borderSoft)
                      : BorderSide.none,
                  bottom: i < rows.length - 1
                      ? const BorderSide(color: AppPalette.borderSoft)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(rows[i].$1,
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: AppPalette.textMuted,
                          fontWeight: FontWeight.w600)),
                  Flexible(
                    child: Text(rows[i].$2,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                            fontSize: 12.5,
                            color: AppPalette.text,
                            fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _evidencePlaceholder() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.bgSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.borderSoft),
      ),
      child: const Row(
        children: [
          Icon(Icons.photo_library_outlined,
              size: 18, color: AppPalette.textMuted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Preuves jointes par cette partie — disponibles dans le détail du litige et la conversation arbitrage.',
              style: TextStyle(
                  fontSize: 12, color: AppPalette.textMuted, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _possibleOutcomes(num amount) {
    final half = amount > 0 ? amount / 2 : 0;
    final outcomes = [
      ('Décision en faveur du livreur',
          amount > 0 ? '+ ${Fmt.fcfa(amount)} libérés' : 'fonds libérés',
          AppPalette.success),
      ('Partage 50/50',
          half > 0 ? '+ ${Fmt.fcfa(half)} libérés' : 'partage', AppPalette.accent),
      ('Décision en faveur acheteur', '0 F · strike réputation',
          AppPalette.danger),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppPalette.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppPalette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel('Issues possibles'),
          const SizedBox(height: 10),
          for (int i = 0; i < outcomes.length; i++)
            Padding(
              padding: EdgeInsets.only(bottom: i < outcomes.length - 1 ? 6 : 0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppPalette.bgSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: outcomes[i].$3),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(outcomes[i].$1,
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
                    Text(outcomes[i].$2,
                        style: const TextStyle(
                            fontSize: 11, color: AppPalette.textMuted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
