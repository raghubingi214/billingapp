import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/status_view.dart';
import '../../features/auth/presentation/auth_providers.dart';
import '../../features/auth/presentation/auth_screen.dart';
import '../../features/auth/presentation/password_recovery_screen.dart';
import '../../features/onboarding/presentation/onboarding_providers.dart';
import '../../features/onboarding/presentation/onboarding_screen.dart';
import '../../features/onboarding/presentation/organization_picker_screen.dart';
import '../workspace_gate.dart';

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefresh();
  ref.listen(authSessionProvider, (previous, next) {
    final oldId = previous?.asData?.value?.userId;
    final newId = next.asData?.value?.userId;
    if (oldId != null && oldId != newId) {
      ref.invalidate(activeOrganizationProvider(oldId));
      ref.invalidate(membershipProvider(oldId));
    }
    refresh.update();
  });
  final router = GoRouter(
    initialLocation: '/startup',
    refreshListenable: refresh,
    redirect: (context, state) {
      final session = ref.read(authSessionProvider);
      if (session.isLoading || session.hasError) {
        return state.uri.path == '/startup' ? null : '/startup';
      }
      final user = session.asData?.value;
      if (user == null) {
        return state.uri.path == '/sign-in' ? null : '/sign-in';
      }
      if (user.isPasswordRecovery) {
        return state.uri.path == '/reset-password' ? null : '/reset-password';
      }
      if ([
        '/startup',
        '/sign-in',
        '/reset-password',
      ].contains(state.uri.path)) {
        return '/businesses';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/startup',
        builder: (context, state) => const _StartupScreen(),
      ),
      GoRoute(
        path: '/sign-in',
        builder: (context, state) => const AuthScreen(),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (context, state) => const PasswordRecoveryScreen(),
      ),
      GoRoute(
        path: '/businesses',
        builder: (context, state) {
          final id = ref.read(authSessionProvider).asData?.value?.userId;
          if (id == null) return const _StartupScreen();
          return OrganizationPickerScreen(
            userId: id,
            onSelected: (membership) {
              ref
                  .read(activeOrganizationProvider(id).notifier)
                  .select(membership);
              context.go('/home');
            },
            onCreate: () => context.go('/onboarding'),
            onSignOut: () {
              ref.read(authControllerProvider.notifier).signOut();
            },
          );
        },
      ),
      GoRoute(
        path: '/onboarding',
        builder: (context, state) {
          final id = ref.read(authSessionProvider).asData?.value?.userId;
          if (id == null) return const _StartupScreen();
          return OnboardingScreen(
            userId: id,
            onCompleted: () {
              ref.invalidate(membershipProvider(id));
              context.go('/businesses');
            },
          );
        },
      ),
      GoRoute(
        path: '/home',
        builder: (context, state) => const WorkspaceGate(),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: StatusView(
        title: 'Page unavailable',
        message: 'Return to your businesses to continue.',
        actionLabel: 'My businesses',
        onAction: () => context.go('/businesses'),
      ),
    ),
  );
  ref.onDispose(() {
    router.dispose();
    refresh.dispose();
  });
  return router;
});

class _RouterRefresh extends ChangeNotifier {
  void update() => notifyListeners();
}

class _StartupScreen extends ConsumerWidget {
  const _StartupScreen();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authSessionProvider);
    return Scaffold(
      body: StatusView(
        title: session.hasError ? 'Unable to restore session' : 'Smart Billing',
        message: session.hasError
            ? 'Check your connection and try again.'
            : 'Restoring your workspace…',
        loading: !session.hasError,
        onAction: session.hasError
            ? () => ref.invalidate(authSessionProvider)
            : null,
      ),
    );
  }
}
