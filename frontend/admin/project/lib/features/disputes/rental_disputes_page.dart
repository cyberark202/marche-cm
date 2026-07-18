import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/ui_kit.dart';
import '../data/admin_repository.dart';

class RentalDisputesPage extends StatefulWidget {
  const RentalDisputesPage({super.key});

  @override
  State<RentalDisputesPage> createState() => _RentalDisputesPageState();
}

class _RentalDisputesPageState extends State<RentalDisputesPage> {
  final _api = ApiService();
  final _repo = AdminRepository.instance;
  List<Map<String, dynamic>> _disputes = const [];
  bool _loading = true;
  String? _error;

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
    try {
      final rows = await _api.getList('/api/rental-bookings/');
      if (!mounted) return;
      setState(() {
        _disputes = rows
            .where((b) => '${b['status']}' == 'DISPUTED')
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _repo.errorMessage(e);
        _loading = false;
      });
    }
  }

  Future<void> _resolve(Map<String, dynamic> booking) async {
    final deposit = '${booking['deposit_amount']}';
    final controller = TextEditingController(text: '0');
    final forfeit = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Trancher le litige'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Caution séquestrée : $deposit FCFA.\n\n'
              'Part attribuée au propriétaire (dédommagement). Le reste est '
              'restitué au locataire ; le loyer part au propriétaire net de '
              'commission.',
              style: const TextStyle(
                  fontSize: 13, color: AppPalette.textMuted),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Part propriétaire (FCFA)',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Trancher')),
        ],
      ),
    );
    if (forfeit == null || forfeit.isEmpty) return;
    try {
      await _api.post(
          '/api/rental-bookings/${booking['id']}/resolve-dispute/',
          {'deposit_forfeit': forfeit});
      if (!mounted) return;
      showSnack(context, 'Litige tranché : $forfeit FCFA au propriétaire.');
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, _repo.errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Litiges location')),
      body: _loading
          ? const AppLoadingState(label: 'Chargement des litiges…')
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _disputes.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            SizedBox(height: 60),
                            Center(
                                child: Text('Aucun litige de location en cours',
                                    style: TextStyle(
                                        color: AppPalette.textMuted))),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _disputes.length,
                          itemBuilder: (context, index) {
                            final b = _disputes[index];
                            final events =
                                (b['events'] as List?) ?? const [];
                            final lastNote = events.isEmpty
                                ? ''
                                : '${(events.last as Map)['note'] ?? ''}';
                            return SectionCard(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(LucideIcons.gavel,
                                          size: 18,
                                          color: AppPalette.danger),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                            '${b['listing_title'] ?? 'Location'} — #${b['id']}',
                                            style: const TextStyle(
                                                fontWeight:
                                                    FontWeight.w700)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Du ${b['start_date']} au ${b['end_date']}\n'
                                    'Loyer ${b['rental_amount']} FCFA — '
                                    'caution ${b['deposit_amount']} FCFA'
                                    '${lastNote.isEmpty ? '' : '\n$lastNote'}',
                                    style: const TextStyle(
                                        fontSize: 12.5,
                                        color: AppPalette.textMuted),
                                  ),
                                  const SizedBox(height: 8),
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: () => _resolve(b),
                                      icon: const Icon(LucideIcons.scale,
                                          size: 16),
                                      label: const Text(
                                          'Trancher (répartir la caution)'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
