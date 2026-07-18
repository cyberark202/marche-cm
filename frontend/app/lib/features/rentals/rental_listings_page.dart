import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';
import 'rental_bookings_page.dart';
import 'rental_listing_edit_page.dart';

/// Mes annonces de location (côté propriétaire, doc 14).
class RentalListingsPage extends StatefulWidget {
  const RentalListingsPage({super.key});

  @override
  State<RentalListingsPage> createState() => _RentalListingsPageState();
}

class _RentalListingsPageState extends State<RentalListingsPage> {
  final ApiService _api = ApiService();
  List<Map<String, dynamic>> _listings = const [];
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
    final session = context.read<SessionStore>();
    final token = session.token;
    final userId = session.userId;
    try {
      final rows = await _api.getList('/api/rental-listings/', token: token);
      if (!mounted) return;
      setState(() {
        // L'endpoint liste aussi les annonces publiées des autres :
        // on ne garde ici que les miennes.
        _listings = rows
            .where((l) => '${l['owner']}' == '$userId')
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _api.toUserMessage(e,
            fallback: 'Impossible de charger vos annonces.');
        _loading = false;
      });
    }
  }

  Future<void> _toggleAvailability(Map<String, dynamic> listing) async {
    final token = context.read<SessionStore>().token;
    final target = !(listing['is_available'] == true);
    try {
      await _api.patch('/api/rental-listings/${listing['id']}/',
          {'is_available': target},
          token: token);
      _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_api.toUserMessage(e,
              fallback: 'Modification impossible.'))));
    }
  }

  Future<void> _openEditor([Map<String, dynamic>? listing]) async {
    final saved = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
          builder: (_) => RentalListingEditPage(listing: listing)),
    );
    if (saved != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes locations'),
        actions: [
          IconButton(
            tooltip: 'Réservations reçues',
            icon: const Icon(LucideIcons.calendarClock),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RentalBookingsPage()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(LucideIcons.plus),
        label: const Text('Louer un bien'),
      ),
      body: _loading
          ? const AppLoadingState(label: 'Chargement...')
          : _error != null
              ? AppErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _listings.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: const [
                            AppEmptyState(
                              title: 'Aucune annonce de location',
                              subtitle:
                                  'Publiez un bien à louer : la caution et le '
                                  'loyer sont sécurisés par séquestre.',
                              icon: LucideIcons.keyRound,
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _listings.length,
                          itemBuilder: (context, index) {
                            final l = _listings[index];
                            final available = l['is_available'] == true;
                            return Card(
                              child: ListTile(
                                leading: Icon(
                                  available
                                      ? LucideIcons.keyRound
                                      : LucideIcons.lock,
                                  color: available
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.black38,
                                ),
                                title: Text((l['title'] ?? '').toString()),
                                subtitle: Text(
                                  '${l['price_per_period']} FCFA / '
                                  '${_periodLabel(l['price_period'])} — '
                                  'caution ${l['deposit_amount']} FCFA\n'
                                  '${l['status']}'
                                  '${available ? '' : ' — indisponible'}',
                                ),
                                isThreeLine: true,
                                onTap: () => _openEditor(l),
                                trailing: Switch(
                                  value: available,
                                  onChanged: (_) => _toggleAvailability(l),
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }

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
}
