import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';

class RentalBookingsPage extends StatefulWidget {
  const RentalBookingsPage({super.key});

  @override
  State<RentalBookingsPage> createState() => _RentalBookingsPageState();
}

class _RentalBookingsPageState extends State<RentalBookingsPage> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _bookings = const [];
  bool _loading = true;
  String? _error;

  static const statusLabels = {
    'REQUESTED': 'Demandée',
    'PAID': 'Payée — à valider',
    'ACCEPTED': 'Acceptée — remise à faire',
    'IN_PROGRESS': 'En cours',
    'RETURNED': 'Restituée — à clôturer',
    'COMPLETED': 'Terminée',
    'REFUSED': 'Refusée',
    'DISPUTED': 'En litige',
    'REFUNDED': 'Remboursée',
    'CANCELLED': 'Annulée',
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final session = context.read<SessionStore>();
    final token = session.token;
    final userId = session.userId;
    try {
      final rows = await _api.getList('/api/rental-bookings/', token: token);
      if (!mounted) return;
      setState(() {
        _bookings = rows
            .where((b) => '${b['owner']}' == '$userId')
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _api.toUserMessage(e,
            fallback: 'Impossible de charger les réservations.');
        _loading = false;
      });
    }
  }

  Future<void> _action(int id, String path, {Map<String, dynamic>? body}) async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post('/api/rental-bookings/$id/$path/', body ?? {},
          token: token);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(_api.toUserMessage(e, fallback: 'Action impossible.'))));
    }
  }

  Future<void> _confirmReturn(int id) async {
    final code = await _askText(
      title: 'Confirmer la restitution',
      hint: 'Code à 4 chiffres reçu en notification',
      keyboard: TextInputType.number,
    );
    if (code == null || code.isEmpty) return;
    await _action(id, 'confirm-return', body: {'otp': code});
  }

  Future<void> _openDispute(int id) async {
    final reason = await _askText(
      title: 'Ouvrir un litige',
      hint: 'Motif (dégradation, perte, retard...)',
    );
    if (reason == null || reason.isEmpty) return;
    await _action(id, 'open-dispute', body: {'reason': reason});
  }

  Future<String?> _askText({
    required String title,
    required String hint,
    TextInputType keyboard = TextInputType.text,
  }) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: keyboard,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Valider')),
        ],
      ),
    );
  }

  List<Widget> _actionsFor(Map<String, dynamic> b) {
    final id = b['id'] as int;
    switch ('${b['status']}') {
      case 'PAID':
        return [
          FilledButton(
              onPressed: () => _action(id, 'accept'),
              child: const Text('Accepter')),
          OutlinedButton(
              onPressed: () => _action(id, 'refuse'),
              child: const Text('Refuser')),
        ];
      case 'ACCEPTED':
        return [
          FilledButton.icon(
            onPressed: () => _action(id, 'issue-handover-otp'),
            icon: const Icon(LucideIcons.keyRound, size: 16),
            label: const Text('Code de remise'),
          ),
        ];
      case 'IN_PROGRESS':
        return [
          FilledButton.icon(
            onPressed: () => _confirmReturn(id),
            icon: const Icon(LucideIcons.packageCheck, size: 16),
            label: const Text('Confirmer restitution'),
          ),
          OutlinedButton(
              onPressed: () => _openDispute(id),
              child: const Text('Litige')),
        ];
      case 'RETURNED':
        return [
          FilledButton.icon(
            onPressed: () => _action(id, 'settle'),
            icon: const Icon(LucideIcons.badgeCheck, size: 16),
            label: const Text('Clôturer (conforme)'),
          ),
          OutlinedButton(
              onPressed: () => _openDispute(id),
              child: const Text('Litige')),
        ];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Réservations reçues')),
      body: _loading
          ? const AppLoadingState(label: 'Chargement...')
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _bookings.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            AppEmptyState(
                              title: 'Aucune réservation',
                              subtitle:
                                  'Les demandes de location de vos biens '
                                  'apparaîtront ici.',
                              icon: LucideIcons.calendarClock,
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _bookings.length,
                          itemBuilder: (context, index) {
                            final b = _bookings[index];
                            final status = '${b['status']}';
                            return Card(
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (b['listing_title'] ?? 'Location')
                                          .toString(),
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w700),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Du ${b['start_date']} au ${b['end_date']}\n'
                                      'Loyer ${b['rental_amount']} FCFA — '
                                      'caution ${b['deposit_amount']} FCFA',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                    const SizedBox(height: 6),
                                    Chip(
                                      label: Text(
                                          statusLabels[status] ?? status,
                                          style:
                                              const TextStyle(fontSize: 12)),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    if (_actionsFor(b).isNotEmpty) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 6,
                                        children: _actionsFor(b),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
