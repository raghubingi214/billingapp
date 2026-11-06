import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../data/supabase_auth_repository.dart';
import '../domain/auth_repository.dart';
import '../domain/auth_use_cases.dart';

export '../domain/auth_repository.dart' show AppSession;

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(ref.watch(supabaseClientProvider)),
);
final authSessionProvider = StreamProvider<AppSession?>(
  (ref) => ref.watch(authRepositoryProvider).watchSession(),
);
final authUseCasesProvider = Provider(
  (ref) => AuthUseCases(ref.watch(authRepositoryProvider)),
);
final authControllerProvider =
    NotifierProvider<AuthController, AuthActionState>(AuthController.new);

class AuthActionState {
  const AuthActionState({
    this.busy = false,
    this.message,
    this.isError = false,
  });
  final bool busy;
  final String? message;
  final bool isError;
}

class AuthController extends Notifier<AuthActionState> {
  @override
  AuthActionState build() => const AuthActionState();
  void clearMessage() {
    if (!state.busy) state = const AuthActionState();
  }

  Future<bool> _perform(Future<String?> Function() action) async {
    if (state.busy) return false;
    state = const AuthActionState(busy: true);
    try {
      final message = await action();
      if (ref.mounted) state = AuthActionState(message: message);
      return true;
    } on AuthFailure catch (error) {
      if (ref.mounted) {
        state = AuthActionState(message: error.message, isError: true);
      }
    } catch (_) {
      if (ref.mounted) {
        state = const AuthActionState(
          message: 'Something went wrong. Please try again.',
          isError: true,
        );
      }
    }
    return false;
  }

  Future<bool> signIn(String email, String password) => _perform(() async {
    await ref.read(authUseCasesProvider).signIn(email, password);
    return null;
  });
  Future<bool> register(String email, String password) => _perform(() async {
    final signedIn = await ref
        .read(authUseCasesProvider)
        .register(email, password);
    return signedIn
        ? null
        : 'If confirmation is needed, check your email before signing in. If you already have an account, sign in instead.';
  });
  Future<bool> sendRecovery(String email) => _perform(() async {
    await ref.read(authUseCasesProvider).sendRecovery(email);
    return 'If an account matches this email, you will receive recovery instructions. Open the link on this phone, or enter the code if your email includes one.';
  });
  Future<bool> verifyRecovery(String email, String code) => _perform(() async {
    await ref.read(authUseCasesProvider).verifyRecovery(email, code);
    return null;
  });
  Future<bool> updatePassword(String password) => _perform(() async {
    await ref.read(authUseCasesProvider).updatePassword(password);
    return 'Password updated. Sign in with your new password.';
  });
  Future<bool> signOut() => _perform(() async {
    await ref.read(authRepositoryProvider).signOut();
    return null;
  });
}
