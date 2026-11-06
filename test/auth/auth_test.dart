import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/features/auth/domain/auth_repository.dart';
import 'package:smart_billing/features/auth/domain/auth_use_cases.dart';
import 'package:smart_billing/features/auth/presentation/auth_providers.dart';
import 'package:smart_billing/features/auth/presentation/auth_screen.dart';

class FakeAuthRepository implements AuthRepository {
  String? lastEmail;
  String? lastPassword;
  int calls = 0;
  Completer<void>? pending;
  @override
  Stream<AppSession?> watchSession() => Stream.value(null);
  @override
  Future<void> signIn(String email, String password) async {
    calls++;
    lastEmail = email;
    lastPassword = password;
    await pending?.future;
  }

  @override
  Future<bool> register(String email, String password) async {
    calls++;
    return false;
  }

  @override
  Future<void> sendRecovery(String email) async {
    calls++;
    lastEmail = email;
  }

  @override
  Future<void> verifyRecovery(String email, String code) async {
    calls++;
  }

  @override
  Future<void> updatePassword(String password) async {
    calls++;
  }

  @override
  Future<void> signOut() async {
    calls++;
  }
}

void main() {
  test('invalid credentials are rejected before repository access', () async {
    final repository = FakeAuthRepository();
    final useCases = AuthUseCases(repository);
    expect(
      () => useCases.signIn('broken', 'password'),
      throwsA(isA<AuthFailure>()),
    );
    expect(
      () => useCases.register('shop@example.com', 'short'),
      throwsA(isA<AuthFailure>()),
    );
    expect(repository.calls, 0);
  });

  test('sign-in preserves passwords while trimming email', () async {
    final repository = FakeAuthRepository();
    await AuthUseCases(repository).signIn(' shop@example.com ', '  password  ');
    expect(repository.lastEmail, 'shop@example.com');
    expect(repository.lastPassword, '  password  ');
  });

  test('recovery code cannot be empty or nonnumeric', () {
    final repository = FakeAuthRepository();
    final useCases = AuthUseCases(repository);
    expect(
      () => useCases.verifyRecovery('shop@example.com', ''),
      throwsA(isA<AuthFailure>()),
    );
    expect(
      () => useCases.verifyRecovery('shop@example.com', 'abcdef'),
      throwsA(isA<AuthFailure>()),
    );
    expect(repository.calls, 0);
  });

  test('controller suppresses concurrent duplicate submissions', () async {
    final repository = FakeAuthRepository()..pending = Completer<void>();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    final controller = container.read(authControllerProvider.notifier);
    final first = controller.signIn('shop@example.com', 'password');
    expect(await controller.signIn('shop@example.com', 'password'), isFalse);
    repository.pending!.complete();
    expect(await first, isTrue);
    expect(repository.calls, 1);
  });

  testWidgets('mobile sign-in validates without sending malformed requests', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.tap(find.byKey(const Key('auth-submit')));
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
    expect(repository.calls, 0);
  });

  testWidgets('auth and recovery fit 360dp with large text and keyboard', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.8),
              viewInsets: const EdgeInsets.only(bottom: 260),
            ),
            child: child!,
          ),
          home: const AuthScreen(),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.text('Recover your account'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
