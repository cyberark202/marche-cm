import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/api_service.dart';
import '../../core/app_theme.dart';
import '../../core/ui_kit.dart';
import '../data/admin_repository.dart';

class ModerationPage extends StatefulWidget {
  const ModerationPage({super.key});

  @override
  State<ModerationPage> createState() => _ModerationPageState();
}

class _ModerationPageState extends State<ModerationPage> {
  final _api = ApiService();
  final _repo = AdminRepository.instance;
  String _status = 'PUBLISHED';
  List<Map<String, dynamic>> _products = const [];
  bool _loading = true;
  String? _error;

  static const _statuses = {
    'PUBLISHED': 'Publiés',
    'SUSPENDED': 'Suspendus',
    'REJECTED': 'Refusés',
    'DRAFT': 'Brouillons',
    'ARCHIVED': 'Archivés',
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
    try {
      final rows = await _api.getList('/api/products/?status=$_status');
      if (!mounted) return;
      setState(() {
        _products = rows;
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

  Future<void> _moderate(int productId, String action) async {
    String? reason;
    if (action != 'restore') {
      reason = await _askReason(action);
      if (reason == null) return;
    }
    try {
      await _api.post('/api/products/$productId/moderate/', {
        'action': action,
        if (reason != null && reason.isNotEmpty) 'reason': reason,
      });
      if (!mounted) return;
      showSnack(context, 'Décision appliquée.');
      _load();
    } catch (e) {
      if (!mounted) return;
      showSnack(context, _repo.errorMessage(e));
    }
  }

  Future<String?> _askReason(String action) {
    final controller = TextEditingController();
    final label = action == 'suspend' ? 'Suspendre' : 'Refuser';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$label le produit'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          decoration: const InputDecoration(
            labelText: 'Motif (communiqué au vendeur)',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Annuler')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: Text(label)),
        ],
      ),
    );
  }

  List<Widget> _actionsFor(Map<String, dynamic> p) {
    final id = p['id'] as int;
    switch ('${p['status']}') {
      case 'PUBLISHED':
        return [
          OutlinedButton(
              onPressed: () => _moderate(id, 'suspend'),
              child: const Text('Suspendre')),
          OutlinedButton(
              onPressed: () => _moderate(id, 'reject'),
              child: const Text('Refuser')),
        ];
      case 'SUSPENDED':
      case 'REJECTED':
        return [
          FilledButton(
              onPressed: () => _moderate(id, 'restore'),
              child: const Text('Rétablir')),
        ];
      default:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Modération produits')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 8,
                children: _statuses.entries
                    .map((e) => ChoiceChip(
                          label: Text(e.value),
                          selected: _status == e.key,
                          onSelected: (_) {
                            setState(() => _status = e.key);
                            _load();
                          },
                        ))
                    .toList(),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const AppLoadingState(label: 'Chargement des produits…')
                : _error != null
                    ? AppErrorState(message: _error!, onRetry: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: _products.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  SizedBox(height: 60),
                                  Center(
                                      child: Text('Aucun produit dans ce statut',
                                          style: TextStyle(
                                              color: AppPalette.textMuted))),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: _products.length,
                                itemBuilder: (context, index) {
                                  final p = _products[index];
                                  return SectionCard(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Icon(LucideIcons.package,
                                                size: 18,
                                                color: AppPalette.primary),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                  '${p['title']}',
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.w700)),
                                            ),
                                            StatusPill('${p['status']}'),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          'Vendeur #${p['seller']} — '
                                          '${p['unit_price'] ?? p['price_for_min_qty'] ?? '?'} FCFA — '
                                          'type ${p['listing_type'] ?? 'PHYSICAL'}',
                                          style: const TextStyle(
                                              fontSize: 12.5,
                                              color: AppPalette.textMuted),
                                        ),
                                        if (_actionsFor(p).isNotEmpty) ...[
                                          const SizedBox(height: 8),
                                          Wrap(
                                              spacing: 8,
                                              children: _actionsFor(p)),
                                        ],
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
