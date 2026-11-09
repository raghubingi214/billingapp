import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/inventory_repository.dart';
import '../data/supabase_inventory_repository.dart';
import 'stock_approvals_screen.dart';
import 'stock_history_sheet.dart';
import '../../../app/theme/app_theme.dart';

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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Count ${position.name}',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
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
    appBar: AppBar(
      title: const Text(
        'Stock',
        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      ),
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () => load(reset: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (outlets.isNotEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey(selected),
                    initialValue: selected,
                    decoration: const InputDecoration(
                      labelText: 'Outlet',
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    items: outlets
                        .map(
                          (o) => DropdownMenuItem(
                            value: o.id,
                            child: Text(
                              o.name,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: busy
                        ? null
                        : (v) {
                            setState(() => selected = v);
                            load(reset: true);
                          },
                  ),
                ),
              ),
            Card(
              child: SwitchListTile(
                title: const Text(
                  'Low stock only',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                secondary: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppTheme.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.warning_amber_rounded,
                    size: 20,
                    color: AppTheme.amber,
                  ),
                ),
                value: lowOnly,
                onChanged: busy
                    ? null
                    : (value) {
                        setState(() => lowOnly = value);
                        load(reset: true);
                      },
              ),
            ),
            if (busy && positions.isEmpty)
              const LinearProgressIndicator(minHeight: 2)
            else if (busy)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 4),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: TextButton.icon(
                    onPressed: () => load(reset: true),
                    icon: const Icon(Icons.refresh),
                    label: Text(error!),
                  ),
                ),
              ),
            if (!busy && positions.isEmpty && error == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xffF1F5F9),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          size: 48,
                          color: Color(0xff94A3B8),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No stock products yet.',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xff64748B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            for (final position in positions)
              Card(
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: AppTheme.blue,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    position.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xffdfe2ef),
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${position.quantity} ${position.unit} on hand',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xff8d90a0),
                      ),
                    ),
                  ),
                  onTap: widget.canReadHistory ? () => history(position) : null,
                  trailing: widget.canCount || widget.canRequest
                      ? IconButton(
                          tooltip: widget.canCount
                              ? 'Count stock'
                              : 'Request stock count',
                          icon: const Icon(Icons.edit_note, color: AppTheme.blue),
                          style: IconButton.styleFrom(
                            backgroundColor: AppTheme.blue.withValues(alpha: 0.08),
                          ),
                          onPressed: busy ? null : () => count(position),
                        )
                      : null,
                ),
              ),
            if (positions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Text(
                      'Showing ${positions.length} items',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Color(0xff64748B),
                      ),
                    ),
                    if (more && !busy) ...[
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () => load(),
                        icon: const Icon(Icons.keyboard_arrow_down, size: 18),
                        label: const Text('Load more'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.blue,
                          side: const BorderSide(color: Color(0xffCBD5E1)),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    ),
  );
}
