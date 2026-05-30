import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ui_kit.dart';
import '../data/admin_repository.dart';

/// Screen 41 — Platform configuration (commissions & security). Read-only:
/// values come from the backend ui-config when present, otherwise the
/// documented platform defaults. Mutation is intentionally not exposed here.
class ConfigurationPage extends StatefulWidget {
  const ConfigurationPage({super.key});

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  final _repo = AdminRepository.instance;
  late Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = _safeConfig();
  }

  Future<Map<String, dynamic>> _safeConfig() async {
    try {
      return await _repo.uiConfig();
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  String _val(Map<String, dynamic> cfg, List<String> path, String fallback) {
    dynamic node = cfg;
    for (final key in path) {
      if (node is Map && node.containsKey(key)) {
        node = node[key];
      } else {
        return fallback;
      }
    }
    if (node == null) return fallback;
    return '$node';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuration')),
      body: FutureBuilder<Map<String, dynamic>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const AppLoadingState();
          }
          final cfg = snap.data ?? const {};
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              const Text('Plateforme · sécurité',
                  style: TextStyle(color: AppPalette.textMuted)),
              const SizedBox(height: 14),
              const SectionLabel('Commissions'),
              SectionCard(
                child: Column(
                  children: [
                    _row('Commission plateforme',
                        _val(cfg, ['commissions', 'platform'], '3 %'),
                        sub: 'Sur chaque commande'),
                    const Divider(height: 18),
                    _row('Part transitaire',
                        _val(cfg, ['commissions', 'transit'], '5 %'),
                        sub: 'Du séquestre'),
                    const Divider(height: 18),
                    _row('Part vendeur',
                        _val(cfg, ['commissions', 'seller'], '92 %'),
                        sub: 'À la libération'),
                    const Divider(height: 18),
                    _row('Frais NotchPay',
                        _val(cfg, ['commissions', 'notchpay'],
                            '1 % paiement · 0,5 % retrait')),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SectionLabel('Sécurité & escrow'),
              SectionCard(
                child: Column(
                  children: [
                    _row('Délai max séquestre',
                        _val(cfg, ['escrow', 'max_days'], '14 jours'),
                        sub: 'Puis arbitrage auto'),
                    const Divider(height: 18),
                    _toggleRow('PIN wallet obligatoire', true,
                        sub: 'Pour tous les retraits'),
                    const Divider(height: 18),
                    _toggleRow('2FA e-mail', true,
                        sub: 'Actions sensibles (réconciliation, retraits)'),
                    const Divider(height: 18),
                    _row('Chiffrement PII at-rest', 'AES-256',
                        sub: 'Rotation de clé 90 j'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const SectionLabel('Notifications & alertes'),
              SectionCard(
                child: Column(
                  children: [
                    _toggleRow('Webhooks NotchPay', true,
                        sub: 'Endpoint actif'),
                    const Divider(height: 18),
                    _toggleRow('Alertes FinOps', true,
                        sub: 'Écarts de réconciliation'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppPalette.infoSoft,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 18, color: AppPalette.info),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Lecture seule. La modification des commissions et des '
                        'paramètres de sécurité se fait côté backend (variables '
                        'd\'environnement / migration auditée).',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _row(String label, String value, {String? sub}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (sub != null)
                Text(sub,
                    style: const TextStyle(
                        fontSize: 12, color: AppPalette.textMuted)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: AppPalette.primary)),
      ],
    );
  }

  Widget _toggleRow(String label, bool on, {String? sub}) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              if (sub != null)
                Text(sub,
                    style: const TextStyle(
                        fontSize: 12, color: AppPalette.textMuted)),
            ],
          ),
        ),
        StatusPill(on ? 'ACTIF' : 'INACTIF',
            color: on ? AppPalette.success : AppPalette.textMuted),
      ],
    );
  }
}
