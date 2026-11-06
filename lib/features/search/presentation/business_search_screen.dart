import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/domain/membership.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/business_search_repository.dart';
import '../data/supabase_business_search_repository.dart';
import '../../sales/presentation/sales_screen.dart';
import '../../customers/presentation/customer_ledger_screen.dart';
import '../../catalog/presentation/product_detail_screen.dart';

final businessSearchRepositoryProvider = Provider<BusinessSearchRepository>(
  (ref) => SupabaseBusinessSearchRepository(ref.watch(supabaseClientProvider)),
);

class BusinessSearchScreen extends ConsumerStatefulWidget {
  const BusinessSearchScreen({super.key, required this.membership});
  final Membership membership;
  @override
  ConsumerState<BusinessSearchScreen> createState() => _SearchState();
}

class _SearchState extends ConsumerState<BusinessSearchScreen> {
  final query = TextEditingController();
  SearchCategory category = SearchCategory.products;
  List<BusinessSearchResult> rows = [];
  bool busy = false, searched = false, more = false;
  String? error;
  int generation = 0;
  void invalidate() {
    generation++;
    rows = [];
    busy = false;
    searched = false;
    more = false;
    error = null;
  }

  @override
  void didUpdateWidget(BusinessSearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.membership.organizationId !=
            widget.membership.organizationId ||
        oldWidget.membership.role != widget.membership.role) {
      query.clear();
      category = SearchCategory.products;
      invalidate();
    }
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  Future<void> search({bool reset = true}) async {
    final text = query.text.trim();
    if (text.length < 2 || text.length > 100) {
      setState(() => error = 'Enter 2–100 characters to search');
      return;
    }
    if (busy) return;
    final request = ++generation;
    final selected = category;
    setState(() {
      busy = true;
      error = null;
      if (reset) rows = [];
    });
    try {
      final page = await ref
          .read(businessSearchRepositoryProvider)
          .search(
            widget.membership.organizationId,
            selected,
            text,
            rows.length,
          );
      if (!mounted || request != generation) return;
      setState(() {
        rows = [...rows, ...page];
        more = page.length == 50;
        searched = true;
      });
    } catch (_) {
      if (mounted && request == generation) {
        setState(
          () =>
              error = 'Unable to search. Check your business access and retry.',
        );
      }
    } finally {
      if (mounted && request == generation) setState(() => busy = false);
    }
  }

  void open(BusinessSearchResult result) {
    final member = widget.membership;
    final selected = category;
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => switch (selected) {
          SearchCategory.invoices => SalesDetailScreen(
            organizationId: member.organizationId,
            invoiceId: result.id,
            canCollect: member.role != OrganizationRole.accountant,
            canReturn: member.role == OrganizationRole.owner,
            canRemind: member.role != OrganizationRole.cashier,
          ),
          SearchCategory.customers => CustomerLedgerScreen(
            organizationId: member.organizationId,
            customerId: result.id,
          ),
          SearchCategory.products => ProductDetailScreen(
            organizationId: member.organizationId,
            productId: result.id,
            canManage: [
              OrganizationRole.owner,
              OrganizationRole.manager,
            ].contains(member.role),
          ),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Search business')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<SearchCategory>(
            key: ValueKey(category),
            initialValue: category,
            decoration: const InputDecoration(labelText: 'Search in'),
            items: [
              for (final value in SearchCategory.values)
                if (value != SearchCategory.customers ||
                    widget.membership.role != OrganizationRole.cashier)
                  DropdownMenuItem(
                    value: value,
                    child: Text(switch (value) {
                      SearchCategory.products => 'Products',
                      SearchCategory.invoices => 'Invoices',
                      SearchCategory.customers => 'Customers',
                    }),
                  ),
            ],
            isExpanded: true,
            onChanged: (value) => setState(() {
              category = value!;
              invalidate();
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: query,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Search text'),
            textInputAction: TextInputAction.search,
            onChanged: (_) => setState(invalidate),
            onSubmitted: (_) => search(),
          ),
          FilledButton(
            onPressed: busy ? null : () => search(),
            child: const Text('Search'),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) ...[
            Text(error!),
            TextButton(
              onPressed: busy ? null : () => search(reset: rows.isEmpty),
              child: const Text('Retry search'),
            ),
          ],
          if (!busy && searched && error == null && rows.isEmpty)
            const Text('No matching records'),
          for (final row in rows)
            Card(
              child: ListTile(
                title: Text(row.title),
                subtitle: Text(row.subtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: busy ? null : () => open(row),
              ),
            ),
          if (more && !busy && error == null)
            TextButton(
              onPressed: () => search(reset: false),
              child: const Text('Load more'),
            ),
        ],
      ),
    ),
  );
}
