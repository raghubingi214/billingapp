import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/receipt_repository.dart';
import '../data/supabase_receipt_repository.dart';

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => SupabaseReceiptRepository(ref.watch(supabaseClientProvider)),
);

class ReceiptForm extends ConsumerStatefulWidget {
  const ReceiptForm({
    super.key,
    required this.organizationId,
    required this.customerId,
    required this.invoiceId,
    required this.onSaved,
  });
  final String organizationId, customerId, invoiceId;
  final VoidCallback onSaved;
  @override
  ConsumerState<ReceiptForm> createState() => _ReceiptFormState();
}

class _ReceiptFormState extends ConsumerState<ReceiptForm> {
  final form = GlobalKey<FormState>(),
      amount = TextEditingController(),
      reference = TextEditingController();
  bool busy = false;
  String method = 'cash', keyId = const Uuid().v4(), lastPayload = '';
  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final value = amount.text.trim(),
        refText = reference.text.trim(),
        selectedMethod = method;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record customer receipt?'),
        content: Text('₹$value by $selectedMethod'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record receipt'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final date = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30))
        .toIso8601String()
        .substring(0, 10);
    final payload = '$value|$selectedMethod|$refText|$date';
    if (payload != lastPayload) {
      keyId = const Uuid().v4();
      lastPayload = payload;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(receiptRepositoryProvider)
          .record(
            keyId,
            widget.organizationId,
            widget.customerId,
            widget.invoiceId,
            value,
            selectedMethod,
            refText,
            date,
          );
      if (mounted) {
        amount.clear();
        reference.clear();
        widget.onSaved();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Receipt could not be recorded. Check the remaining balance, reference and access before retrying.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      children: [
        TextFormField(
          controller: amount,
          enabled: !busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Receipt amount (₹)'),
          validator: (v) {
            final value = v?.trim() ?? '';
            if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value) ||
                (num.tryParse(value) ?? 0) <= 0) {
              return 'Enter a positive amount';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: method,
          decoration: const InputDecoration(labelText: 'Method'),
          items: [
            'cash',
            'upi',
            'card',
            'bank',
            'other',
          ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
          onChanged: busy ? null : (v) => setState(() => method = v!),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: reference,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'Reference'),
          validator: (v) => method != 'cash' && (v?.trim().isEmpty ?? true)
              ? 'Reference required'
              : null,
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Recording…' : 'Record receipt'),
        ),
      ],
    ),
  );
}
