import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/supplier_repository.dart';
import '../data/supabase_supplier_repository.dart';

final supplierRepositoryProvider = Provider<SupplierRepository>(
  (ref) => SupabaseSupplierRepository(ref.watch(supabaseClientProvider)),
);

class SuppliersScreen extends ConsumerStatefulWidget {
  const SuppliersScreen({
    super.key,
    required this.organizationId,
    required this.canManage,
  });
  final String organizationId;
  final bool canManage;
  @override
  ConsumerState<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends ConsumerState<SuppliersScreen> {
  List<Supplier> suppliers = [];
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
      if (reset) suppliers = [];
      final page = await ref
          .read(supplierRepositoryProvider)
          .page(widget.organizationId, suppliers.length);
      if (mounted) {
        setState(() {
          suppliers = [...suppliers, ...page];
          more = page.length == 50;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to load suppliers. Retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(Supplier? supplier) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SupplierEditor(
          organizationId: widget.organizationId,
          supplier: supplier,
        ),
      ),
    );
    if (saved == true && mounted) load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Suppliers')),
    floatingActionButton: widget.canManage
        ? FloatingActionButton(
            tooltip: 'Add supplier',
            onPressed: () => edit(null),
            child: const Icon(Icons.add),
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
            if (!busy && suppliers.isEmpty)
              const ListTile(title: Text('No suppliers yet')),
            for (final supplier in suppliers)
              Card(
                child: ListTile(
                  title: Text(supplier.name),
                  subtitle: Text(
                    '${supplier.values['phone']} · ${supplier.values['payment_terms_days']} day terms',
                  ),
                  onTap: widget.canManage ? () => edit(supplier) : null,
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

class SupplierEditor extends ConsumerStatefulWidget {
  const SupplierEditor({
    super.key,
    required this.organizationId,
    this.supplier,
  });
  final String organizationId;
  final Supplier? supplier;
  @override
  ConsumerState<SupplierEditor> createState() => _SupplierEditorState();
}

class _SupplierEditorState extends ConsumerState<SupplierEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  String requestId = const Uuid().v4(), previousPayload = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    for (final field in [
      'name',
      'phone',
      'email',
      'gstin',
      'address',
      'payment_terms_days',
      'opening_balance',
    ]) {
      fields[field] = TextEditingController(
        text:
            widget.supplier?.values[field]?.toString() ??
            (['payment_terms_days', 'opening_balance'].contains(field)
                ? '0'
                : ''),
      );
    }
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final values = <String, Object?>{
      for (final field in fields.entries) field.key: field.value.text.trim(),
      'active': widget.supplier?.values['active'] ?? true,
    };
    if (values.toString() != previousPayload) {
      requestId = const Uuid().v4();
      previousPayload = values.toString();
    }
    setState(() => busy = true);
    try {
      await ref
          .read(supplierRepositoryProvider)
          .save(requestId, widget.organizationId, widget.supplier, values);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to save supplier. Check details and access; reopen if edited elsewhere.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(widget.supplier == null ? 'Add supplier' : 'Edit supplier'),
    ),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final field in fields.entries) ...[
              TextFormField(
                controller: field.value,
                enabled:
                    !busy &&
                    !(field.key == 'opening_balance' &&
                        widget.supplier != null),
                decoration: InputDecoration(
                  labelText: {
                    'name': 'Supplier name',
                    'phone': 'Phone',
                    'email': 'Email',
                    'gstin': 'GSTIN (optional)',
                    'address': 'Address',
                    'payment_terms_days': 'Payment terms (days)',
                    'opening_balance': 'Opening payable balance (₹)',
                  }[field.key],
                ),
                keyboardType:
                    [
                      'payment_terms_days',
                      'opening_balance',
                    ].contains(field.key)
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (field.key == 'name' && value.isEmpty) return 'Required';
                  if (field.key == 'email' &&
                      value.isNotEmpty &&
                      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
                    return 'Enter a valid email';
                  }
                  if (field.key == 'payment_terms_days' &&
                      (!RegExp(r'^\d{1,3}$').hasMatch(value) ||
                          (int.tryParse(value) ?? 366) > 365)) {
                    return 'Use 0 to 365 days';
                  }
                  if (field.key == 'opening_balance' &&
                      !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
                    return 'Use up to two decimals';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Saving…' : 'Save supplier'),
            ),
          ],
        ),
      ),
    ),
  );
}
