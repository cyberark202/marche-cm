import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/api_service.dart';
import '../auth/session_store.dart';

class CustodyEventPage extends StatefulWidget {
  final int shipmentId;
  const CustodyEventPage({super.key, required this.shipmentId});

  @override
  State<CustodyEventPage> createState() => _CustodyEventPageState();
}

class _CustodyEventPageState extends State<CustodyEventPage> {
  final ApiService _api = ApiService();
  final _locationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  String _eventType = 'PICKUP';
  bool _loading = false;

  static const _eventTypes = [
    ('PICKUP', 'Prise en charge', Icons.inventory_2_outlined, Color(0xFF1565C0)),
    ('WAREHOUSE_IN', 'Entree entrepot', Icons.warehouse_outlined, Color(0xFF283593)),
    ('WAREHOUSE_OUT', 'Sortie entrepot', Icons.output_outlined, Color(0xFF6A1B9A)),
    ('HANDOVER', 'Transfert de garde', Icons.swap_horiz_outlined, Color(0xFFE65100)),
    ('OUT_FOR_DELIVERY', 'Depart livraison', Icons.local_shipping_outlined, Color(0xFF00695C)),
    ('DELIVERED', 'Livre', Icons.check_circle_outline, Color(0xFF2E7D32)),
  ];

  @override
  void dispose() {
    _locationCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final location = _locationCtrl.text.trim();
    if (location.isEmpty) {
      _showSnack('Localisation requise', error: true);
      return;
    }
    setState(() => _loading = true);
    final token = context.read<SessionStore>().token;
    try {
      await _api.post(
        '/api/shipments/${widget.shipmentId}/log-custody/',
        {
          'event_type': _eventType,
          'location': location,
          'notes': _notesCtrl.text.trim(),
        },
        token: token,
      );
      if (!mounted) return;
      _showSnack('Evenement enregistre avec succes');
      Navigator.pop(context, true);
    } catch (e) {
      _showSnack(_api.toUserMessage(e), error: true);
    }
    if (mounted) setState(() => _loading = false);
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Evenement — Exp. #${widget.shipmentId}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Type d\'evenement',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (value, label, icon, color) in _eventTypes)
                        _EventTypeCard(
                          value: value,
                          label: label,
                          icon: icon,
                          color: color,
                          selected: _eventType == value,
                          onTap: () => setState(() => _eventType = value),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _locationCtrl,
            decoration: const InputDecoration(
              labelText: 'Localisation *',
              hintText: 'Ex: Entrepot Douala, Port de Kribi…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.location_on_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'Notes (optionnel)',
              hintText: 'Observations, etat de la marchandise…',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.notes_outlined),
            ),
            minLines: 3,
            maxLines: 5,
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Row(
              children: [
                const Icon(Icons.security_outlined, size: 18, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Cet evenement sera signe numeriquement (SHA-256) et ne pourra pas etre '
                    'modifie. Il fera foi en cas de litige.',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed: _loading ? null : _submit,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_loading ? 'Enregistrement...' : 'Enregistrer l\'evenement'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _EventTypeCard extends StatelessWidget {
  final String value, label;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _EventTypeCard({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.14) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? color : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: selected ? color : Colors.grey.shade600),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected ? color : Colors.grey.shade700,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
