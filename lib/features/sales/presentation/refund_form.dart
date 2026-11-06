import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/refund_repository.dart';
import '../data/supabase_refund_repository.dart';

final refundRepositoryProvider = Provider<RefundRepository>(
  (ref) => SupabaseRefundRepository(ref.watch(supabaseClientProvider)),
);

class RefundForm extends ConsumerStatefulWidget {
  const RefundForm({
    super.key,
    required this.organizationId,
    required this.invoiceId,
    required this.onSaved,
  });
  final String organizationId, invoiceId;
  final VoidCallback onSaved;
  @override
  ConsumerState<RefundForm> createState() => _RefundFormState();
}

class _RefundFormState extends ConsumerState<RefundForm> {
  final form = GlobalKey<FormState>(),
      amount = TextEditingController(),
      reference = TextEditingController(),
      reason = TextEditingController();
  bool busy = false;
  String method = 'cash', requestId = const Uuid().v4(), lastPayload = '';
  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    reason.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record refund already paid?'),
        content: Text(
          '₹${amount.text.trim()} by $method. Confirm the customer has received this refund.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record refund'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final payload =
        '${amount.text.trim()}|$method|${reference.text.trim()}|${reason.text.trim()}';
    if (lastPayload != payload) {
      requestId = const Uuid().v4();
      lastPayload = payload;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(refundRepositoryProvider)
          .record(
            requestId,
            widget.organizationId,
            widget.invoiceId,
            amount.text.trim(),
            method,
            reference.text.trim(),
            reason.text.trim(),
          );
      if (mounted) {
        amount.clear();
        reference.clear();
        reason.clear();
        widget.onSaved();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Refund could not be recorded. Check remaining refund credit, reference and permissions.',
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Record a refund already paid to the customer.'),
        const SizedBox(height: 12),
        TextFormField(
          controller: amount,
          enabled: !busy,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Refund amount (₹)'),
          validator: (v) {
            final value = v?.trim() ?? '';
            return RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value) &&
                    (num.tryParse(value) ?? 0) > 0
                ? null
                : 'Enter a positive amount';
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          initialValue: method,
          decoration: const InputDecoration(labelText: 'Refund method'),
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
          decoration: const InputDecoration(labelText: 'Refund reference'),
          validator: (v) => method != 'cash' && (v?.trim().isEmpty ?? true)
              ? 'Reference required'
              : null,
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: reason,
          enabled: !busy,
          decoration: const InputDecoration(labelText: 'Refund reason'),
          validator: (v) => (v?.trim().length ?? 0) >= 3
              ? null
              : 'Enter a reason (3+ characters)',
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : save,
          child: Text(busy ? 'Recording…' : 'Review refund'),
        ),
      ],
    ),
  );
}
