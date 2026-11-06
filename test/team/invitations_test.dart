import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/team/domain/team_repository.dart';
import 'package:smart_billing/features/team/presentation/invitations_screen.dart';
import 'package:smart_billing/features/onboarding/presentation/onboarding_providers.dart';
import 'package:smart_billing/shared/domain/membership.dart';

class FakeTeamRepository implements TeamRepository {
  int accepts = 0, invites = 0;
  @override
  Future<List<TeamInvitation>> invitations({String? organizationId}) async => [
    const TeamInvitation(
      id: 'invite-a',
      email: 'staff@example.com',
      role: 'cashier',
      status: 'pending',
    ),
  ];
  @override
  Future<void> accept(String invitationId) async {
    accepts++;
  }

  @override
  Future<void> invite(
    String requestId,
    String organizationId,
    String email,
    String role,
  ) async {
    invites++;
  }

  @override
  Future<void> revoke(
    String requestId,
    String organizationId,
    String invitationId,
  ) async {}
}

void main() {
  test(
    'selection survives route listener gaps and stays separate by identity',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const membership = Membership(
        id: 'membership',
        organizationId: 'org-a',
        organizationName: 'Shop A',
        role: OrganizationRole.owner,
      );
      container
          .read(activeOrganizationProvider('user-a').notifier)
          .select(membership);
      await container.pump();
      expect(container.read(activeOrganizationProvider('user-a')), membership);
      expect(container.read(activeOrganizationProvider('user-b')), isNull);
      container.invalidate(activeOrganizationProvider('user-a'));
      expect(container.read(activeOrganizationProvider('user-a')), isNull);
    },
  );

  testWidgets('recipient acceptance refreshes memberships through callback', (
    tester,
  ) async {
    final repository = FakeTeamRepository();
    var refreshes = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [teamRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: InvitationsScreen(onAccepted: () => refreshes++),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(repository.accepts, 1);
    expect(refreshes, 1);
  });

  testWidgets('owner cannot submit malformed invitation email', (tester) async {
    final repository = FakeTeamRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [teamRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          home: InvitationsScreen(organizationId: 'org-a', onAccepted: () {}),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'broken');
    await tester.tap(find.text('Create invitation'));
    await tester.pumpAndSettle();
    expect(repository.invites, 0);
    expect(find.text('Enter a valid email.'), findsOneWidget);
  });
}
