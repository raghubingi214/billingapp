import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/purchase_repository.dart';
import '../data/supabase_purchase_repository.dart';
import 'purchase_detail_screen.dart';

final purchaseRepositoryProvider = Provider<PurchaseRepository>(
  (ref) => SupabasePurchaseRepository(ref.watch(supabaseClientProvider)),
);

class PurchasesScreen extends ConsumerStatefulWidget {
  const PurchasesScreen({
    super.key,
    required this.organizationId,
    required this.canReceive,
  });
  final String organizationId;
  final bool canReceive;
  @override
  ConsumerState<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends ConsumerState<PurchasesScreen> {
  List<PurchaseSummary> rows = [];
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
          .read(purchaseRepositoryProvider)
          .page(widget.organizationId, rows.length);
      if (mounted) {
        setState(() {
          rows = [...rows, ...page];
          more = page.length == 50;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to load purchases. Retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Purchases')),
    floatingActionButton: widget.canReceive
        ? FloatingActionButton(
            tooltip: 'Receive purchase',
            child: const Icon(Icons.add),
            onPressed: () async {
              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) =>
                      PurchaseEditor(organizationId: widget.organizationId),
                ),
              );
              if (saved == true && mounted) load(reset: true);
            },
          )
        : null,
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () => load(reset: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              TextButton(onPressed: () => load(), child: Text(error!)),
            if (!busy && rows.isEmpty)
              const ListTile(title: Text('No received purchases yet')),
            for (final row in rows)
              Card(
                child: ListTile(
                  title: Text(row.number),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => PurchaseDetailScreen(
                        organizationId: widget.organizationId,
                        purchaseId: row.id,
                        canPay: widget.canReceive,
                      ),
                    ),
                  ),
                  subtitle: Text(row.date),
                  trailing: Text('₹${row.total}'),
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

class _Line {
  String? product;
  final qty = TextEditingController(text: '1'),
      cost = TextEditingController(text: '0'),
      tax = TextEditingController(text: '0');
  void dispose() {
    qty.dispose();
    cost.dispose();
    tax.dispose();
  }

  Map<String, String> get data => {
    'product_id': product!,
    'qty': qty.text.trim(),
    'unit_cost': cost.text.trim(),
    'tax_percent': tax.text.trim(),
  };
}

class PurchaseEditor extends ConsumerStatefulWidget {
  const PurchaseEditor({super.key, required this.organizationId});
  final String organizationId;
  @override
  ConsumerState<PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends ConsumerState<PurchaseEditor> {
  final form = GlobalKey<FormState>(),
      bill = TextEditingController(),
      date = TextEditingController();
  final lines = <_Line>[_Line()];
  List<PurchaseChoice> outlets = [], suppliers = [], products = [];
  String? outlet, supplier, error;
  String requestId = const Uuid().v4(), lastPayload = '';
  bool loading = true, busy = false;
  @override
  void initState() {
    super.initState();
    date.text = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30))
        .toIso8601String()
        .substring(0, 10);
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repository = ref.read(purchaseRepositoryProvider);
      final choices = await Future.wait(
        [
          'outlets',
          'suppliers',
          'products',
        ].map((type) => repository.choices(widget.organizationId, type)),
      );
      if (mounted) {
        setState(() {
          outlets = choices[0];
          suppliers = choices[1];
          products = choices[2];
          outlet = outlets.firstOrNull?.id;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to load purchase options. Retry.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    bill.dispose();
    date.dispose();
    for (final line in lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> receive() async {
    if (!form.currentState!.validate()) return;
    final items = lines.map((line) => line.data).toList();
    if (items.map((line) => line['product_id']).toSet().length !=
        items.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Combine quantities for duplicate products.'),
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Receive this purchase?'),
        content: const Text(
          'This posts the supplier bill and increases stock. Posted records are preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Receive'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final payload = '$outlet|$supplier|${bill.text.trim()}|${date.text}|$items';
    if (payload != lastPayload) {
      requestId = const Uuid().v4();
      lastPayload = payload;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(purchaseRepositoryProvider)
          .receive(
            requestId,
            widget.organizationId,
            outlet!,
            supplier!,
            bill.text.trim(),
            date.text,
            items,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not receive purchase. Check duplicate bill number, product details and access, then retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget choice(
    String label,
    List<PurchaseChoice> options,
    String? value,
    ValueChanged<String?> changed,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: options
        .map(
          (o) => DropdownMenuItem(
            value: o.id,
            child: Text(o.name, overflow: TextOverflow.ellipsis),
          ),
        )
        .toList(),
    onChanged: busy ? null : changed,
    validator: (value) => value == null ? 'Required' : null,
  );
  Widget decimal(
    String label,
    TextEditingController controller, {
    bool quantity = false,
  }) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: TextFormField(
      controller: controller,
      enabled: !busy,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
      validator: (v) {
        final value = v?.trim() ?? '';
        if (!RegExp(
          quantity ? r'^\d+(\.\d{1,3})?$' : r'^\d+(\.\d{1,2})?$',
        ).hasMatch(value)) {
          return 'Invalid decimal';
        }
        if (quantity && (num.tryParse(value) ?? 0) <= 0) {
          return 'Must be positive';
        }
        if (label == 'Tax (%)' && (num.tryParse(value) ?? 101) > 100) {
          return 'Maximum 100%';
        }
        return null;
      },
    ),
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Receive purchase')),
    body: SafeArea(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: TextButton(onPressed: load, child: Text(error!)),
            )
          : Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (outlets.isEmpty || suppliers.isEmpty || products.isEmpty)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 16),
                      child: Text(
                        'Add an active supplier and stock product before receiving a purchase.',
                      ),
                    ),
                  choice(
                    'Outlet',
                    outlets,
                    outlet,
                    (v) => setState(() => outlet = v),
                  ),
                  const SizedBox(height: 16),
                  choice(
                    'Supplier',
                    suppliers,
                    supplier,
                    (v) => setState(() => supplier = v),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: bill,
                    enabled: !busy,
                    decoration: const InputDecoration(
                      labelText: 'Supplier bill number',
                    ),
                    validator: (v) =>
                        (v?.trim().isEmpty ?? true) ? 'Required' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: date,
                    readOnly: true,
                    decoration: const InputDecoration(labelText: 'Bill date'),
                    onTap: busy
                        ? null
                        : () async {
                            final now = DateTime.now();
                            final selected = await showDatePicker(
                              context: context,
                              initialDate: DateTime.tryParse(date.text) ?? now,
                              firstDate: DateTime(2000),
                              lastDate: now,
                            );
                            if (selected != null) {
                              date.text = selected.toIso8601String().substring(
                                0,
                                10,
                              );
                            }
                          },
                  ),
                  for (final line in lines)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            choice(
                              'Product',
                              products,
                              line.product,
                              (v) => setState(() => line.product = v),
                            ),
                            decimal('Quantity', line.qty, quantity: true),
                            decimal('Unit cost excluding tax (₹)', line.cost),
                            decimal('Tax (%)', line.tax),
                            if (lines.length > 1)
                              TextButton(
                                onPressed: busy
                                    ? null
                                    : () => setState(() {
                                        lines.remove(line);
                                        line.dispose();
                                      }),
                                child: const Text('Remove line'),
                              ),
                          ],
                        ),
                      ),
                    ),
                  OutlinedButton(
                    onPressed: busy || lines.length >= 100
                        ? null
                        : () => setState(() => lines.add(_Line())),
                    child: const Text('Add product line'),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : receive,
                    child: Text(busy ? 'Receiving…' : 'Receive stock'),
                  ),
                ],
              ),
            ),
    ),
  );
}
