import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_billing/shared/domain/membership.dart';
import 'package:smart_billing/features/search/domain/business_search_repository.dart';
import 'package:smart_billing/features/search/data/supabase_business_search_repository.dart';
import 'package:smart_billing/features/search/presentation/business_search_screen.dart';

class _Search implements BusinessSearchRepository {
  final pending = <Completer<List<BusinessSearchResult>>>[];
  final orgs = <String>[];
  @override
  Future<List<BusinessSearchResult>> search(
    String org,
    SearchCategory category,
    String query,
    int offset,
  ) {
    orgs.add(org);
    final reply = Completer<List<BusinessSearchResult>>();
    pending.add(reply);
    return reply.future;
  }
}

Widget _app(
  _Search repository, {
  String org = 'org-a',
  OrganizationRole role = OrganizationRole.owner,
}) => ProviderScope(
  overrides: [businessSearchRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    home: BusinessSearchScreen(
      membership: Membership(
        id: 'member',
        organizationId: org,
        organizationName: org,
        role: role,
      ),
    ),
  ),
);

void main() {
  testWidgets(
    'changed query ignores delayed response and business switch clears results',
    (tester) async {
      final repository = _Search();
      await tester.pumpWidget(_app(repository));
      await tester.enterText(find.byType(TextField), 'old');
      await tester.tap(find.text('Search'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'new');
      await tester.pump();
      await tester.tap(find.text('Search'));
      await tester.pump();
      repository.pending[1].complete([
        const BusinessSearchResult('new-id', 'New result', ''),
      ]);
      await tester.pumpAndSettle();
      repository.pending[0].complete([
        const BusinessSearchResult('old-id', 'Old result', ''),
      ]);
      await tester.pumpAndSettle();
      expect(find.text('New result'), findsOneWidget);
      expect(find.text('Old result'), findsNothing);
      await tester.pumpWidget(_app(repository, org: 'org-b'));
      await tester.pumpAndSettle();
      expect(find.text('New result'), findsNothing);
      await tester.enterText(find.byType(TextField), 'other');
      await tester.tap(find.text('Search'));
      await tester.pump();
      expect(repository.orgs, ['org-a', 'org-a', 'org-b']);
      repository.pending.last.complete([]);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'cashier search hides customers and short query never requests data',
    (tester) async {
      final repository = _Search();
      await tester.pumpWidget(_app(repository, role: OrganizationRole.cashier));
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      expect(repository.pending, isEmpty);
      await tester.tap(find.byType(DropdownButtonFormField<SearchCategory>));
      await tester.pumpAndSettle();
      expect(find.text('Customers'), findsNothing);
      expect(find.text('Invoices'), findsWidgets);
    },
  );

  test('HTTP searches retain tenant filters and bounded paging', () async {
    final requests = <http.Request>[];
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    addTearDown(client.dispose);
    final repository = SupabaseBusinessSearchRepository(client);
    await repository.search('tenant-a', SearchCategory.invoices, 'INV_%', 50);
    final uri = requests.single.url;
    expect(uri.path, endsWith('/sales_invoices'));
    expect(uri.queryParameters['organization_id'], 'eq.tenant-a');
    expect(uri.queryParameters['invoice_number'], r'ilike.%INV\_\%%');
    expect(uri.queryParameters['offset'], '50');
    expect(uri.queryParameters['limit'], '50');
    await repository.search('tenant-b', SearchCategory.customers, 'Green', 0);
    expect(requests.last.url.queryParameters['organization_id'], 'eq.tenant-b');
    await repository.search('tenant-c', SearchCategory.products, '000123', 0);
    expect(jsonDecode(requests.last.body)['p_organization_id'], 'tenant-c');
    expect(jsonDecode(requests.last.body)['p_query'], '000123');
  });
}
