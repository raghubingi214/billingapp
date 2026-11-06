import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../domain/purchase_detail_repository.dart';

class SupplierRefundScreen extends StatefulWidget {
  const SupplierRefundScreen({
    super.key,
    required this.repository,
    required this.organizationId,
    required this.purchaseId,
    required this.creditDue,
  });
  final PurchaseDetailRepository repository;
  final String organizationId, purchaseId, creditDue;
  @override
  State<SupplierRefundScreen> createState() => _SupplierRefundScreenState();
}

class _SupplierRefundScreenState extends State<SupplierRefundScreen> {
  final form = GlobalKey<FormState>();
  final amount = TextEditingController(), reference = TextEditingController();
  String method = 'cash', requestId = const Uuid().v4(), lastPayload = '';
  bool busy = false;
  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    final money = amount.text.trim(), refValue = reference.text.trim();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record supplier refund?'),
        content: Text('Received ₹$money by $method'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm refund'),
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
    final payload = '$money|$method|$refValue|$date';
    if (payload != lastPayload) {
      requestId = const Uuid().v4();
      lastPayload = payload;
    }
    setState(() => busy = true);
    try {
      await widget.repository.recordSupplierCreditRefund(
        requestId,
        widget.organizationId,
        widget.purchaseId,
        money,
        date,
        method,
        refValue.isEmpty ? null : refValue,
      );
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Refund not confirmed. Check the supplier credit and retry with the same details.',
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
    appBar: AppBar(title: const Text('Supplier refund')),
    body: SafeArea(
      child: Form(
        key: form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Credit due ₹${widget.creditDue}',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            TextFormField(
              controller: amount,
              enabled: !busy,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Refund received (₹)',
              ),
              validator: (v) {
                final text = v?.trim() ?? '', value = num.tryParse(text);
                if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(text) ||
                    value == null ||
                    value <= 0 ||
                    value > (num.tryParse(widget.creditDue) ?? 0)) {
                  return 'Enter an amount up to the supplier credit';
                }
                return null;
              },
            ),
            DropdownButtonFormField<String>(
              initialValue: method,
              decoration: const InputDecoration(labelText: 'Method'),
              items: [
                'cash',
                'upi',
                'card',
                'bank',
                'other',
              ].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
              onChanged: busy ? null : (v) => setState(() => method = v!),
            ),
            TextFormField(
              controller: reference,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'Reference'),
              validator: (v) => method != 'cash' && (v?.trim().isEmpty ?? true)
                  ? 'Reference required'
                  : (v?.trim().length ?? 0) > 100
                  ? 'Maximum 100 characters'
                  : null,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: busy ? null : submit,
              child: const Text('Record supplier refund'),
            ),
          ],
        ),
      ),
    ),
  );
}
