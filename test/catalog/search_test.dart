import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/catalog/domain/catalog_repository.dart';
import 'package:smart_billing/features/catalog/presentation/catalog_screen.dart';

class SearchRepository implements CatalogRepository {
  final rice = Completer<List<CatalogProduct>>();
  final queries = <String>[];
  @override
  Future<List<CatalogProduct>> page(
    String org,
    int offset, {
    required bool archived,
    String query = '',
  }) async {
    queries.add(query);
    if (query == 'Rice') return rice.future;
    if (query == 'Tea') {
      return [
        const CatalogProduct(
          id: 'tea',
          version: 1,
          name: 'Tea',
          type: 'product',
          values: {'sale_price': '10', 'unit': 'pcs'},
        ),
      ];
    }
    return [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected mutation');
}

void main() {
  testWidgets('newer server search wins when an older response is delayed', (
    tester,
  ) async {
    final repository = SearchRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [catalogRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          home: CatalogScreen(organizationId: 'org', canManage: false),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Rice');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.enterText(find.byType(TextField), 'Tea');
    await tester.pump(const Duration(milliseconds: 350));
    repository.rice.complete([
      const CatalogProduct(
        id: 'rice',
        version: 1,
        name: 'Rice',
        type: 'product',
        values: {'sale_price': '50', 'unit': 'kg'},
      ),
    ]);
    await tester.pumpAndSettle();
    expect(repository.queries, containsAllInOrder(['', 'Rice', 'Tea']));
    expect(find.text('Tea'), findsWidgets);
    expect(find.text('Rice'), findsNothing);
  });
}
