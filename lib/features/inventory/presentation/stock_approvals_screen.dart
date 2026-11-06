import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/stock_approval_repository.dart';
import '../data/supabase_stock_approval_repository.dart';

final stockApprovalRepositoryProvider = Provider<StockApprovalRepository>(
  (ref) => SupabaseStockApprovalRepository(ref.watch(supabaseClientProvider)),
);

class StockApprovalsScreen extends ConsumerStatefulWidget {
  const StockApprovalsScreen({
    super.key,
    required this.organizationId,
    required this.canReview,
  });
  final String organizationId;
  final bool canReview;
  @override
  ConsumerState<StockApprovalsScreen> createState() =>
      _StockApprovalsScreenState();
}

class _StockApprovalsScreenState extends ConsumerState<StockApprovalsScreen> {
  List<StockApproval> rows = [];
  bool busy = false, more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (reset) rows = [];
      final page = await ref
          .read(stockApprovalRepositoryProvider)
          .page(widget.organizationId, rows.length);
      if (mounted) {
        setState(() {
          rows = [...rows, ...page];
          more = page.length == 50;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to load stock approvals. Retry.');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> review(StockApproval approval, bool approve) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'Approve stock count?' : 'Reject stock count?'),
        content: Text(
          '${approval.product}\nCounted: ${approval.quantity}\n${approval.reason}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      await ref
          .read(stockApprovalRepositoryProvider)
          .review(
            const Uuid().v4(),
            widget.organizationId,
            approval.id,
            approve,
          );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to review. If stock changed, reject this request and submit a fresh count.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
        load(reset: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stock approvals')),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () => load(reset: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              TextButton(onPressed: () => load(), child: Text(error!)),
            if (!busy && rows.isEmpty)
              const ListTile(title: Text('No stock requests')),
            for (final row in rows)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row.product} · ${row.outlet}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text('Counted ${row.quantity} · ${row.status}'),
                      Text(row.reason),
                      if (widget.canReview && row.status == 'pending')
                        Wrap(
                          spacing: 12,
                          children: [
                            TextButton(
                              onPressed: busy ? null : () => review(row, false),
                              child: const Text('Reject'),
                            ),
                            FilledButton(
                              onPressed: busy ? null : () => review(row, true),
                              child: const Text('Approve'),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            if (more && !busy)
              TextButton(
                onPressed: () => load(),
                child: const Text('Load more'),
              ),
          ],
        ),
      ),
    ),
  );
}
