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
      title: const Text('Sales invoices'),
      actions: [
        if (widget.canSell)
          IconButton(
            tooltip: 'Drafts and new sale',
            icon: const Icon(Icons.add),
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
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              TextButton(onPressed: () => load(), child: Text(error!)),
            if (!busy && rows.isEmpty)
              const ListTile(title: Text('No issued invoices yet')),
            for (final invoice in rows)
              Card(
                child: ListTile(
                  title: Text(invoice.number),
                  subtitle: Text(invoice.date),
                  trailing: Text('₹${invoice.total}'),
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
    appBar: AppBar(title: const Text('Invoice details')),
    body: SafeArea(
      child: FutureBuilder<SalesDetail>(
        future: detail,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(reload),
                child: const Text('Unable to load invoice. Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!.values;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              Text(
                data['invoice_number'] as String,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              Text(
                '${(data['recipient_snapshot'] as Map)['name']} · ${data['invoice_date']}',
              ),
              Text('Due ${data['due_date']} · ${data['document_type']}'),
              const SizedBox(height: 16),
              Text(
                'Total ₹${data['grand_total']} · Paid ₹${data['paid_total']}',
              ),
              Text('Balance due ₹${data['balance_due']}'),
              if (widget.canRemind &&
                  data['customer_id'] != null &&
                  (num.tryParse('${data['balance_due']}') ?? 0) > 0)
                QueueReminderForm(
                  organizationId: widget.organizationId,
                  invoiceId: widget.invoiceId,
                ),
              if (widget.canReturn &&
                  (num.tryParse((data['refund_due'] ?? 0).toString()) ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: RefundForm(
                    organizationId: widget.organizationId,
                    invoiceId: widget.invoiceId,
                    onSaved: () => setState(reload),
                  ),
                ),
              if (widget.canReturn)
                OutlinedButton.icon(
                  icon: const Icon(Icons.assignment_return_outlined),
                  label: const Text('Return / credit note'),
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
              Text(
                'Credited ₹${data['credit_total'] ?? 0} · Refund due ₹${data['refund_due'] ?? 0}',
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Preview / share / print PDF'),
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
              if (widget.canCollect &&
                  (num.tryParse(data['balance_due'].toString()) ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: ReceiptForm(
                    organizationId: widget.organizationId,
                    customerId: data['customer_id'] as String,
                    invoiceId: widget.invoiceId,
                    onSaved: () => setState(reload),
                  ),
                ),
              for (final item in data['items'] as List)
                Card(
                  child: ListTile(
                    title: Text((item['snapshot'] as Map)['name'] as String),
                    subtitle: Text('${item['qty']} × ₹${item['unit_price']}'),
                    trailing: Text('₹${item['total']}'),
                  ),
                ),
              const SizedBox(height: 16),
              Text('Receipts', style: Theme.of(context).textTheme.titleLarge),
              for (final payment in data['payments'] as List)
                ListTile(
                  title: Text('₹${payment['amount']} · ${payment['method']}'),
                  subtitle: Text(payment['date'] as String),
                ),
            ],
          );
        },
      ),
    ),
  );
}
