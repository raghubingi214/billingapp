import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../../../core/env/auth_redirect.dart';
import '../domain/auth_repository.dart';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this.client);
  final SupabaseClient client;
  bool _recovering = false;
  static final redirectUrl = AuthRedirect.resolve(
    isWeb: kIsWeb,
    baseUri: Uri.base,
    override: const String.fromEnvironment('AUTH_REDIRECT_URL'),
  );

  AppSession? _map(Session? session) => session == null
      ? null
      : AppSession(
          userId: session.user.id,
          email: session.user.email ?? '',
          isPasswordRecovery: _recovering,
        );

  static bool _isExpiredLink(Object? error) =>
      error is AuthException && error.statusCode == 'otp_expired';

  @override
  Stream<String> watchLinkFailures() => client.auth.onAuthStateChange.transform(
    StreamTransformer<AuthState, String>.fromHandlers(
      handleData: (_, _) {},
      handleError: (error, _, sink) {
        if (_isExpiredLink(error)) {
          sink.add(
            'This email link has expired or was already used. Request a new email and try again.',
          );
        }
      },
    ),
  );

  @override
  Stream<AppSession?> watchSession() async* {
    // Verify restored identities before exposing them to the app router. Network
    // failures remain a retryable state; they must not silently sign users out.
    if (client.auth.currentSession != null) {
      try {
        await client.auth.getUser();
      } on AuthException catch (error) {
        if (error.statusCode == '401' ||
            error.statusCode == '403' ||
            error.code == 'session_not_found' ||
            error.code == 'refresh_token_not_found') {
          await client.auth.signOut(scope: SignOutScope.local);
        } else {
          throw const AuthFailure(
            'Could not restore your session. Check your connection and retry.',
          );
        }
      } catch (_) {
        throw const AuthFailure(
          'Could not restore your session. Check your connection and retry.',
        );
      }
    }
    yield _map(client.auth.currentSession);
    final events = client.auth.onAuthStateChange.handleError(
      (Object _) {},
      test: _isExpiredLink,
    );
    await for (final event in events) {
      if (event.event == AuthChangeEvent.passwordRecovery) _recovering = true;
      if (event.event == AuthChangeEvent.signedOut) _recovering = false;
      yield _map(event.session);
    }
  }

  Future<T> _run<T>(Future<T> Function() operation, String message) async {
    try {
      return await operation();
    } on AuthException catch (error) {
      if (error.statusCode == '429' ||
          error.code == 'over_request_rate_limit' ||
          error.code == 'over_email_send_rate_limit') {
        throw const AuthFailure(
          'Too many attempts. Please wait a few minutes and try again.',
        );
      }
      throw AuthFailure(message);
    } catch (_) {
      throw const AuthFailure(
        'Unable to connect. Check your internet and try again.',
      );
    }
  }

  @override
  Future<void> signIn(String email, String password) => _run(
    () async {
      _recovering = false;
      await client.auth.signInWithPassword(email: email, password: password);
    },
    'Unable to sign in. Check your details and confirm your email if you recently registered.',
  );

  @override
  Future<bool> register(String email, String password) => _run(() async {
    final response = await client.auth.signUp(
      email: email,
      password: password,
      emailRedirectTo: redirectUrl,
    );
    return response.session != null;
  }, 'Unable to create an account. Check your details or try signing in.');

  @override
  Future<void> resendConfirmation(String email) => _run(() async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: redirectUrl,
    );
  }, 'Unable to request a confirmation email. Please try again later.');

  @override
  Future<void> sendRecovery(String email) => _run(() async {
    await client.auth.resetPasswordForEmail(email, redirectTo: redirectUrl);
  }, 'Unable to request recovery. Please try again later.');

  @override
  Future<void> verifyRecovery(String email, String code) => _run(() async {
    await client.auth.verifyOTP(
      email: email,
      token: code,
      type: OtpType.recovery,
    );
  }, 'This code is invalid or has expired. Request another recovery email.');

  @override
  Future<void> updatePassword(String password) => _run(
    () async {
      await client.auth.updateUser(UserAttributes(password: password));
      await client.auth.signOut(scope: SignOutScope.local);
      _recovering = false;
    },
    'Unable to update your password. Request a new recovery email and try again.',
  );

  @override
  Future<void> signOut() => _run(() async {
    await client.auth.signOut(scope: SignOutScope.local);
    _recovering = false;
  }, 'Unable to sign out. Please try again.');
}
