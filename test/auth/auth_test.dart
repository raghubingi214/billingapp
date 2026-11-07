import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_billing/features/auth/data/supabase_auth_repository.dart';
import 'package:smart_billing/features/auth/domain/auth_repository.dart';
import 'package:smart_billing/features/auth/domain/auth_use_cases.dart';
import 'package:smart_billing/features/auth/presentation/auth_providers.dart';
import 'package:smart_billing/features/auth/presentation/auth_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAuthRepository implements AuthRepository {
  String? lastEmail;
  String? lastPassword;
  int calls = 0;
  Completer<void>? pending;
  @override
  Stream<AppSession?> watchSession() => Stream.value(null);
  @override
  Stream<String> watchLinkFailures() => const Stream.empty();
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
  Future<void> resendConfirmation(String email) async {
    calls++;
    lastEmail = email;
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
  test(
    'confirmation resend sends a signup request with the app callback',
    () async {
      SharedPreferences.setMockInitialValues({});
      late http.Request resend;
      final client = SupabaseClient(
        'https://example.invalid',
        'test-key',
        authOptions: AuthClientOptions(
          autoRefreshToken: false,
          pkceAsyncStorage: SharedPreferencesGotrueAsyncStorage(),
        ),
        httpClient: MockClient((request) async {
          resend = request;
          return http.Response('{}', 200);
        }),
      );
      addTearDown(client.dispose);
      await SupabaseAuthRepository(
        client,
      ).resendConfirmation('shop@example.com');
      expect(resend.method, 'POST');
      expect(resend.url.path, '/auth/v1/resend');
      expect(
        resend.url.queryParameters['redirect_to'],
        'smartbilling://auth-callback',
      );
      final body = jsonDecode(resend.body) as Map<String, dynamic>;
      expect(body['email'], 'shop@example.com');
      expect(body['type'], 'signup');
      expect(body['code_challenge'], isNotEmpty);
    },
  );

  testWidgets('confirmation resend needs a valid email and no password', (
    tester,
  ) async {
    final repository = FakeAuthRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    final resend = find.text('Resend confirmation email');
    await tester.ensureVisible(resend);
    await tester.tap(resend);
    await tester.pumpAndSettle();
    final submit = find.byKey(const Key('auth-submit'));
    expect(find.byKey(const Key('auth-password')), findsNothing);
    await tester.tap(submit);
    await tester.pump();
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(repository.calls, 0);
    await tester.enterText(
      find.byKey(const Key('auth-email')),
      ' shop@example.com ',
    );
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(repository.calls, 1);
    expect(repository.lastEmail, 'shop@example.com');
    expect(find.textContaining('Open the latest email'), findsOneWidget);
  });

  testWidgets('expired callback keeps sign-in open and explains what to do', (
    tester,
  ) async {
    final client = (await tester.runAsync(
      () async => SupabaseClient(
        'https://example.invalid',
        'test-key',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
      ),
    ))!;
    final repository = SupabaseAuthRepository(client);
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(() async {
      container.dispose();
      await client.dispose();
    });
    final session = container.listen(authSessionProvider, (_, _) {});
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();
    // Exercise the SDK callback parser and the error channel used by Flutter.
    try {
      await client.auth.getSessionFromUrl(
        Uri.parse(
          'smartbilling://auth-callback#error=access_denied&error_code=otp_expired',
        ),
      );
      fail('The test link should be rejected');
    } on AuthException catch (error) {
      // ignore: invalid_use_of_internal_member
      client.auth.notifyException(error);
    }
    await tester.pumpAndSettle();
    expect(session.read(), const AsyncData<AppSession?>(null));
    expect(find.text('Sign in'), findsOneWidget);
    expect(
      find.text(
        'This email link has expired or was already used. Request a new email and try again.',
      ),
      findsOneWidget,
    );
  });

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
