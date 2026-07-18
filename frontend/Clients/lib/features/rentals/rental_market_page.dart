import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';
import 'my_rentals_page.dart';

/// Marché de la location (doc 14) : biens à louer publiés par les vendeurs.
///
/// La réservation séquestre loyer + caution ; la caution est restituée au
/// retour conforme du bien.
class RentalMarketPage extends StatefulWidget {
  const RentalMarketPage({super.key});

  @override
  State<RentalMarketPage> createState() => _RentalMarketPageState();
}

class _RentalMarketPageState extends State<RentalMarketPage> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _listings = const [];
  bool _loading = true;
  String? _error;
  String _query = '';

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
      final rows = await _api.getList('/api/rental-listings/', token: token);
      if (!mounted) return;
      setState(() {
        _listings = rows
            .where((l) =>
                l['is_available'] == true && '${l['owner']}' != '$userId')
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _api.toUserMessage(e,
            fallback: 'Impossible de charger les locations.');
        _loading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.trim().isEmpty) return _listings;
    final q = _query.trim().toLowerCase();
    return _listings
        .where((l) =>
            '${l['title']}'.toLowerCase().contains(q) ||
            '${l['category']}'.toLowerCase().contains(q) ||
            '${l['city']}'.toLowerCase().contains(q))
        .toList(growable: false);
  }

  Future<void> _book(Map<String, dynamic> listing) async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'Période de location',
    );
    if (range == null || !mounted) return;
    final token = context.read<SessionStore>().token;
    try {
      final booking = await _api.post('/api/rental-bookings/', {
        'listing': listing['id'],
        'start_date': _isoDate(range.start),
        'end_date': _isoDate(range.end),
      }, token: token);
      if (!mounted) return;
      final payNow = await _confirmPayment(booking);
      if (payNow == true) {
        await _api.post(
            '/api/rental-bookings/${booking['id']}/pay/', {},
            token: token);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Fonds séquestrés. Le propriétaire doit maintenant accepter.')));
      }
      if (!mounted) return;
      Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const MyRentalsPage()));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              _api.toUserMessage(e, fallback: 'Réservation impossible.'))));
    }
  }

  Future<bool?> _confirmPayment(Map<String, dynamic> booking) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Payer la location ?'),
        content: Text(
          'Loyer : ${booking['rental_amount']} FCFA\n'
          'Caution : ${booking['deposit_amount']} FCFA\n\n'
          'Le total est bloqué sur votre wallet (séquestre). La caution vous '
          'est restituée au retour conforme du bien.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Plus tard')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Payer maintenant')),
        ],
      ),
    );
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _periodLabel(dynamic period) {
    switch ('$period') {
      case 'HOUR':
        return 'heure';
      case 'WEEK':
        return 'semaine';
      case 'MONTH':
        return 'mois';
      default:
        return 'jour';
    }
  }

  @override
  Widget build(BuildContext context) {
    final listings = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Louer un bien'),
        actions: [
          IconButton(
            tooltip: 'Mes locations',
            icon: const Icon(LucideIcons.calendarClock),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const MyRentalsPage())),
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingState(label: 'Chargement...')
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                        child: TextField(
                          decoration: const InputDecoration(
                            prefixIcon: Icon(LucideIcons.search),
                            hintText: 'Rechercher un bien, une ville...',
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      Expanded(
                        child: listings.isEmpty
                            ? ListView(
                                physics:
                                    const AlwaysScrollableScrollPhysics(),
                                children: const [
                                  AppEmptyState(
                                    title: 'Aucun bien à louer',
                                    subtitle:
                                        'Les annonces de location apparaîtront ici.',
                                    icon: LucideIcons.keyRound,
                                  ),
                                ],
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.all(12),
                                itemCount: listings.length,
                                itemBuilder: (context, index) {
                                  final l = listings[index];
                                  return Card(
                                    child: ListTile(
                                      leading: const Icon(
                                          LucideIcons.keyRound),
                                      title: Text(
                                          (l['title'] ?? '').toString()),
                                      subtitle: Text(
                                        '${l['price_per_period']} FCFA / '
                                        '${_periodLabel(l['price_period'])}'
                                        ' — caution ${l['deposit_amount']} FCFA'
                                        '${'${l['city']}'.isEmpty ? '' : '\n${l['city']}'}',
                                      ),
                                      isThreeLine:
                                          '${l['city']}'.isNotEmpty,
                                      trailing: FilledButton(
                                        onPressed: () => _book(l),
                                        child: const Text('Réserver'),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
