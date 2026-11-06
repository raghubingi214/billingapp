import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/customer_repository.dart';
import '../data/supabase_customer_repository.dart';
import 'customer_ledger_screen.dart';
import '../../reminders/presentation/reminder_consent_screen.dart';

final customerRepositoryProvider = Provider<CustomerRepository>(
  (ref) => SupabaseCustomerRepository(ref.watch(supabaseClientProvider)),
);

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({
    super.key,
    required this.organizationId,
    required this.canManage,
  });
  final String organizationId;
  final bool canManage;
  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  List<Customer> rows = [];
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
          .read(customerRepositoryProvider)
          .page(widget.organizationId, rows.length);
      if (mounted) {
        setState(() {
          rows = [...rows, ...page];
          more = page.length == 50;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => error = 'Unable to load customers. Retry.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(Customer? customer) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => CustomerEditor(
          organizationId: widget.organizationId,
          customer: customer,
        ),
      ),
    );
    if (saved == true && mounted) load(reset: true);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Customers')),
    floatingActionButton: widget.canManage
        ? FloatingActionButton(
            tooltip: 'Add customer',
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
            if (!busy && rows.isEmpty)
              const ListTile(title: Text('No customers yet')),
            for (final customer in rows)
              Card(
                child: ListTile(
                  title: Text(customer.name),
                  leading: widget.canManage
                      ? IconButton(
                          tooltip: 'Reminder consent',
                          icon: const Icon(Icons.notifications_outlined),
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => ReminderConsentScreen(
                                organizationId: widget.organizationId,
                                customerId: customer.id,
                                customerName: customer.name,
                              ),
                            ),
                          ),
                        )
                      : null,
                  trailing: IconButton(
                    tooltip: 'Customer ledger',
                    icon: const Icon(Icons.account_balance_outlined),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CustomerLedgerScreen(
                          organizationId: widget.organizationId,
                          customerId: customer.id,
                        ),
                      ),
                    ),
                  ),
                  subtitle: Text(
                    '${customer.values['phone']} · State ${customer.values['state_code']}',
                  ),
                  onTap: widget.canManage ? () => edit(customer) : null,
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

class CustomerEditor extends ConsumerStatefulWidget {
  const CustomerEditor({
    super.key,
    required this.organizationId,
    this.customer,
  });
  final String organizationId;
  final Customer? customer;
  @override
  ConsumerState<CustomerEditor> createState() => _CustomerEditorState();
}

class _CustomerEditorState extends ConsumerState<CustomerEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  String requestId = const Uuid().v4(), lastPayload = '';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    for (final key in [
      'name',
      'phone',
      'email',
      'gstin',
      'state_code',
      'billing_address',
      'shipping_address',
      'credit_limit',
    ]) {
      fields[key] = TextEditingController(
        text: widget.customer?.values[key]?.toString() ?? '',
      );
    }
  }

  @override
  void dispose() {
    for (final field in fields.values) {
      field.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    final values = <String, Object?>{
      for (final field in fields.entries) field.key: field.value.text.trim(),
      'active': widget.customer?.values['active'] ?? true,
    };
    if (values.toString() != lastPayload) {
      requestId = const Uuid().v4();
      lastPayload = values.toString();
    }
    setState(() => busy = true);
    try {
      await ref
          .read(customerRepositoryProvider)
          .save(requestId, widget.organizationId, widget.customer, values);
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to save customer. Check tax/address details and access; reopen if edited elsewhere.',
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
      title: Text(widget.customer == null ? 'Add customer' : 'Edit customer'),
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
                enabled: !busy,
                decoration: InputDecoration(
                  labelText: {
                    'name': 'Customer name',
                    'phone': 'Phone (optional)',
                    'email': 'Email (optional)',
                    'gstin': 'GSTIN (optional)',
                    'state_code': 'State code (2 digits)',
                    'billing_address': 'Billing address',
                    'shipping_address': 'Shipping address',
                    'credit_limit': 'Credit limit (₹, optional)',
                  }[field.key],
                ),
                keyboardType: ['state_code', 'credit_limit'].contains(field.key)
                    ? const TextInputType.numberWithOptions(decimal: true)
                    : TextInputType.text,
                validator: (v) {
                  final value = v?.trim() ?? '';
                  if (field.key == 'name' && value.isEmpty) return 'Required';
                  if (field.key == 'state_code' &&
                      (!RegExp(r'^\d{2}$').hasMatch(value) ||
                          (int.tryParse(value) ?? 0) < 1 ||
                          (int.tryParse(value) ?? 99) > 38)) {
                    return 'Use a valid 2-digit state code';
                  }
                  if (field.key == 'credit_limit' &&
                      value.isNotEmpty &&
                      !RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(value)) {
                    return 'Use up to two decimals';
                  }
                  if (field.key == 'email' &&
                      value.isNotEmpty &&
                      !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
                    return 'Enter a valid email';
                  }
                  if (field.key == 'gstin' &&
                      value.isNotEmpty &&
                      (!RegExp(
                            r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
                          ).hasMatch(value.toUpperCase()) ||
                          !value.startsWith(fields['state_code']!.text))) {
                    return 'GSTIN must match the state';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
            ],
            FilledButton(
              onPressed: busy ? null : save,
              child: Text(busy ? 'Saving…' : 'Save customer'),
            ),
          ],
        ),
      ),
    ),
  );
}
