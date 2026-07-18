import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/network/api_error.dart';
import '../../../core/network/driver_dio_client.dart';
import '../../../core/realtime_events_service.dart';
import '../../../core/theme/driver_theme.dart';

/// Boîte de réception du livreur : liste des discussions de coordination
/// livraison. Réutilise l'API chat partagée (`/api/chat/rooms/`) et ouvre la
/// conversation plein écran existante (`/chat/:roomId`).
class DriverConversationsPage extends StatefulWidget {
  const DriverConversationsPage({super.key});

  @override
  State<DriverConversationsPage> createState() => _DriverConversationsPageState();
}

class _DriverConversationsPageState extends State<DriverConversationsPage> {
  List<Map<String, dynamic>> _rooms = const [];
  bool _loading = true;
  String? _error;
  StreamSubscription<Map<String, dynamic>>? _eventsSub;

  @override
  void initState() {
    super.initState();
    _load();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      if (RealtimeEventsService.instance.matchesTopic(event, 'chat')) _load();
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await DriverDioClient.dio.get('/api/chat/rooms/');
      final raw = res.data;
      final rows = <Map<String, dynamic>>[
        if (raw is List) ...raw.cast<Map<String, dynamic>>(),
        if (raw is Map && raw['results'] is List)
          ...(raw['results'] as List).cast<Map<String, dynamic>>(),
      ];
      if (!mounted) return;
      setState(() {
        _rooms = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiError.friendly(e);
      });
    }
  }

  String _roomTitle(Map<String, dynamic> room) {
    final name = (room['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return name;
    final peer = room['peer'];
    final peerName =
        peer is Map ? (peer['username'] ?? '').toString().trim() : '';
    return peerName.isNotEmpty ? peerName : 'Discussion #${room['id']}';
  }

  /// Horodatage compact du dernier message (HH:MM aujourd'hui, sinon date).
  String _timeLabel(Map<String, dynamic> room) {
    final last = room['last_message'];
    if (last is! Map) return '';
    final date =
        DateTime.tryParse((last['created_at'] ?? '').toString())?.toLocal();
    if (date == null) return '';
    final now = DateTime.now();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(date.year, date.month, date.day))
        .inDays;
    if (diff == 0) {
      return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    if (diff == 1) return 'Hier';
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
  }

  void _open(Map<String, dynamic> room) {
    final id = room['id'];
    if (id is! int) return;
    context.go('/chat/$id?title=${Uri.encodeComponent(_roomTitle(room))}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: T.bg,
      appBar: AppBar(
        backgroundColor: DriverPalette.primary,
        foregroundColor: Colors.white,
        title: const Text('Messages',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _rooms.isEmpty) {
      return _CenteredMessage(
        icon: LucideIcons.alertCircle,
        message: _error!,
        actionLabel: 'Réessayer',
        onAction: _load,
      );
    }
    if (_rooms.isEmpty) {
      return const _CenteredMessage(
        icon: LucideIcons.messageCircle,
        message:
            "Aucune discussion pour le moment.\nElles apparaissent quand vous coordonnez une livraison.",
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _rooms.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, indent: 72, color: T.line2),
      itemBuilder: (context, i) {
        final room = _rooms[i];
        final peer = room['peer'];
        final online = peer is Map && peer['is_online'] == true;
        final unread = (room['unread_count'] ?? 0) as int;
        final last = room['last_message'];
        final snippet =
            last is Map ? (last['snippet'] ?? '').toString() : '';
        final time = _timeLabel(room);
        return ListTile(
          onTap: () => _open(room),
          leading: Stack(
            clipBehavior: Clip.none,
            children: [
              const CircleAvatar(
                backgroundColor: T.primarySoft,
                child:
                    Icon(LucideIcons.messageCircle, color: T.primary, size: 20),
              ),
              if (online)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          title: Row(
            children: [
              Expanded(
                child: Text(_roomTitle(room),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight:
                            unread > 0 ? FontWeight.w800 : FontWeight.w700,
                        fontSize: 14.5)),
              ),
              if (time.isNotEmpty)
                Text(time,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight:
                            unread > 0 ? FontWeight.w700 : FontWeight.w400,
                        color: unread > 0 ? T.primary : T.ink3)),
            ],
          ),
          subtitle: snippet.isEmpty
              ? null
              : Text(snippet,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 12.5,
                      color: unread > 0 ? Colors.black87 : T.ink3)),
          trailing: unread > 0
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: const BoxDecoration(
                    color: DriverPalette.primary,
                    borderRadius: BorderRadius.all(Radius.circular(999)),
                  ),
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700),
                  ),
                )
              : const Icon(LucideIcons.chevronRight, size: 18, color: T.ink3),
        );
      },
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: DriverPalette.textMuted),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: DriverPalette.textSecondary)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 16),
              FilledButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
