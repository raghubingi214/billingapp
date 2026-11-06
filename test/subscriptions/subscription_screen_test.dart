import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/subscriptions/domain/subscription_repository.dart';
import 'package:smart_billing/features/subscriptions/presentation/subscription_screen.dart';

class _Repository implements SubscriptionRepository {
  bool fail = false;
  Map<String, dynamic> data = {'status': 'unconfigured'};
  final organizations = <String>[];
  @override
  Future<Map<String, dynamic>> summary(String organizationId) async {
    organizations.add(organizationId);
    if (fail) throw StateError('Unavailable');
    return data;
  }
}

void main() {
  testWidgets('resume refreshes configured plan and usage', (tester) async {
    final repository = _Repository()
      ..data = {
        'status': 'active',
        'plan_name': 'Example plan',
        'price_inr': 100,
        'billing_interval': 'month',
        'period_end': '2026-12-01T00:00:00Z',
        'limits': {'invoices': 100, 'staff': 3, 'locations': 1, 'reports': []},
        'usage': {'invoices': 4, 'staff': 2, 'locations': 1},
      };
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: SubscriptionScreen(organizationId: 'business-a'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Status: Active'), findsOneWidget);
    expect(find.text('Invoices this month: 4 / 100'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    repository.data = {'status': 'unconfigured'};
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('Example plan'), findsNothing);
    expect(find.text('No subscription assigned'), findsOneWidget);
    expect(repository.organizations.length, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('owner can retry a failed load on narrow large-text screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _Repository()..fail = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const SubscriptionScreen(organizationId: 'business-a'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Retry subscription'), findsOneWidget);
    repository.fail = false;
    await tester.tap(find.text('Retry subscription'));
    await tester.pumpAndSettle();
    expect(find.text('No subscription assigned'), findsOneWidget);
    expect(repository.organizations.length, 2);
    expect(tester.takeException(), isNull);
  });
  testWidgets('unconfigured business shows honest plan state', (tester) async {
    final repository = _Repository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          subscriptionRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: SubscriptionScreen(organizationId: 'business-a'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No subscription assigned'), findsOneWidget);
    expect(repository.organizations, ['business-a']);
    expect(find.textContaining('Unlimited'), findsNothing);
  });
}
