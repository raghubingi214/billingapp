import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/purchase_detail_repository.dart';
import '../domain/pending_purchase_return.dart';
import '../data/shared_preferences_pending_return_store.dart';
import '../data/supabase_purchase_detail_repository.dart';
import 'supplier_refund_screen.dart';

final purchaseDetailRepositoryProvider = Provider<PurchaseDetailRepository>(
  (ref) => SupabasePurchaseDetailRepository(ref.watch(supabaseClientProvider)),
);
final pendingPurchaseReturnStoreProvider = Provider<PendingPurchaseReturnStore>(
  (ref) => SharedPreferencesPendingReturnStore(),
);
final purchaseReturnActorIdProvider = Provider<String?>((ref) {
  try {
    return ref.watch(supabaseClientProvider).auth.currentUser?.id;
  } catch (_) {
    return null;
  }
});

class PurchaseDetailScreen extends ConsumerStatefulWidget {
  const PurchaseDetailScreen({
    super.key,
    required this.organizationId,
    required this.purchaseId,
    required this.canPay,
  });
  final String organizationId, purchaseId;
  final bool canPay;
  @override
  ConsumerState<PurchaseDetailScreen> createState() =>
      _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends ConsumerState<PurchaseDetailScreen> {
  late Future<PurchaseDetail> detail;
  final amount = TextEditingController(), reference = TextEditingController();
  final form = GlobalKey<FormState>();
  String method = 'cash', requestId = const Uuid().v4(), lastPayload = '';
  String returnKey = const Uuid().v4(), lastReturnPayload = '';
  PendingPurchaseReturn? pendingReturn;
  String? pendingActorId, restoreError;
  bool restoring = true;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    reload();
    restorePending();
  }

