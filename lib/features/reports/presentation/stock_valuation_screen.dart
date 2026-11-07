import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/report_csv.dart';
import 'report_snapshot_export_button.dart';
import 'reports_screen.dart';

class StockValuationScreen extends ConsumerStatefulWidget {
  const StockValuationScreen({super.key, required this.organizationId});
  final String organizationId;

  @override
  ConsumerState<StockValuationScreen> createState() => _StockValuationState();
}

class _StockValuationState extends ConsumerState<StockValuationScreen> {
  final rows = <Map<String, dynamic>>[];
  Map<String, dynamic>? summary;
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
      final report = await ref
          .read(reportRepositoryProvider)
          .stockValuation(widget.organizationId, rows.length);
      if (!mounted) return;
      final page = (report.values['rows'] as List).cast<Map<String, dynamic>>();
      setState(() {
        summary = report.values;
        rows.addAll(page);
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
      appBar: AppBar(title: const Text('Stock valuation')),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => load(refresh: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              ReportSnapshotExportButton(
                filenamePrefix: 'stock-valuation',
                enabled: totals != null,
                load: (requestId) => ref
                    .read(reportRepositoryProvider)
                    .exportStockValuation(requestId, widget.organizationId),
                encode: ReportCsv.encodeStockValuation,
              ),
              if (busy) const LinearProgressIndicator(),
              if (totals != null) ...[
                Text(
                  'Estimated stock value ₹${totals['total']}',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  '${totals['count']} stocked positions · ${totals['low_stock_count']} low',
                ),
                Text(
                  '${totals['uncosted_count']} positions without a positive recorded cost',
                ),
                const SizedBox(height: 8),
                const Text(
                  'Uses the recorded average purchase cost. Opening stock, adjustments '
                  'and returns can affect the estimate. Positions without a positive cost '
                  'are excluded from the value.',
                ),
                if (rows.isEmpty)
                  const ListTile(title: Text('No stock on hand.')),
                for (final row in rows)
                  Card(
                    child: ListTile(
                      title: Text(row['name'] as String),
                      subtitle: Text(
                        [
                          '${row['outlet']} · ${row['quantity']} ${row['unit']} on hand',
                          if (row['low_stock'] == true) 'Low stock',
                          if (row['estimate'] == null)
                            'No positive recorded cost'
                          else
                            'Average cost ₹${row['unit_cost']} · Estimated value ₹${row['estimate']}',
                        ].join('\n'),
                      ),
                    ),
                  ),
              ],
              if (failed)
                TextButton(
                  onPressed: busy ? null : () => load(),
                  child: const Text('Unable to load stock valuation. Retry'),
                )
              else if (totals != null && rows.length < (totals['count'] as int))
                TextButton(
                  onPressed: busy ? null : () => load(),
                  child: const Text('Load more stock'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
