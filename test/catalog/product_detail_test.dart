import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_billing/shared/domain/membership.dart';
import 'package:smart_billing/features/catalog/domain/catalog_repository.dart';
import 'package:smart_billing/features/catalog/domain/product_detail_repository.dart';
import 'package:smart_billing/features/catalog/data/supabase_product_detail_repository.dart';
import 'package:smart_billing/features/catalog/presentation/product_detail_screen.dart';
import 'package:smart_billing/features/search/domain/business_search_repository.dart';
import 'package:smart_billing/features/search/presentation/business_search_screen.dart';

class _Details implements ProductDetailRepository {
  bool fail = false;
  final calls = <String>[];
  @override
  Future<CatalogProduct> load(String org, String product) async {
    calls.add('$org:$product');
    if (fail) throw StateError('Access revoked');
    return CatalogProduct(
      id: product,
      version: 3,
      name: 'Soap',
      type: 'product',
      values: {
        'id': product,
        'type': 'product',
        'name': 'Soap',
        'sku': 'SKU-$product',
        'active': true,
        'price_includes_tax': true,
        'sale_price': 50,
        'purchase_price': 30,
      },
    );
  }
}

class _Search implements BusinessSearchRepository {
  @override
  Future<List<BusinessSearchResult>> search(
    String organizationId,
    SearchCategory category,
    String query,
    int offset,
  ) async => const [
    BusinessSearchResult('first', 'Soap', 'SKU-first'),
    BusinessSearchResult('second', 'Soap', 'SKU-second'),
  ];
}

void main() {
  testWidgets(
    'same-name search results open exact product ID for a read-only cashier',
    (tester) async {
      final details = _Details();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productDetailRepositoryProvider.overrideWithValue(details),
            businessSearchRepositoryProvider.overrideWithValue(_Search()),
          ],
          child: const MaterialApp(
            home: BusinessSearchScreen(
              membership: Membership(
                id: 'member',
                organizationId: 'org',
                organizationName: 'Shop',
                role: OrganizationRole.cashier,
              ),
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Soap');
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Soap').last);
      await tester.pumpAndSettle();
      expect(details.calls, ['org:second']);
      expect(find.text('Product details'), findsOneWidget);
      expect(find.text('SKU-second'), findsOneWidget);
      expect(find.text('Edit product'), findsNothing);
    },
  );
  testWidgets(
    'resume removes stale product data after access is revoked and retry recovers',
    (tester) async {
      final details = _Details();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productDetailRepositoryProvider.overrideWithValue(details),
          ],
          child: const MaterialApp(
            home: ProductDetailScreen(
              organizationId: 'org',
              productId: 'second',
              canManage: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Soap'), findsOneWidget);
      details.fail = true;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Soap'), findsNothing);
      expect(find.text('Edit product'), findsNothing);
      details.fail = false;
      await tester.tap(find.text('Retry product'));
      await tester.pumpAndSettle();
      expect(find.text('Soap'), findsOneWidget);
      expect(details.calls.length, 3);
    },
  );
  testWidgets('product details fit a narrow phone with enlarged text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          productDetailRepositoryProvider.overrideWithValue(_Details()),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: const ProductDetailScreen(
            organizationId: 'org',
            productId: 'second',
            canManage: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Edit product'),
      500,
      scrollable: find
          .descendant(
            of: find.byType(ListView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Prices include tax'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test(
    'product detail HTTP request uses exact tenant and product filters',
    () async {
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        httpClient: MockClient((request) async {
          expect(request.url.queryParameters['organization_id'], 'eq.org');
          expect(request.url.queryParameters['id'], 'eq.second');
          expect(
            request.url.queryParameters['select'],
            contains('price_includes_tax'),
          );
          return http.Response(
            jsonEncode({
              'id': 'second',
              'version': 3,
              'name': 'Soap',
              'type': 'product',
            }),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      addTearDown(client.dispose);
      expect(
        (await SupabaseProductDetailRepository(
          client,
        ).load('org', 'second')).id,
        'second',
      );
    },
  );
}
