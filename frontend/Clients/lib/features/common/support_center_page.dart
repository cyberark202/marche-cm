import "package:flutter/material.dart";

import "../../core/app_i18n.dart";
import "support_tickets_page.dart";

class SupportCenterPage extends StatelessWidget {
  const SupportCenterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr("support.title"))),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE5E7EB)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr("support.center_title"),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr("support.center_subtitle"),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: ListTile(
              leading: const Icon(Icons.confirmation_num_outlined),
              title: Text(context.tr("support.my_tickets")),
              subtitle: Text(context.tr("support.my_tickets_subtitle")),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SupportTicketsPage()),
              ),
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.mail_outline),
              title: Text(context.tr("support.email")),
              subtitle: const Text("support@marche-cm.local"),
              trailing: const Icon(Icons.copy),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.tr("support.email_copied"))),
                );
              },
            ),
          ),
          Card(
            child: ListTile(
              leading: const Icon(Icons.schedule_outlined),
              title: Text(context.tr("support.hours")),
              subtitle: Text(context.tr("common.hours_value")),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            context.tr("support.faq"),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          _FaqTile(
            q: context.tr("support.faq.q1"),
            a: context.tr("support.faq.a1"),
          ),
          _FaqTile(
            q: context.tr("support.faq.q2"),
            a: context.tr("support.faq.a2"),
          ),
          _FaqTile(
            q: context.tr("support.faq.q3"),
            a: context.tr("support.faq.a3"),
          ),
        ],
      ),
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.q, required this.a});

  final String q;
  final String a;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ExpansionTile(
        title: Text(q),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(a),
          )
        ],
      ),
    );
  }
}
