import "dart:async";

import "package:flutter/material.dart";
import "package:provider/provider.dart";

import "../../core/api_service.dart";
import "../../core/app_i18n.dart";
import "../../core/realtime_events_service.dart";
import "../../core/ui_state_widgets.dart";
import "../auth/session_store.dart";

class SupportTicketsPage extends StatefulWidget {
  const SupportTicketsPage({super.key});

  @override
  State<SupportTicketsPage> createState() => _SupportTicketsPageState();
}

class _SupportTicketsPageState extends State<SupportTicketsPage> {
  final ApiService _api = ApiService();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _tickets = const [];
  String _statusFilter = "ALL";

  @override
  void initState() {
    super.initState();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      final topic = (event["topic"] ?? "").toString();
      if (topic == "support") {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = context.read<SessionStore>().token;
    try {
      final rows = await _api.getList("/api/support/tickets/", token: token);
      if (!mounted) return;
      setState(() {
        _tickets = rows;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst("Exception: ", "");
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  List<Map<String, dynamic>> _filteredTickets() {
    if (_statusFilter == "ALL") return _tickets;
    return _tickets
        .where((row) => (row["status"] ?? "").toString().toUpperCase() == _statusFilter)
        .toList();
  }

  Future<void> _openCreateTicketDialog() async {
    final subject = TextEditingController();
    final description = TextEditingController();
    final category = TextEditingController(text: "GENERAL");
    String priority = "MEDIUM";

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr("tickets.new")),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: subject,
                decoration: InputDecoration(labelText: context.tr("tickets.subject")),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: description,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(labelText: context.tr("tickets.description")),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: category,
                decoration: InputDecoration(labelText: context.tr("tickets.category")),
              ),
              const SizedBox(height: 8),
              StatefulBuilder(
                builder: (context, setInnerState) => DropdownButtonFormField<String>(
                  initialValue: priority,
                  decoration: InputDecoration(labelText: context.tr("tickets.priority")),
                  items: [
                    DropdownMenuItem(value: "LOW", child: Text(context.tr("tickets.priority.low"))),
                    DropdownMenuItem(
                      value: "MEDIUM",
                      child: Text(context.tr("tickets.priority.medium")),
                    ),
                    DropdownMenuItem(value: "HIGH", child: Text(context.tr("tickets.priority.high"))),
                    DropdownMenuItem(
                      value: "URGENT",
                      child: Text(context.tr("tickets.priority.urgent")),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setInnerState(() => priority = value);
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.tr("common.cancel")),
          ),
          FilledButton(
            onPressed: () async {
              final token = context.read<SessionStore>().token;
              try {
                await _api.post(
                  "/api/support/tickets/",
                  {
                    "subject": subject.text.trim(),
                    "description": description.text.trim(),
                    "category": category.text.trim().isEmpty ? "GENERAL" : category.text.trim(),
                    "priority": priority,
                  },
                  token: token,
                );
                if (!context.mounted) return;
                Navigator.of(context).pop(true);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
                );
              }
            },
            child: Text(context.tr("tickets.new")),
          ),
        ],
      ),
    );

    if (created == true) {
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr("tickets.created"))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredTickets();
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr("tickets.title")),
        actions: [
          IconButton(
            tooltip: context.tr("tickets.new"),
            onPressed: _openCreateTicketDialog,
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: context.tr("tickets.refresh"),
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? AppLoadingState(label: context.tr("tickets.loading"))
          : _error != null
              ? AppErrorState(message: _error!, onRetry: () => _load())
              : Column(
                  children: [
                    SizedBox(
                      height: 54,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        scrollDirection: Axis.horizontal,
                        children: [
                          _filterChip("ALL"),
                          _filterChip("OPEN"),
                          _filterChip("IN_PROGRESS"),
                          _filterChip("RESOLVED"),
                          _filterChip("CLOSED"),
                        ],
                      ),
                    ),
                    Expanded(
                      child: rows.isEmpty
                          ? AppEmptyState(
                              title: context.tr("tickets.empty"),
                              subtitle: context.tr("tickets.empty_subtitle"),
                              onRetry: () => _openCreateTicketDialog(),
                              retryLabel: context.tr("tickets.new"),
                              icon: Icons.support_agent,
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: rows.length,
                              itemBuilder: (context, index) {
                                final ticket = rows[index];
                                final ticketId = (ticket["id"] ?? 0).toString();
                                final status = (ticket["status"] ?? "").toString().toUpperCase();
                                final priority = (ticket["priority"] ?? "").toString().toUpperCase();
                                return Card(
                                  child: ListTile(
                                    onTap: () async {
                                      await Navigator.of(context).push(
                                        MaterialPageRoute(
                                          builder: (_) => SupportTicketDetailPage(
                                            ticketId: int.tryParse(ticketId) ?? 0,
                                          ),
                                        ),
                                      );
                                      if (!mounted) return;
                                      _load();
                                    },
                                    title: Text((ticket["subject"] ?? "").toString()),
                                    subtitle: Text(
                                      context.tr(
                                        "tickets.meta_line",
                                        params: {
                                          "ticket": context.tr("tickets.ticket_label"),
                                          "id": ticketId,
                                          "priority": _priorityLabel(priority),
                                          "category": (ticket["category"] ?? "GENERAL").toString(),
                                        },
                                      ),
                                    ),
                                    trailing: _statusChip(status),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openCreateTicketDialog,
        icon: const Icon(Icons.add),
        label: Text(context.tr("tickets.new")),
      ),
    );
  }

  Widget _filterChip(String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(_filterLabel(value)),
        selected: _statusFilter == value,
        onSelected: (_) => setState(() => _statusFilter = value),
      ),
    );
  }

  Widget _statusChip(String status) {
    Color color;
    switch (status) {
      case "OPEN":
        color = const Color(0xFFB45309);
        break;
      case "IN_PROGRESS":
        color = const Color(0xFF1D4ED8);
        break;
      case "RESOLVED":
        color = const Color(0xFF166534);
        break;
      case "CLOSED":
        color = const Color(0xFF374151);
        break;
      default:
        color = Colors.black54;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
      ),
    );
  }

  String _filterLabel(String raw) {
    switch (raw) {
      case "OPEN":
        return context.tr("tickets.filter.open");
      case "IN_PROGRESS":
        return context.tr("tickets.filter.in_progress");
      case "RESOLVED":
        return context.tr("tickets.filter.resolved");
      case "CLOSED":
        return context.tr("tickets.filter.closed");
      default:
        return context.tr("tickets.filter.all");
    }
  }

  String _statusLabel(String raw) {
    switch (raw.toUpperCase()) {
      case "OPEN":
        return context.tr("tickets.status.open");
      case "IN_PROGRESS":
        return context.tr("tickets.status.in_progress");
      case "RESOLVED":
        return context.tr("tickets.status.resolved");
      case "CLOSED":
        return context.tr("tickets.status.closed");
      default:
        return raw;
    }
  }

  String _priorityLabel(String raw) {
    switch (raw.toUpperCase()) {
      case "LOW":
        return context.tr("tickets.priority.low");
      case "MEDIUM":
        return context.tr("tickets.priority.medium");
      case "HIGH":
        return context.tr("tickets.priority.high");
      case "URGENT":
        return context.tr("tickets.priority.urgent");
      default:
        return raw;
    }
  }
}

class SupportTicketDetailPage extends StatefulWidget {
  const SupportTicketDetailPage({super.key, required this.ticketId});

  final int ticketId;

  @override
  State<SupportTicketDetailPage> createState() => _SupportTicketDetailPageState();
}

class _SupportTicketDetailPageState extends State<SupportTicketDetailPage> {
  final ApiService _api = ApiService();
  final TextEditingController _messageCtrl = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _eventsSub;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _ticket;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _eventsSub = RealtimeEventsService.instance.events.listen((event) {
      if (!mounted) return;
      final topic = (event["topic"] ?? "").toString();
      if (topic != "support") {
        return;
      }
      final payload = event["payload"] is Map<String, dynamic>
          ? event["payload"] as Map<String, dynamic>
          : const <String, dynamic>{};
      final ticketId = _asInt(payload["ticket_id"]);
      if (ticketId == widget.ticketId) {
        _load();
      }
    });
    _load();
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final token = context.read<SessionStore>().token;
    try {
      final obj = await _api.getObject("/api/support/tickets/${widget.ticketId}/", token: token);
      if (!mounted) return;
      setState(() => _ticket = obj);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst("Exception: ", ""));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendMessage() async {
    final message = _messageCtrl.text.trim();
    if (message.length < 2 || _sending) return;
    setState(() => _sending = true);
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
        "/api/support/tickets/${widget.ticketId}/add_message/",
        {"body": message, "is_internal": false},
        token: token,
      );
      _messageCtrl.clear();
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _closeTicket() async {
    final token = context.read<SessionStore>().token;
    try {
      await _api.post("/api/support/tickets/${widget.ticketId}/close/", {}, token: token);
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr("tickets.closed"))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst("Exception: ", ""))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ticket = _ticket;
    final status = (ticket?["status"] ?? "").toString().toUpperCase();
    final messages = (ticket?["messages"] is List) ? (ticket!["messages"] as List) : const [];

    return Scaffold(
      appBar: AppBar(
        title: Text("${context.tr("tickets.ticket_label")} #${widget.ticketId}"),
        actions: [
          if (status != "CLOSED")
            IconButton(
              tooltip: context.tr("tickets.close"),
              onPressed: _closeTicket,
              icon: const Icon(Icons.task_alt_outlined),
            ),
        ],
      ),
      body: _loading
          ? AppLoadingState(label: context.tr("state.loading"))
          : _error != null
              ? AppErrorState(message: _error!, onRetry: () => _load())
              : Column(
                  children: [
                    if (ticket != null)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E7EB)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (ticket["subject"] ?? "").toString(),
                              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.tr(
                                "tickets.details.status_priority",
                                params: {
                                  "status": _statusLabel((ticket["status"] ?? "").toString()),
                                  "priority": _priorityLabel((ticket["priority"] ?? "").toString()),
                                },
                              ),
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              context.tr(
                                "tickets.details.category_assigned",
                                params: {
                                  "category": (ticket["category"] ?? "GENERAL").toString(),
                                  "assigned": (ticket["assigned_to_username"] ?? "")
                                          .toString()
                                          .trim()
                                          .isEmpty
                                      ? context.tr("common.unknown")
                                      : (ticket["assigned_to_username"] ?? "").toString(),
                                },
                              ),
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: messages.isEmpty
                          ? AppEmptyState(
                              title: context.tr("tickets.messages.empty"),
                              subtitle: context.tr("tickets.messages.empty_subtitle"),
                              icon: Icons.chat_bubble_outline,
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final row = messages[index] as Map<String, dynamic>;
                                return Card(
                                  child: ListTile(
                                    leading: const Icon(Icons.message_outlined),
                                    title: Text((row["body"] ?? "").toString()),
                                    subtitle: Text(
                                      "${row["author_username"] ?? "-"} • ${row["author_role"] ?? "-"}",
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    if (status != "CLOSED")
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                        decoration: const BoxDecoration(color: Colors.white),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _messageCtrl,
                                minLines: 1,
                                maxLines: 3,
                                decoration: InputDecoration(
                                  labelText: context.tr("tickets.message_label"),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _sending ? null : _sendMessage,
                              child: Text(
                                _sending
                                    ? context.tr("tickets.send_pending")
                                    : context.tr("tickets.send"),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
    );
  }

  String _statusLabel(String raw) {
    switch (raw.toUpperCase()) {
      case "OPEN":
        return context.tr("tickets.status.open");
      case "IN_PROGRESS":
        return context.tr("tickets.status.in_progress");
      case "RESOLVED":
        return context.tr("tickets.status.resolved");
      case "CLOSED":
        return context.tr("tickets.status.closed");
      default:
        return raw;
    }
  }

  String _priorityLabel(String raw) {
    switch (raw.toUpperCase()) {
      case "LOW":
        return context.tr("tickets.priority.low");
      case "MEDIUM":
        return context.tr("tickets.priority.medium");
      case "HIGH":
        return context.tr("tickets.priority.high");
      case "URGENT":
        return context.tr("tickets.priority.urgent");
      default:
        return raw;
    }
  }

  int? _asInt(dynamic raw) {
    if (raw is int) return raw;
    return int.tryParse((raw ?? "").toString());
  }
}
