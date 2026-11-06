import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/widgets/status_view.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../features/onboarding/presentation/onboarding_providers.dart';
import '../shared/domain/membership.dart';
import 'workspace_screen.dart';

/// Revalidate membership before showing cached business state and on resume.
class WorkspaceGate extends ConsumerStatefulWidget {
  const WorkspaceGate({super.key});
  @override
  ConsumerState<WorkspaceGate> createState() => _WorkspaceGateState();
}

class _WorkspaceGateState extends ConsumerState<WorkspaceGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final id = ref.read(authSessionProvider).asData?.value?.userId;
      if (id != null) ref.invalidate(membershipProvider(id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final id = ref.watch(authSessionProvider).asData?.value?.userId;
    if (id == null) return const SizedBox.shrink();
    final selected = ref.watch(activeOrganizationProvider(id));
    if (selected == null) return _accessScreen(context);
    return ref
        .watch(membershipProvider(id))
        .when(
          skipLoadingOnRefresh: false,
          data: (memberships) {
            Membership? current;
            for (final membership in memberships) {
              if (membership.organizationId == selected.organizationId) {
                current = membership;
              }
            }
            if (current == null) return _accessScreen(context);
            return WorkspaceScreen(membership: current);
          },
          loading: () => const Scaffold(
            body: StatusView(
              title: 'Checking access',
              message: 'Loading your business membership…',
              loading: true,
            ),
          ),
          error: (error, stack) => Scaffold(
            body: StatusView(
              title: 'Unable to check access',
              message: 'Check your connection and retry.',
              onAction: () => ref.invalidate(membershipProvider(id)),
            ),
          ),
        );
  }

  Widget _accessScreen(BuildContext context) => Scaffold(
    body: StatusView(
      title: 'Choose a business',
      message: 'Select a business you have access to.',
      actionLabel: 'My businesses',
      onAction: () => context.go('/businesses'),
    ),
  );
}
