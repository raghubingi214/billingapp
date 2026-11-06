import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/sales/domain/draft_repository.dart';
import 'package:smart_billing/features/sales/presentation/drafts_screen.dart';

class WalkInRepository implements DraftRepository {
  @override
  Future<List<SaleOption>> options(String org, String type) async =>
      type == 'customers' ? [] : [SaleOption(type, 'Test $type')];
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected mutation');
}

void main() {
  testWidgets('walk-in selection removes mandatory customer picker', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          draftRepositoryProvider.overrideWithValue(WalkInRepository()),
        ],
        child: const MaterialApp(home: SaleEditor(organizationId: 'org')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Customer'), findsOneWidget);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Customer'), findsNothing);
    expect(
      find.text('Full payment required; no contact record created'),
      findsOneWidget,
    );
  });
}
