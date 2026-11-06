import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/ledger_repository.dart';
import '../data/supabase_ledger_repository.dart';
import '../../reminders/presentation/reminder_history_screen.dart';

final ledgerRepositoryProvider = Provider<LedgerRepository>(
  (ref) => SupabaseLedgerRepository(ref.watch(supabaseClientProvider)),
);

class CustomerLedgerScreen extends ConsumerStatefulWidget {
  const CustomerLedgerScreen({
    super.key,
    required this.organizationId,
    required this.customerId,
  });
  final String organizationId, customerId;
  @override
  ConsumerState<CustomerLedgerScreen> createState() =>
      _CustomerLedgerScreenState();
}

class _CustomerLedgerScreenState extends ConsumerState<CustomerLedgerScreen> {
  final from = TextEditingController(), to = TextEditingController();
  Map<String, dynamic>? summary;
  List<dynamic> entries = [];
  String? error;
  bool busy = false, more = true;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    from.text = DateTime(
      now.year,
      now.month,
      1,
    ).toIso8601String().substring(0, 10);
    to.text = now.toIso8601String().substring(0, 10);
    load(reset: true);
  }

  @override
  void dispose() {
    from.dispose();
    to.dispose();
    super.dispose();
  }

  Future<void> load({bool reset = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (reset) entries = [];
      final page = await ref
          .read(ledgerRepositoryProvider)
          .page(
            widget.organizationId,
            widget.customerId,
            from.text,
            to.text,
            entries.length,
          );
      if (mounted) {
        setState(() {
          summary = page.values;
          final rows = page.values['entries'] as List;
          entries = [...entries, ...rows];
          more = rows.length == 50;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to load statement. Check dates and access.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Customer ledger'),
      actions: [
        IconButton(
          tooltip: 'Reminder history',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReminderHistoryScreen(
                organizationId: widget.organizationId,
                customerId: widget.customerId,
              ),
            ),
          ),
        ),
      ],
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final field in [(from, 'From'), (to, 'To')])
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: field.$1,
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: '${field.$2} (YYYY-MM-DD)',
                ),
              ),
            ),
          FilledButton(
            onPressed: busy ? null : () => load(reset: true),
            child: const Text('Apply dates'),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (summary != null) ...[
            Text(
              summary!['customer_name'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Opening ₹${summary!['opening_balance']} · Closing ₹${summary!['closing_balance']}',
            ),
            const Text(
              'Receipts include unapplied advances. Positive balance is receivable.',
            ),
          ],
          for (final entry in entries)
            Card(
              child: ListTile(
                title: Text('${entry['type']} · ${entry['reference']}'),
                subtitle: Text(
                  '${entry['date']}\nDebit ₹${entry['debit']} · Credit ₹${entry['credit']}',
                ),
                trailing: Text('₹${entry['balance']}'),
              ),
            ),
          if (more && !busy)
            TextButton(onPressed: () => load(), child: const Text('Load more')),
        ],
      ),
    ),
  );
}
