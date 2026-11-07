import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/team/presentation/role_permissions_screen.dart';
import 'package:smart_billing/shared/domain/membership.dart';

void main() {
  testWidgets('role guide separates platform and business roles on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.8)),
          child: child!,
        ),
        home: const RolePermissionsScreen(
          isPlatformAdmin: true,
          membership: Membership(
            id: 'membership',
            organizationId: 'demo',
            organizationName: 'Demo Shop',
            role: OrganizationRole.owner,
          ),
        ),
      ),
    );

    expect(find.text('Your platform role: Superadmin'), findsOneWidget);
    final businessRole = find.text('Your role in Demo Shop: Owner');
    await tester.scrollUntilVisible(businessRole, 180);
    expect(businessRole, findsOneWidget);
    for (final role in [
      'Superadmin',
      'Business Owner',
      'Manager',
      'Cashier',
      'Accountant',
    ]) {
      await tester.scrollUntilVisible(find.text(role), 220);
      expect(find.text(role), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });
}
