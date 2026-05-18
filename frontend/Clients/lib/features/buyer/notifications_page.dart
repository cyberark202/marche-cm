import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../../core/app_i18n.dart';
import '../../core/ui_state_widgets.dart';
import '../auth/session_store.dart';
import 'buyer_store.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  final ApiService _api = ApiService();
  bool _showOnlyUnread = false;
  bool _loading = true;
  bool _syncing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRemote();
  }

  Future<void> _loadRemote({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _syncing = true);
    }
    final token = context.read<SessionStore>().token;
    try {
      final rows = await _api.getList("/api/notifications/", token: token);
      if (!mounted) return;
      context.read<BuyerStore>().syncRemoteNotifications(rows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.tr("notifications.sync_error"));
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _syncing = false;
        });
      }
    }
  }

  Future<void> _markAllRead() async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post("/api/notifications/mark_all_read/", {}, token: token);
      if (!mounted) return;
      context.read<BuyerStore>().markAllNotificationsRead();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr("notifications.mark_all_error"))),
      );
    }
  }

  Future<void> _markRead(BuyerNotification item, int absoluteIndex) async {
    if (item.read) return;
    final token = context.read<SessionStore>().token;
    try {
      if (item.remoteId != null) {
        await _api.post(
          "/api/notifications/${item.remoteId}/mark_read/",
          {},
          token: token,
        );
      }
      if (!mounted) return;
      context.read<BuyerStore>().markNotificationRead(absoluteIndex);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr("notifications.mark_read_error"))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<BuyerStore>();
    final notifications = _showOnlyUnread
        ? store.notifications.where((n) => !n.read).toList()
        : store.notifications;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr("notifications.title")),
        actions: [
          IconButton(
            tooltip: context.tr("state.refresh"),
            onPressed: _syncing ? null : () => _loadRemote(silent: true),
            icon: _syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
          if (store.notifications.isNotEmpty)
            IconButton(
              tooltip: context.tr("notifications.mark_all"),
              onPressed: _markAllRead,
              icon: const Icon(Icons.done_all),
            ),
          if (store.notifications.isNotEmpty)
            IconButton(
              tooltip: context.tr("notifications.clear"),
              onPressed: store.clearNotifications,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: _loading
          ? AppLoadingState(label: context.tr("state.loading"))
          : _error != null && store.notifications.isEmpty
              ? AppErrorState(message: _error!, onRetry: () => _loadRemote())
              : RefreshIndicator(
                  onRefresh: () => _loadRemote(silent: true),
                  child: notifications.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            AppEmptyState(
                              title: _showOnlyUnread
                                  ? context.tr("notifications.empty_unread")
                                  : context.tr("notifications.empty"),
                              subtitle: _showOnlyUnread
                                  ? context.tr("notifications.all_read")
                                  : context.tr("notifications.new_hint"),
                              icon: Icons.notifications_none,
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: notifications.length + 1,
                          itemBuilder: (context, index) {
                            if (index == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Wrap(
                                  spacing: 8,
                                  children: [
                                    ChoiceChip(
                                      label: Text(context.tr("notifications.all")),
                                      selected: !_showOnlyUnread,
                                      onSelected: (_) =>
                                          setState(() => _showOnlyUnread = false),
                                    ),
                                    ChoiceChip(
                                      label: Text(
                                        "${context.tr("notifications.unread")} (${store.unreadNotificationsCount})",
                                      ),
                                      selected: _showOnlyUnread,
                                      onSelected: (_) =>
                                          setState(() => _showOnlyUnread = true),
                                    ),
                                  ],
                                ),
                              );
                            }
                            final item = notifications[index - 1];
                            final absoluteIndex = store.notifications.indexOf(item);
                            return Card(
                              child: ListTile(
                                onTap: () => _markRead(item, absoluteIndex),
                                leading: Icon(
                                  item.read
                                      ? Icons.notifications_none
                                      : Icons.notifications_active_outlined,
                                  color: item.read
                                      ? Colors.black45
                                      : Theme.of(context).colorScheme.primary,
                                ),
                                title: Text(
                                  item.message,
                                  style: TextStyle(
                                    fontWeight:
                                        item.read ? FontWeight.w500 : FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  _formatMeta(item),
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: item.read
                                    ? null
                                    : Container(
                                        width: 10,
                                        height: 10,
                                        decoration: BoxDecoration(
                                          color: Theme.of(context).colorScheme.primary,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }

  String _formatMeta(BuyerNotification item) {
    final date = item.createdAt;
    final hh = date.hour.toString().padLeft(2, "0");
    final mm = date.minute.toString().padLeft(2, "0");
    final topic = item.topic.trim().isEmpty ? "" : "[${item.topic}] ";
    return "$topic${date.day}/${date.month}/${date.year} ${context.tr("common.at")} $hh:$mm";
  }
}
