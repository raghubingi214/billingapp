import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../customers/presentation/customer_ledger_screen.dart';
import '../domain/report_csv.dart';
import 'reports_screen.dart';

import 'report_snapshot_export_button.dart';

class CustomerAgingScreen extends ConsumerStatefulWidget {
  const CustomerAgingScreen({super.key, required this.organizationId});
  final String organizationId;

  @override
  ConsumerState<CustomerAgingScreen> createState() => _CustomerAgingState();
}

class _CustomerAgingState extends ConsumerState<CustomerAgingScreen> {
  static const buckets = {
    'current_due': 'Current (including due today)',
    'days_1_30': '1–30 days overdue',
    'days_31_60': '31–60 days overdue',
    'days_61_90': '61–90 days overdue',
    'days_91_plus': '91+ days overdue',
  };

  Map<String, dynamic>? summary;
  final rows = <Map<String, dynamic>>[];
  bool busy = false;
  bool failed = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load({bool refresh = false}) async {
    if (busy) return;
    setState(() {
      busy = true;
      failed = false;
      if (refresh) {
        rows.clear();
        summary = null;
      }
    });
    try {
      final result = await ref
          .read(reportRepositoryProvider)
          .customerAging(widget.organizationId, refresh ? 0 : rows.length);
      if (!mounted) return;
      setState(() {
        summary = result.values;
        rows.addAll(
          (result.values['rows'] as List).cast<Map<String, dynamic>>(),
        );
      });
    } catch (_) {
      if (mounted) setState(() => failed = true);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totals = summary;
    return Scaffold(
      appBar: AppBar(title: const Text('Customer aging')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => load(refresh: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              ReportSnapshotExportButton(
                filenamePrefix: 'customer-aging',
                enabled: totals != null,
                load: (requestId) => ref
                    .read(reportRepositoryProvider)
                    .exportCustomerAging(requestId, widget.organizationId),
                encode: ReportCsv.encodeAging,
              ),
              if (busy) const LinearProgressIndicator(),
              if (totals != null) ...[
                Text(
                  'Outstanding ₹${totals['total']}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text('As of ${totals['as_of']} · ${totals['count']} customers'),
                const SizedBox(height: 8),
                const Text(
                  'Open invoice balances after payments, returns and refunds.',
                ),
                for (final bucket in buckets.entries)
                  ListTile(
                    dense: true,
                    title: Text(bucket.value),
                    subtitle: Text('₹${totals[bucket.key]}'),
                  ),
                if (rows.isEmpty)
                  const Text('No outstanding customer invoices.'),
                for (final row in rows)
                  Card(
                    child: ListTile(
                      title: Text(row['name'] as String),
                      subtitle: Text(
                        [
                          'Outstanding ₹${row['total']}',
                          for (final bucket in buckets.entries)
                            if ((row[bucket.key] as num) > 0)
                              '${bucket.value} · ₹${row[bucket.key]}',
                        ].join('\n'),
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => CustomerLedgerScreen(
                            organizationId: widget.organizationId,
                            customerId: row['customer_id'] as String,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              if (failed)
                TextButton(
                  onPressed: busy ? null : () => load(),
                  child: const Text('Unable to load customer aging. Retry'),
                )
              else if (totals != null && rows.length < (totals['count'] as int))
                TextButton(
                  onPressed: busy ? null : () => load(),
                  child: const Text('Load more customers'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
