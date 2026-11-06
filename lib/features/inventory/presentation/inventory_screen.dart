import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/inventory_repository.dart';
import '../data/supabase_inventory_repository.dart';
import 'stock_approvals_screen.dart';
import 'stock_history_sheet.dart';

final inventoryRepositoryProvider = Provider<InventoryRepository>(
  (ref) => SupabaseInventoryRepository(ref.watch(supabaseClientProvider)),
);

class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({
    super.key,
    required this.organizationId,
    required this.canCount,
    required this.canReadHistory,
    this.canRequest = false,
  });
  final String organizationId;
  final bool canCount, canReadHistory, canRequest;
  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  List<StockOutlet> outlets = [];
  List<StockPosition> positions = [];
  String? selected, error;
  bool busy = false, more = true, lowOnly = false;
  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (outlets.isEmpty) {
        outlets = await ref
            .read(inventoryRepositoryProvider)
            .outlets(widget.organizationId);
      }
      selected ??= outlets.firstOrNull?.id;
      if (reset) positions = [];
      final page = selected == null
          ? <StockPosition>[]
          : await ref
                .read(inventoryRepositoryProvider)
                .positions(
                  widget.organizationId,
                  selected!,
                  positions.length,
                  lowOnly: lowOnly,
                );
      if (mounted) {
        setState(() {
          positions = [...positions, ...page];
          more = page.length == 50;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Could not load stock. Retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> count(StockPosition position) async {
    final quantity = TextEditingController(text: position.quantity),
        reason = TextEditingController();
    final form = GlobalKey<FormState>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Count ${position.name}'),
        content: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: quantity,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Counted quantity',
                  ),
                  validator: (v) =>
                      RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(v?.trim() ?? '')
                      ? null
                      : 'Use up to three decimals',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: reason,
                  decoration: const InputDecoration(labelText: 'Reason'),
                  validator: (v) => (v?.trim().length ?? 0) >= 3
                      ? null
                      : 'Enter a reason (3+ characters)',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: Text(widget.canCount ? 'Post count' : 'Submit count'),
          ),
        ],
      ),
    );
    final value = quantity.text.trim(), note = reason.text.trim();
    // Dialog fields may still be animating out; controllers are disposed after transition.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    quantity.dispose();
    reason.dispose();
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      if (!widget.canCount) {
        await ref
            .read(stockApprovalRepositoryProvider)
            .request(
              const Uuid().v4(),
              widget.organizationId,
              selected!,
              position.productId,
              position.version,
              value,
              note,
            );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Count submitted for owner approval.'),
            ),
          );
        }
      } else {
        await ref
            .read(inventoryRepositoryProvider)
            .count(
              const Uuid().v4(),
              widget.organizationId,
              selected!,
              position,
              value,
              note,
            );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Count could not be posted. Refresh stock before retrying; it may have changed.',
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

  Future<void> history(StockPosition position) async {
    final outlet = selected!;
    final repository = ref.read(inventoryRepositoryProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StockHistorySheet(
        product: position.name,
        unit: position.unit,
        loadPage: (offset) => repository.movements(
          widget.organizationId,
          outlet,
          position.productId,
          offset,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Stock')),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () => load(reset: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (outlets.isNotEmpty)
              DropdownButtonFormField<String>(
                key: ValueKey(selected),
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Outlet'),
                items: outlets
                    .map(
                      (o) => DropdownMenuItem(value: o.id, child: Text(o.name)),
                    )
                    .toList(),
                onChanged: busy
                    ? null
                    : (v) {
                        setState(() => selected = v);
                        load(reset: true);
                      },
              ),
            SwitchListTile(
              title: const Text('Low stock only'),
              value: lowOnly,
              onChanged: busy
                  ? null
                  : (value) {
                      setState(() => lowOnly = value);
                      load(reset: true);
                    },
            ),
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              TextButton(
                onPressed: () => load(reset: true),
                child: Text(error!),
              ),
            if (!busy && positions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No stock products yet.'),
              ),
            for (final position in positions)
              Card(
                child: ListTile(
                  title: Text(position.name),
                  subtitle: Text(
                    '${position.quantity} ${position.unit} on hand',
                  ),
                  onTap: widget.canReadHistory ? () => history(position) : null,
                  trailing: widget.canCount || widget.canRequest
                      ? IconButton(
                          tooltip: widget.canCount
                              ? 'Count stock'
                              : 'Request stock count',
                          icon: const Icon(Icons.edit_note),
                          onPressed: busy ? null : () => count(position),
                        )
                      : null,
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
