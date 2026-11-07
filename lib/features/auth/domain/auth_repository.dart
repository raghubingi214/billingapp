class AppSession {
  const AppSession({
    required this.userId,
    required this.email,
    this.isPasswordRecovery = false,
  });
  final String userId;
  final String email;
  final bool isPasswordRecovery;
  String get id => userId;
}

class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class AuthRepository {
  Stream<AppSession?> watchSession();
  Stream<String> watchLinkFailures();
  Future<void> signIn(String email, String password);
  Future<bool> register(String email, String password);
  Future<void> resendConfirmation(String email);
  Future<void> sendRecovery(String email);
  Future<void> verifyRecovery(String email, String code);
  Future<void> updatePassword(String password);
  Future<void> signOut();
}
