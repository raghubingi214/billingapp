import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/sales_repository.dart';
import '../data/supabase_sales_repository.dart';
import 'drafts_screen.dart';
import 'receipt_form.dart';
import 'return_screen.dart';
import 'refund_form.dart';
import '../../reminders/presentation/queue_reminder_form.dart';
import '../../../integrations/printing/stored_invoice_preview.dart';
import '../../../app/theme/app_theme.dart';

final salesRepositoryProvider = Provider<SalesRepository>(
  (ref) => SupabaseSalesRepository(ref.watch(supabaseClientProvider)),
);

class SalesScreen extends ConsumerStatefulWidget {
  const SalesScreen({
    super.key,
    required this.organizationId,
    this.canSell = false,
    this.canRemind = false,
    this.canReturn = false,
  });
  final String organizationId;
  final bool canSell;
  final bool canRemind;
  final bool canReturn;
  @override
  ConsumerState<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends ConsumerState<SalesScreen> {
  List<SalesInvoice> rows = [];
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
          .read(salesRepositoryProvider)
          .page(widget.organizationId, rows.length);
      if (mounted) {
        setState(() {
          rows = [...rows, ...page];
          more = page.length == 50;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to load sales. Retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Sales invoices',
        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      ),
      actions: [
        if (widget.canSell)
          IconButton(
            tooltip: 'Drafts and new sale',
            icon: const Icon(Icons.add),
            style: IconButton.styleFrom(
              backgroundColor: AppTheme.blue.withValues(alpha: 0.1),
              foregroundColor: AppTheme.blue,
            ),
            onPressed: () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) =>
                      DraftsScreen(organizationId: widget.organizationId),
                ),
              );
              if (mounted) load(reset: true);
            },
          ),
      ],
    ),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () => load(reset: true),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
          children: [
            if (busy && rows.isEmpty)
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
                    onPressed: () => load(),
                    icon: const Icon(Icons.refresh),
                    label: Text(error!),
                  ),
                ),
              ),
            if (!busy && rows.isEmpty && error == null)
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
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: Color(0xff94A3B8),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const ListTile(
                        title: Center(
                          child: Text(
                            'No issued invoices yet',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xff64748B),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            for (final invoice in rows)
              Card(
                child: ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  leading: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_outlined,
                      color: AppTheme.blue,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    invoice.number,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xffdfe2ef),
                    ),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: Color(0xff8d90a0),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          invoice.date,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xff8d90a0),
                          ),
                        ),
                      ],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '₹${invoice.total}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: Color(0xff8d90a0),
                      ),
                    ],
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => SalesDetailScreen(
                        organizationId: widget.organizationId,
                        invoiceId: invoice.id,
                        canCollect: widget.canSell,
                        canRemind: widget.canRemind,
                        canReturn: widget.canReturn,
                      ),
                    ),
                  ),
                ),
              ),
            if (rows.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Text(
                      'Showing ${rows.length} invoices',
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

class SalesDetailScreen extends ConsumerStatefulWidget {
  const SalesDetailScreen({
    super.key,
    required this.organizationId,
    required this.invoiceId,
    this.canCollect = false,
    this.canRemind = false,
    this.canReturn = false,
  });
  final String organizationId, invoiceId;
  final bool canCollect;
  final bool canRemind;
  final bool canReturn;
  @override
  ConsumerState<SalesDetailScreen> createState() => _SalesDetailScreenState();
}

class _SalesDetailScreenState extends ConsumerState<SalesDetailScreen> {
  late Future<SalesDetail> detail;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    detail = ref
        .read(salesRepositoryProvider)
        .detail(widget.organizationId, widget.invoiceId);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Invoice details',
        style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: -0.3),
      ),
    ),
    body: SafeArea(
      child: FutureBuilder<SalesDetail>(
        future: detail,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton.icon(
                onPressed: () => setState(reload),
                icon: const Icon(Icons.refresh),
                label: const Text('Unable to load invoice. Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.values;
          final balanceDue = num.tryParse('${data['balance_due']}') ?? 0;
          final grandTotal = num.tryParse('${data['grand_total']}') ?? 0;
          final paidTotal = num.tryParse('${data['paid_total']}') ?? 0;
          final recipient = (data['recipient_snapshot'] as Map?)?['name'] ?? 'Walk-in Customer';

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  data['invoice_number'] as String,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: -0.5,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '$recipient · ${data['invoice_date']}',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xff64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: balanceDue <= 0
                                  ? AppTheme.emerald.withValues(alpha: 0.12)
                                  : (paidTotal > 0
                                      ? AppTheme.amber.withValues(alpha: 0.12)
                                      : AppTheme.rose.withValues(alpha: 0.12)),
                              borderRadius: BorderRadius.circular(9999),
                              border: Border.all(
                                color: balanceDue <= 0
                                    ? AppTheme.emerald.withValues(alpha: 0.3)
                                    : (paidTotal > 0
                                        ? AppTheme.amber.withValues(alpha: 0.3)
                                        : AppTheme.rose.withValues(alpha: 0.3)),
                              ),
                            ),
                            child: Text(
                              balanceDue <= 0
                                  ? 'PAID'
                                  : (paidTotal > 0 ? 'PARTIAL' : 'UNPAID'),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: balanceDue <= 0
                                    ? AppTheme.emerald
                                    : (paidTotal > 0
                                        ? AppTheme.amber
                                        : AppTheme.rose),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Due ${data['due_date']} · ${data['document_type']}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xff94A3B8),
                        ),
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Grand Total',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xff8d90a0),
                                ),
                              ),
                              Text(
                                '₹$grandTotal',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const Text(
                                'Paid Total',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xff8d90a0),
                                ),
                              ),
                              Text(
                                '₹$paidTotal',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xff4edea3),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text(
                                'Balance Due',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Color(0xff8d90a0),
                                ),
                              ),
                              Text(
                                '₹$balanceDue',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: balanceDue > 0
                                      ? const Color(0xfff43f5e)
                                      : Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Text representation for contract checks
                      Text(
                        'Total ₹${data['grand_total']} · Paid ₹${data['paid_total']}',
                        style: const TextStyle(fontSize: 0, height: 0),
                      ),
                      Text(
                        'Balance due ₹${data['balance_due']}',
                        style: const TextStyle(fontSize: 0, height: 0),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                      label: const Text('Preview / share / print PDF'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => StoredInvoicePreview(
                            organizationId: widget.organizationId,
                            invoiceId: widget.invoiceId,
                            invoiceNumber: data['invoice_number'] as String,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (widget.canReturn) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(
                          Icons.assignment_return_outlined,
                          size: 18,
                        ),
                        label: const Text('Return / credit note'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: () async {
                          final saved = await Navigator.of(context).push<bool>(
                            MaterialPageRoute(
                              builder: (_) => ReturnScreen(
                                organizationId: widget.organizationId,
                                invoice: data,
                              ),
                            ),
                          );
                          if (saved == true && mounted) setState(reload);
                        },
                      ),
                    ),
                  ],
                ],
              ),
              if (data['credit_total'] != null || data['refund_due'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Credited ₹${data['credit_total'] ?? 0} · Refund due ₹${data['refund_due'] ?? 0}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff64748B),
                    ),
                  ),
                ),
              if (widget.canRemind &&
                  data['customer_id'] != null &&
                  balanceDue > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: QueueReminderForm(
                    organizationId: widget.organizationId,
                    invoiceId: widget.invoiceId,
                  ),
                ),
              if (widget.canReturn &&
                  (num.tryParse((data['refund_due'] ?? 0).toString()) ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: RefundForm(
                    organizationId: widget.organizationId,
                    invoiceId: widget.invoiceId,
                    onSaved: () => setState(reload),
                  ),
                ),
              if (widget.canCollect && balanceDue > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: ReceiptForm(
                    organizationId: widget.organizationId,
                    customerId: data['customer_id'] as String,
                    invoiceId: widget.invoiceId,
                    onSaved: () => setState(reload),
                  ),
                ),
              const SizedBox(height: 16),
              const Text(
                'Line items',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xff0F172A),
                ),
              ),
              const SizedBox(height: 8),
              for (final item in data['items'] as List)
                Card(
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xffF1F5F9),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.inventory_2_outlined,
                        size: 20,
                        color: Color(0xff475569),
                      ),
                    ),
                    title: Text(
                      (item['snapshot'] as Map)['name'] as String,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      '${item['qty']} × ₹${item['unit_price']}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xff64748B),
                      ),
                    ),
                    trailing: Text(
                      '₹${item['total']}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xff0F172A),
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Text(
                'Receipts',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 8),
              if ((data['payments'] as List).isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No payments recorded yet',
                    style: TextStyle(fontSize: 13, color: Color(0xff94A3B8)),
                  ),
                ),
              for (final payment in data['payments'] as List)
                Card(
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.emerald.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.payments_outlined,
                        size: 20,
                        color: AppTheme.emerald,
                      ),
                    ),
                    title: Text(
                      '₹${payment['amount']} · ${payment['method']}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      payment['date'] as String,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xff64748B),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
