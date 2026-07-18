import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/driver_dio_client.dart';
import 'package:lucide_icons/lucide_icons.dart';

final _prefsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res =
      await DriverDioClient.dio.get('/api/notifications/preferences/');
  final data = res.data;
  if (data is Map<String, dynamic>) return data;
  return const {};
});

class NotificationPreferencesPage extends ConsumerStatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  ConsumerState<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends ConsumerState<NotificationPreferencesPage> {
  bool _saving = false;

  Future<void> _save(Map<String, dynamic> current,
      {bool? promotions, bool? push}) async {
    setState(() => _saving = true);
    try {
      await DriverDioClient.dio.patch('/api/notifications/preferences/', data: {
        'promotions_enabled':
            promotions ?? current['promotions_enabled'] != false,
        'push_enabled': push ?? current['push_enabled'] != false,
      });
      ref.invalidate(_prefsProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiError.friendly(e))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final prefs = ref.watch(_prefsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Préférences de notifications')),
      body: prefs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ApiError.friendly(e)),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => ref.invalidate(_prefsProvider),
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
        data: (current) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SwitchListTile(
              value: current['push_enabled'] != false,
              onChanged:
                  _saving ? null : (v) => _save(current, push: v),
              secondary: const Icon(LucideIcons.bellRing),
              title: const Text('Notifications push'),
              subtitle: const Text(
                  'Alertes sur cet appareil quand l\'application est fermée'),
            ),
            SwitchListTile(
              value: current['promotions_enabled'] != false,
              onChanged:
                  _saving ? null : (v) => _save(current, promotions: v),
              secondary: const Icon(LucideIcons.megaphone),
              title: const Text('Promotions'),
              subtitle:
                  const Text('Offres et annonces commerciales'),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Les alertes de sécurité et les notifications critiques '
                '(nouvelle course, litige) ne peuvent pas être désactivées.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
