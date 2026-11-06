import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/return_repository.dart';
import '../data/supabase_return_repository.dart';

final returnRepositoryProvider = Provider<ReturnRepository>(
  (ref) => SupabaseReturnRepository(ref.watch(supabaseClientProvider)),
);

class ReturnScreen extends ConsumerStatefulWidget {
  const ReturnScreen({
    super.key,
    required this.organizationId,
    required this.invoice,
  });
  final String organizationId;
  final Map<String, dynamic> invoice;
  @override
  ConsumerState<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends ConsumerState<ReturnScreen> {
  final form = GlobalKey<FormState>(), reason = TextEditingController();
  final quantities = <String, TextEditingController>{},
      restock = <String, bool>{};
  bool busy = false;
  String requestId = const Uuid().v4(), lastPayload = '';
  List<dynamic> get items => widget.invoice['items'] as List;
  @override
  void initState() {
    super.initState();
    for (final item in items) {
      quantities[item['id'] as String] = TextEditingController(text: '0');
      restock[item['id'] as String] = false;
    }
  }

  @override
  void dispose() {
    reason.dispose();
    for (final controller in quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> post() async {
    if (busy || !form.currentState!.validate()) return;
    final selected = <Map<String, Object?>>[];
    for (final item in items) {
      final id = item['id'] as String,
          quantity = quantities[item['id']]!.text.trim();
      if ((num.tryParse(quantity) ?? 0) > 0) {
        selected.add({
          'invoice_item_id': id,
          'qty': quantity,
          'restock': restock[id],
        });
      }
    }
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter at least one return quantity.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Post return and credit note?'),
        content: const Text(
          'The server calculates credit from the original invoice. Selected goods will be restocked. This preserves the original invoice.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Post return'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final payload = '${reason.text.trim()}|$selected';
    if (lastPayload != payload) {
      requestId = const Uuid().v4();
      lastPayload = payload;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(returnRepositoryProvider)
          .post(
            requestId,
            widget.organizationId,
            widget.invoice['id'] as String,
            reason.text.trim(),
            selected,
          );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Return could not be posted. Check remaining quantities and permissions; reopen if changed elsewhere.',
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
    appBar: AppBar(title: const Text('Sales return')),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.invoice['invoice_number'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const Text('Enter zero for lines that are not being returned.'),
            for (final item in items)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text((item['snapshot'] as Map)['name'] as String),
                      Text(
                        'Sold ${item['qty']} · Already returned ${item['returned_qty'] ?? 0}',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: quantities[item['id']],
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'Return quantity',
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        validator: (v) {
                          if (!RegExp(
                            r'^\d+(\.\d{1,3})?$',
                          ).hasMatch(v?.trim() ?? '')) {
                            return 'Use up to three decimals';
                          }
                          final remaining =
                              (num.tryParse(item['qty'].toString()) ?? 0) -
                              (num.tryParse(
                                    (item['returned_qty'] ?? 0).toString(),
                                  ) ??
                                  0);
                          return (num.tryParse(v!.trim()) ?? 0) > remaining
                              ? 'Exceeds remaining quantity'
                              : null;
                        },
                      ),
                      if ((item['snapshot'] as Map)['type'] == 'product')
                        SwitchListTile(
                          title: const Text('Restock these goods'),
                          value: restock[item['id']]!,
                          onChanged: busy
                              ? null
                              : (value) => setState(
                                  () => restock[item['id'] as String] = value,
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            TextFormField(
              controller: reason,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Return reason'),
              validator: (v) => (v?.trim().length ?? 0) >= 3
                  ? null
                  : 'Enter a reason (3+ characters)',
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : post,
              child: Text(busy ? 'Posting…' : 'Review return'),
            ),
          ],
        ),
      ),
    ),
  );
}
