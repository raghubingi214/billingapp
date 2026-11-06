import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/draft_repository.dart';
import '../domain/pending_invoice_issue.dart';
import '../data/supabase_draft_repository.dart';
import '../../../integrations/scanning/barcode_scanner.dart';

final draftRepositoryProvider = Provider<DraftRepository>(
  (ref) => SupabaseDraftRepository(ref.watch(supabaseClientProvider)),
);

class DraftsScreen extends ConsumerStatefulWidget {
  const DraftsScreen({super.key, required this.organizationId});
  final String organizationId;
  @override
  ConsumerState<DraftsScreen> createState() => _DraftsScreenState();
}

class _DraftsScreenState extends ConsumerState<DraftsScreen> {
  List<SaleDraft> rows = [];
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
          .read(draftRepositoryProvider)
          .drafts(widget.organizationId, rows.length);
      if (mounted) {
        setState(() {
          rows = [...rows, ...page];
          more = page.length == 50;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to load drafts. Retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(SaleDraft? draft) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            SaleEditor(organizationId: widget.organizationId, draft: draft),
      ),
    );
    if (mounted) load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sales drafts')),
    floatingActionButton: FloatingActionButton(
      tooltip: 'New sale',
      onPressed: () => edit(null),
      child: const Icon(Icons.add),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            TextButton(onPressed: () => load(), child: Text(error!)),
          if (!busy && rows.isEmpty)
            const ListTile(title: Text('No saved drafts')),
          for (final draft in rows)
            Card(
              child: ListTile(
                title: Text(
                  'Draft · ${(draft.values['items'] as List).length} lines',
                ),
                subtitle: Text(draft.values['updated_at'] as String),
                onTap: () => edit(draft),
              ),
            ),
          if (more && !busy)
            TextButton(onPressed: () => load(), child: const Text('Load more')),
        ],
      ),
    ),
  );
}

class _SaleLine {
  String? product;
  String kind = 'fixed';
  final qty = TextEditingController(text: '1'),
      discount = TextEditingController(text: '0');
  void dispose() {
    qty.dispose();
    discount.dispose();
  }

  Map<String, String> get data => {
    'product_id': product!,
    'qty': qty.text.trim(),
    'discount_kind': kind,
    'discount': discount.text.trim(),
  };
}

class SaleEditor extends ConsumerStatefulWidget {
  const SaleEditor({super.key, required this.organizationId, this.draft});
  final String organizationId;
  final SaleDraft? draft;
  @override
  ConsumerState<SaleEditor> createState() => _SaleEditorState();
}

class _SaleEditorState extends ConsumerState<SaleEditor> {
  final tenders = <_Tender>[];
  final form = GlobalKey<FormState>();
  final state = TextEditingController(),
      notes = TextEditingController(),
      due = TextEditingController();
  final lines = <_SaleLine>[];
  List<SaleOption> outlets = [], customers = [], products = [];
  String? outlet, customer, error;
  SaleDraft? draft;
  bool loading = true, busy = false;
  bool walkIn = false;
  PendingInvoiceIssue? pendingIssue;
  String saveKey = const Uuid().v4(),
      savePayload = '',
      issueKey = const Uuid().v4(),
      issuePayload = '';
  @override
  void initState() {
    super.initState();
    draft = widget.draft;
    final data = draft?.values;
    outlet = data?['outlet_id'] as String?;
    customer = data?['customer_id'] as String?;
    walkIn = data != null && customer == null;
    state.text = data?['place_of_supply'] as String? ?? '';
    notes.text = data?['notes'] as String? ?? '';
    due.text = DateTime.now()
        .toUtc()
        .add(const Duration(hours: 5, minutes: 30))
        .toIso8601String()
        .substring(0, 10);
    for (final item in data?['items'] as List? ?? []) {
      final line = _SaleLine();
      line.product = item['product_id'] as String?;
      line.kind = item['discount_kind'] as String? ?? 'fixed';
      line.qty.text = item['qty'].toString();
      line.discount.text = (item['discount'] ?? '0').toString();
      lines.add(line);
    }
    if (lines.isEmpty) lines.add(_SaleLine());
    load();
  }

