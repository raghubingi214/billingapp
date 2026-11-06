import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/app/workspace_screen.dart';
import 'package:smart_billing/app/theme/app_theme.dart';
import 'package:smart_billing/shared/domain/membership.dart';
import 'package:smart_billing/features/dashboard/domain/dashboard_repository.dart';
import 'package:smart_billing/features/dashboard/presentation/dashboard_panel.dart';

class FakeDashboard implements DashboardRepository {
  @override
  Future<DashboardSummary> summary(String org, String from, String to) async =>
      const DashboardSummary('0', '0', '0', 0, '2026-11-05T10:00:00Z', false);
}

void main() {
  Widget app(OrganizationRole role, {String org = 'org-a'}) => ProviderScope(
    overrides: [dashboardRepositoryProvider.overrideWithValue(FakeDashboard())],
    child: MaterialApp(
      theme: AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: const TextScaler.linear(1.6)),
        child: child!,
      ),
      home: WorkspaceScreen(
        membership: Membership(
          id: 'member',
          organizationId: org,
          organizationName: org,
          role: role,
        ),
      ),
    ),
  );
  testWidgets(
    'phone navigation supports large text and accountant has no New Sale',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(app(OrganizationRole.accountant));
      await tester.pumpAndSettle();
      expect(find.byType(NavigationDestination), findsNWidgets(4));
      expect(find.text('New Sale'), findsNothing);
      await tester.tap(find.text('More'));
      await tester.pumpAndSettle();
      expect(find.text('Business tools'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('owner sale action is visible and business switch resets tab', (
    tester,
  ) async {
    await tester.pumpWidget(app(OrganizationRole.owner));
    await tester.pumpAndSettle();
    expect(find.text('New Sale'), findsOneWidget);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      3,
    );
    await tester.pumpWidget(app(OrganizationRole.owner, org: 'org-b'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      0,
    );
    expect(find.text('org-b'), findsOneWidget);
  });
}
