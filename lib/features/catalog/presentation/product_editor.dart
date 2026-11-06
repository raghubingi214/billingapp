import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../domain/catalog_repository.dart';
import 'catalog_screen.dart';
import '../../../integrations/scanning/barcode_scanner.dart';

class ProductEditor extends ConsumerStatefulWidget {
  const ProductEditor({super.key, required this.organizationId, this.product});
  final String organizationId;
  final CatalogProduct? product;
  @override
  ConsumerState<ProductEditor> createState() => _ProductEditorState();
}

class _ProductEditorState extends ConsumerState<ProductEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  String type = 'product', requestId = const Uuid().v4();
  Map<String, Object?>? lastPayload;
  bool inclusive = false, busy = false;
  @override
  void initState() {
    super.initState();
    final values = widget.product?.values ?? {};
    for (final key in [
      'name',
      'sku',
      'barcode',
      'category',
      'unit',
      'hsn_sac',
      'sale_price',
      'purchase_price',
      'tax_percent',
      'reorder_level',
    ]) {
      fields[key] = TextEditingController(
        text:
            values[key]?.toString() ??
            (key == 'unit'
                ? 'pcs'
                : [
                    'sale_price',
                    'purchase_price',
                    'tax_percent',
                    'reorder_level',
                  ].contains(key)
                ? '0'
                : ''),
      );
    }
    type = widget.product?.type ?? 'product';
    inclusive = values['price_includes_tax'] == true;
  }

  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final payload = <String, Object?>{
      for (final entry in fields.entries) entry.key: entry.value.text.trim(),
      'type': type,
      'price_includes_tax': inclusive,
      'reorder_level': type == 'service'
          ? '0'
          : fields['reorder_level']!.text.trim(),
      'active': widget.product?.values['active'] ?? true,
    };
    if (lastPayload == null || payload.toString() != lastPayload.toString()) {
      requestId = const Uuid().v4();
      lastPayload = payload;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(catalogRepositoryProvider)
          .save(requestId, widget.organizationId, widget.product, payload);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to save. Check SKU uniqueness and access. If edited elsewhere, reopen the product.',
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
      title: Text(
        widget.product == null ? 'Add product or service' : 'Edit product',
      ),
    ),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              initialValue: type,
              decoration: const InputDecoration(labelText: 'Type'),
              items: [
                'product',
                'service',
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: widget.product != null || busy
                  ? null
                  : (v) => setState(() => type = v!),
            ),
            const SizedBox(height: 16),
            for (final entry in fields.entries) ...[
              if (entry.key != 'reorder_level' || type == 'product')
                TextFormField(
                  controller: entry.value,
                  enabled: !busy,
                  keyboardType:
                      [
                        'sale_price',
                        'purchase_price',
                        'tax_percent',
                        'reorder_level',
                      ].contains(entry.key)
                      ? const TextInputType.numberWithOptions(decimal: true)
                      : TextInputType.text,
                  decoration: InputDecoration(
                    suffixIcon: entry.key == 'barcode'
                        ? IconButton(
                            tooltip: 'Scan barcode',
                            icon: const Icon(Icons.qr_code_scanner),
                            onPressed: busy
                                ? null
                                : () async {
                                    final value = await ref.read(
                                      barcodeScannerProvider,
                                    )(context);
                                    if (value != null && mounted) {
                                      entry.value.text = value;
                                    }
                                  },
                          )
                        : null,
                    labelText: {
                      'name': 'Name',
                      'sku': 'SKU (optional)',
                      'barcode': 'Barcode (optional)',
                      'category': 'Category',
                      'unit': 'Unit',
                      'hsn_sac': 'HSN / SAC',
                      'sale_price': 'Selling price (₹)',
                      'purchase_price': 'Purchase price (₹)',
                      'tax_percent': 'Tax rate (%)',
                      'reorder_level': 'Reorder threshold',
                    }[entry.key],
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (['name', 'unit'].contains(entry.key) && text.isEmpty) {
                      return 'Required';
                    }
                    if ([
                      'sale_price',
                      'purchase_price',
                      'tax_percent',
                      'reorder_level',
                    ].contains(entry.key)) {
                      final pattern = entry.key == 'reorder_level'
                          ? r'^\d+(\.\d{1,3})?$'
                          : r'^\d+(\.\d{1,2})?$';
                      if (!RegExp(pattern).hasMatch(text)) {
                        return 'Enter a valid nonnegative decimal';
                      }
                      if (entry.key == 'tax_percent' &&
                          (num.tryParse(text) ?? 101) > 100) {
                        return 'Maximum 100%';
                      }
                    }
                    return null;
                  },
                ),
              const SizedBox(height: 16),
            ],
            SwitchListTile(
              title: const Text('Selling price includes tax'),
              value: inclusive,
              onChanged: busy ? null : (v) => setState(() => inclusive = v),
            ),
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Saving…' : 'Save'),
            ),
          ],
        ),
      ),
    ),
  );
}