  Future<void> load() async {
    try {
      final repo = ref.read(draftRepositoryProvider);
      final options = await Future.wait(
        [
          'outlets',
          'customers',
          'products',
        ].map((type) => repo.options(widget.organizationId, type)),
      );
      if (mounted) {
        setState(() {
          outlets = options[0];
          customers = options[1];
          products = options[2];
          outlet ??= outlets.firstOrNull?.id;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to load sale options.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  void dispose() {
    state.dispose();
    for (final tender in tenders) {
      tender.dispose();
    }
    notes.dispose();
    due.dispose();
    for (final line in lines) {
      line.dispose();
    }
    super.dispose();
  }

  Future<void> submit({required bool issue}) async {
    if (issue && pendingIssue != null) {
      if (busy) return;
      setState(() => busy = true);
      try {
        await pendingIssue!.send(ref.read(draftRepositoryProvider));
        if (mounted) Navigator.pop(context);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'The pending invoice could not be confirmed. Retry the same request when connected.',
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => busy = false);
      }
      return;
    }
    if (!form.currentState!.validate() || busy) return;
    if (issue && walkIn && tenders.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add payment for the full walk-in sale amount.'),
        ),
      );
      return;
    }
    setState(() => busy = true);
    try {
      final repo = ref.read(draftRepositoryProvider),
          items = lines.map((line) => line.data).toList();
      final payload =
          '$outlet|$customer|$walkIn|${state.text}|$items|${notes.text}|${draft?.values['version']}';
      if (payload != savePayload) {
        saveKey = const Uuid().v4();
        savePayload = payload;
      }
      draft = await repo.save(
        saveKey,
        widget.organizationId,
        draft,
        outlet!,
        walkIn ? null : customer!,
        state.text.trim(),
        items,
        notes.text.trim(),
      );
      if (!issue) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Draft saved.')));
        }
        return;
      }
      final quote = await repo.quote(widget.organizationId, draft!);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Issue invoice?'),
          content: SingleChildScrollView(
            child: Text(
              'Taxable ₹${quote['taxable_total']}\nTax ₹${quote['tax_total']}\nTotal ₹${quote['grand_total']}\nDue ${due.text}\n\nPayments:\n${tenders.isEmpty ? 'None — full amount stays due' : tenders.map((tender) => '${tender.method}: ₹${tender.amount.text.trim()}').join('\n')}\n\nIssuing saves the invoice and reduces stock.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Issue invoice'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      final issueData =
          '${draft!.values['id']}|${draft!.values['version']}|$quote|${due.text}';
      if (issueData != issuePayload) {
        issueKey = const Uuid().v4();
        issuePayload = issueData;
      }
      pendingIssue = PendingInvoiceIssue(
        issueKey,
        widget.organizationId,
        draft!,
        quote,
        due.text,
        tenders: tenders.map((tender) => tender.data).toList(),
      );
      await pendingIssue!.send(repo);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Sale could not be completed. Check stock, credit limit and current prices. Reopen a stale draft before retrying.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget picker(
    String label,
    List<SaleOption> options,
    String? value,
    ValueChanged<String?> changed,
  ) => DropdownButtonFormField<String>(
    initialValue: options.any((o) => o.id == value) ? value : null,
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
    onChanged: busy || pendingIssue != null ? null : changed,
    validator: (v) => v == null ? 'Required' : null,
  );
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('New sale'),
      actions: [
        IconButton(
          tooltip: 'Scan product',
          icon: const Icon(Icons.qr_code_scanner),
          onPressed: loading || busy || pendingIssue != null
              ? null
              : () async {
                  final code = await ref.read(barcodeScannerProvider)(context);
                  if (code == null || !mounted || !context.mounted) return;
                  final matches = products
                      .where((p) => p.barcode == code || p.sku == code)
                      .toList();
                  if (matches.length != 1) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          matches.isEmpty
                              ? 'No active product matches this barcode.'
                              : 'Multiple products match. Choose the product manually.',
                        ),
                      ),
                    );
                    return;
                  }
                  setState(() {
                    final empty = lines
                        .where((line) => line.product == null)
                        .firstOrNull;
                    if (empty != null) {
                      empty.product = matches.single.id;
                    } else {
                      lines.add(_SaleLine()..product = matches.single.id);
                    }
                  });
                },
        ),
      ],
    ),
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
                  picker(
                    'Outlet',
                    outlets,
                    outlet,
                    (v) => setState(() => outlet = v),
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile(
                    title: const Text('Walk-in customer'),
                    subtitle: const Text(
                      'Full payment required; no contact record created',
                    ),
                    value: walkIn,
                    onChanged: busy || pendingIssue != null
                        ? null
                        : (value) => setState(() => walkIn = value),
                  ),
                  if (!walkIn)
                    picker(
                      'Customer',
                      customers,
                      customer,
                      (v) => setState(() => customer = v),
                    ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: state,
                    enabled: !busy && pendingIssue == null,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Place of supply state code',
                    ),
                    validator: (v) =>
                        RegExp(r'^\d{2}$').hasMatch(v ?? '') &&
                            (int.tryParse(v!) ?? 0) >= 1 &&
                            (int.tryParse(v) ?? 99) <= 38
                        ? null
                        : 'Use a valid 2-digit code',
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: due,
                    enabled: !busy && pendingIssue == null,
                    decoration: const InputDecoration(
                      labelText: 'Due date (YYYY-MM-DD)',
                    ),
                    validator: (v) =>
                        DateTime.tryParse(v ?? '') != null &&
                            RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v!)
                        ? null
                        : 'Enter a valid date',
                  ),
                  for (final line in lines)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            picker(
                              'Product/service',
                              products,
                              line.product,
                              (v) => setState(() => line.product = v),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: line.qty,
                              enabled: !busy && pendingIssue == null,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Quantity',
                              ),
                              validator: (v) =>
                                  RegExp(
                                        r'^\d+(\.\d{1,3})?$',
                                      ).hasMatch(v ?? '') &&
                                      (num.tryParse(v!) ?? 0) > 0
                                  ? null
                                  : 'Enter a positive quantity',
                            ),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<String>(
                              initialValue: line.kind,
                              decoration: const InputDecoration(
                                labelText: 'Discount type',
                              ),
                              items: ['fixed', 'percent']
                                  .map(
                                    (v) => DropdownMenuItem(
                                      value: v,
                                      child: Text(v),
                                    ),
                                  )
                                  .toList(),
                              onChanged: busy
                                  ? null
                                  : (v) => setState(() => line.kind = v!),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: line.discount,
                              enabled: !busy && pendingIssue == null,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Discount',
                              ),
                              validator: (v) =>
                                  RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v ?? '')
                                  ? null
                                  : 'Invalid discount',
                            ),
                          ],
                        ),
                      ),
                    ),
                  OutlinedButton(
                    onPressed: busy || lines.length >= 100
                        ? null
                        : () => setState(() => lines.add(_SaleLine())),
                    child: const Text('Add line'),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: notes,
                    enabled: !busy && pendingIssue == null,
                    decoration: const InputDecoration(labelText: 'Notes'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Collect now (optional). Remaining balance stays due.',
                  ),
                  for (final tender in tenders)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            DropdownButtonFormField<String>(
                              initialValue: tender.method,
                              decoration: const InputDecoration(
                                labelText: 'Payment method',
                              ),
                              items: ['cash', 'upi', 'card', 'bank', 'other']
                                  .map(
                                    (value) => DropdownMenuItem(
                                      value: value,
                                      child: Text(value),
                                    ),
                                  )
                                  .toList(),
                              onChanged: busy || pendingIssue != null
                                  ? null
                                  : (value) =>
                                        setState(() => tender.method = value!),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: tender.amount,
                              enabled: !busy && pendingIssue == null,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Amount (₹)',
                              ),
                              validator: (value) =>
                                  RegExp(
                                        r'^\d+(\.\d{1,2})?$',
                                      ).hasMatch(value ?? '') &&
                                      (num.tryParse(value!) ?? 0) > 0
                                  ? null
                                  : 'Enter a positive amount',
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: tender.reference,
                              enabled: !busy && pendingIssue == null,
                              decoration: const InputDecoration(
                                labelText: 'Payment reference',
                              ),
                              validator: (value) =>
                                  tender.method != 'cash' &&
                                      (value?.trim().isEmpty ?? true)
                                  ? 'Reference required'
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ),
                  OutlinedButton(
                    onPressed:
                        busy || pendingIssue != null || tenders.length >= 10
                        ? null
                        : () => setState(() => tenders.add(_Tender())),
                    child: const Text('Add payment method'),
                  ),
                  if (tenders.isNotEmpty)
                    TextButton(
                      onPressed: busy || pendingIssue != null
                          ? null
                          : () {
                              final removed = List<_Tender>.from(tenders);
                              setState(tenders.clear);
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                for (final tender in removed) {
                                  tender.dispose();
                                }
                              });
                            },
                      child: const Text('Clear payments'),
                    ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: busy || pendingIssue != null
                        ? null
                        : () => submit(issue: false),
                    child: const Text('Save draft'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: busy ? null : () => submit(issue: true),
                    child: Text(
                      busy
                          ? 'Please wait…'
                          : pendingIssue != null
                          ? 'Retry pending invoice'
                          : 'Review and issue',
                    ),
                  ),
                ],
              ),
            ),
    ),
  );
}

class _Tender {
  String method = 'cash';
  final amount = TextEditingController(), reference = TextEditingController();
  Map<String, String> get data => {
    'method': method,
    'amount': amount.text.trim(),
    'reference': reference.text.trim(),
  };
  void dispose() {
    amount.dispose();
    reference.dispose();
  }
}