  Future<void> restorePending() async {
    if (mounted) setState(() => restoring = true);
    final actor = ref.read(purchaseReturnActorIdProvider);
    if (!widget.canPay || actor == null) {
      if (mounted) setState(() => restoring = false);
      return;
    }
    try {
      final restored = await ref
          .read(pendingPurchaseReturnStoreProvider)
          .load(actor, widget.organizationId, widget.purchaseId);
      if (mounted && restored != null) {
        setState(() {
          pendingReturn = restored;
          pendingActorId = actor;
          restoreError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => restoreError =
              'Unable to restore pending return. Retry loading it.',
        );
      }
    } finally {
      if (mounted) setState(() => restoring = false);
    }
  }

  Future<void> clearPendingReturn() async {
    final actor = pendingActorId;
    if (actor != null) {
      await ref
          .read(pendingPurchaseReturnStoreProvider)
          .clear(actor, widget.organizationId, widget.purchaseId);
    }
    pendingReturn = null;
    pendingActorId = null;
  }

  void reload() {
    detail = ref
        .read(purchaseDetailRepositoryProvider)
        .detail(widget.organizationId, widget.purchaseId);
  }

  @override
  void dispose() {
    amount.dispose();
    reference.dispose();
    super.dispose();
  }

  Future<void> pay(PurchaseDetail purchase) async {
    if (!form.currentState!.validate() || busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record supplier payment?'),
        content: Text('₹${amount.text.trim()} by $method'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Record payment'),
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
    final payload =
        '${amount.text.trim()}|$method|${reference.text.trim()}|$date';
    if (payload != lastPayload) {
      requestId = const Uuid().v4();
      lastPayload = payload;
    }
    setState(() => busy = true);
    try {
      await ref
          .read(purchaseDetailRepositoryProvider)
          .pay(
            requestId,
            widget.organizationId,
            purchase.values['supplier_id'] as String,
            widget.purchaseId,
            amount.text.trim(),
            method,
            reference.text.trim(),
            date,
          );
      if (mounted) {
        amount.clear();
        reference.clear();
        setState(reload);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Payment was not recorded. Check balance, duplicate reference and access, then retry.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> returnItems(PurchaseDetail purchase) async {
    if (restoreError != null) {
      await restorePending();
      return;
    }
    if (pendingReturn != null) {
      await retryReturn();
      return;
    }
    final items = (purchase.values['items'] as List)
        .cast<Map<String, dynamic>>();
    final quantities = [for (final _ in items) TextEditingController()];
    final reason = TextEditingController(), creditRef = TextEditingController();
    final returnForm = GlobalKey<FormState>();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Return goods to supplier'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: returnForm,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < items.length; i++)
                    TextFormField(
                      controller: quantities[i],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            '${(items[i]['product_snapshot'] as Map)['name']} · received ${items[i]['qty']}',
                      ),
                      validator: (v) {
                        final text = v?.trim() ?? '';
                        if (text.isEmpty) return null;
                        final qty = num.tryParse(text),
                            received = num.tryParse(items[i]['qty'].toString()),
                            returned =
                                num.tryParse(
                                  items[i]['returned_qty'].toString(),
                                ) ??
                                0;
                        if (!RegExp(r'^\d+(\.\d{1,3})?$').hasMatch(text) ||
                            qty == null ||
                            qty <= 0 ||
                            received == null ||
                            qty > received - returned) {
                          return 'Enter up to the remaining quantity';
                        }
                        return null;
                      },
                    ),
                  TextFormField(
                    controller: reason,
                    decoration: const InputDecoration(labelText: 'Reason'),
                    validator: (v) =>
                        (v?.trim().length ?? 0) < 3 ||
                            (v?.trim().length ?? 0) > 500
                        ? 'Enter 3–500 characters'
                        : null,
                  ),
                  TextFormField(
                    controller: creditRef,
                    decoration: const InputDecoration(
                      labelText: 'Supplier credit reference (optional)',
                    ),
                    validator: (v) => (v?.trim().length ?? 0) > 100
                        ? 'Maximum 100 characters'
                        : null,
                  ),
                ],
              ),
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
              if (!returnForm.currentState!.validate()) return;
              if (quantities.every((q) => q.text.trim().isEmpty)) return;
              Navigator.pop(context, true);
            },
            child: const Text('Preview credit'),
          ),
        ],
      ),
    );
    final lines = <Map<String, String>>[
      for (var i = 0; i < items.length; i++)
        if (quantities[i].text.trim().isNotEmpty)
          {
            'purchase_item_id': items[i]['id'] as String,
            'qty': quantities[i].text.trim(),
          },
    ];
    final note = reason.text.trim(), referenceValue = creditRef.text.trim();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final q in quantities) {
      q.dispose();
    }
    reason.dispose();
    creditRef.dispose();
    if (accepted != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      final preview = await ref
          .read(purchaseDetailRepositoryProvider)
          .previewReturn(widget.organizationId, widget.purchaseId, lines);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Post supplier return?'),
          content: Text(
            'Credit ₹${preview['total']} · ${lines.length} line(s)\n$note',
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
      final payload = '$note|$referenceValue|$lines';
      if (payload != lastReturnPayload) {
        returnKey = const Uuid().v4();
        lastReturnPayload = payload;
      }
      final command = PendingPurchaseReturn(
        requestId: returnKey,
        organizationId: widget.organizationId,
        purchaseId: widget.purchaseId,
        reason: note,
        reference: referenceValue.isEmpty ? null : referenceValue,
        items: lines,
      );
      final actor = ref.read(purchaseReturnActorIdProvider);
      if (actor != null) {
        await ref.read(pendingPurchaseReturnStoreProvider).save(actor, command);
      }
      pendingReturn = command;
      pendingActorId = actor;
      await pendingReturn!.send(ref.read(purchaseDetailRepositoryProvider));
      await clearPendingReturn();
      if (mounted) setState(reload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Return not confirmed. Use Retry pending return to safely check the same request.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> retryReturn() async {
    if (busy || pendingReturn == null) return;
    if (pendingActorId != ref.read(purchaseReturnActorIdProvider)) return;
    setState(() => busy = true);
    try {
      await pendingReturn!.send(ref.read(purchaseDetailRepositoryProvider));
      await clearPendingReturn();
      if (mounted) setState(reload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Return still unconfirmed. Retry this same request after checking the connection.',
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
    appBar: AppBar(title: const Text('Purchase details')),
    body: SafeArea(
      child: FutureBuilder<PurchaseDetail>(
        future: detail,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(reload),
                child: const Text('Unable to load purchase. Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final purchase = snapshot.data!, data = purchase.values;
          final supplier = data['supplier_snapshot'] as Map;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                data['supplier_bill_no'] as String,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text('${supplier['name']} · ${data['bill_date']}'),
              const SizedBox(height: 16),
              Text(
                'Total ₹${data['grand_total']} · Paid ₹${data['paid_total']}',
              ),
              Text('Returned credit ₹${data['returned_total'] ?? '0.00'}'),
              Text(
                'Net payable ₹${data['net_payable'] ?? data['grand_total']}',
              ),
              Text('Balance due ₹${data['balance_due']}'),
              if ((num.tryParse(data['supplier_credit_due'].toString()) ?? 0) >
                  0)
                Text('Supplier owes credit ₹${data['supplier_credit_due']}'),
              if ((num.tryParse(data['supplier_refunded_total'].toString()) ??
                      0) >
                  0)
                Text('Supplier refunded ₹${data['supplier_refunded_total']}'),
              if (widget.canPay &&
                  (num.tryParse(data['supplier_credit_due'].toString()) ?? 0) >
                      0)
                TextButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          final saved = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => SupplierRefundScreen(
                                repository: ref.read(
                                  purchaseDetailRepositoryProvider,
                                ),
                                organizationId: widget.organizationId,
                                purchaseId: widget.purchaseId,
                                creditDue: data['supplier_credit_due']
                                    .toString(),
                              ),
                            ),
                          );
                          if (saved == true && mounted) setState(reload);
                        },
                  icon: const Icon(Icons.call_received),
                  label: const Text('Record supplier refund'),
                ),
              if (pendingReturn != null)
                FilledButton.icon(
                  onPressed: busy ? null : retryReturn,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Retry pending return'),
                ),
              if (restoreError != null)
                TextButton(
                  onPressed: restorePending,
                  child: Text(restoreError!),
                ),
              if (restoring) const LinearProgressIndicator(),
              if (widget.canPay &&
                  !restoring &&
                  restoreError == null &&
                  pendingReturn == null &&
                  (data['items'] as List).isNotEmpty)
                TextButton.icon(
                  onPressed: busy ? null : () => returnItems(purchase),
                  icon: const Icon(Icons.keyboard_return),
                  label: const Text('Return goods to supplier'),
                ),
              const SizedBox(height: 16),
              for (final item in data['items'] as List)
                Card(
                  child: ListTile(
                    title: Text(
                      (item['product_snapshot'] as Map)['name'] as String,
                    ),
                    subtitle: Text(
                      '${item['qty']} × ₹${item['unit_cost']} · Tax ${item['tax_percent']}% · Returned ${item['returned_qty'] ?? 0}',
                    ),
                    trailing: Text('₹${item['line_total']}'),
                  ),
                ),
              const SizedBox(height: 16),
              if ((data['returns'] as List?)?.isNotEmpty ?? false) ...[
                Text('Returns', style: Theme.of(context).textTheme.titleLarge),
                for (final returned in data['returns'] as List)
                  ListTile(
                    title: Text('Credit ₹${returned['total']}'),
                    subtitle: Text(
                      '${returned['date']} · ${returned['reason']}',
                    ),
                  ),
                const SizedBox(height: 16),
              ],
              if ((data['refunds'] as List?)?.isNotEmpty ?? false) ...[
                Text(
                  'Supplier refunds',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                for (final refund in data['refunds'] as List)
                  ListTile(
                    title: Text('₹${refund['amount']} · ${refund['method']}'),
                    subtitle: Text(
                      '${refund['date']} · ${refund['reference'] ?? ''}',
                    ),
                  ),
              ],
              Text('Payments', style: Theme.of(context).textTheme.titleLarge),
              for (final payment in data['payments'] as List)
                ListTile(
                  title: Text('₹${payment['amount']} · ${payment['method']}'),
                  subtitle: Text(
                    '${payment['date']} · ${payment['reference'] ?? ''}',
                  ),
                ),
              if (widget.canPay &&
                  (num.tryParse(data['balance_due'].toString()) ?? 0) > 0)
                Form(
                  key: form,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: amount,
                        enabled: !busy,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Payment amount (₹)',
                        ),
                        validator: (v) {
                          final value = v?.trim() ?? '';
                          if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value) ||
                              (num.tryParse(value) ?? 0) <= 0 ||
                              (num.tryParse(value) ?? 0) >
                                  (num.tryParse(
                                        data['balance_due'].toString(),
                                      ) ??
                                      0)) {
                            return 'Enter an amount up to the balance due';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: method,
                        decoration: const InputDecoration(labelText: 'Method'),
                        items: ['cash', 'upi', 'card', 'bank', 'other']
                            .map(
                              (m) => DropdownMenuItem(value: m, child: Text(m)),
                            )
                            .toList(),
                        onChanged: busy
                            ? null
                            : (v) => setState(() => method = v!),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: reference,
                        enabled: !busy,
                        decoration: const InputDecoration(
                          labelText: 'Reference',
                        ),
                        validator: (v) =>
                            method != 'cash' && (v?.trim().isEmpty ?? true)
                            ? 'Reference required'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: busy ? null : () => pay(purchase),
                        child: Text(busy ? 'Recording…' : 'Record payment'),
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
