import 'auth_repository.dart';

class AuthValidation {
  static String? email(String? value) =>
      value != null &&
          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
      ? null
      : 'Enter a valid email address';
  static String? password(String? value, {bool creating = false}) {
    if (value == null || value.isEmpty) return 'Enter your password';
    if (creating && value.length < 8) return 'Use at least 8 characters';
    return null;
  }
}

class AuthUseCases {
  const AuthUseCases(this.repository);
  final AuthRepository repository;

  void _validate(String email, String password, {bool creating = false}) {
    final error =
        AuthValidation.email(email) ??
        AuthValidation.password(password, creating: creating);
    if (error != null) throw AuthFailure(error);
  }

  Future<void> signIn(String email, String password) {
    _validate(email, password);
    return repository.signIn(email.trim(), password);
  }

  Future<bool> register(String email, String password) {
    _validate(email, password, creating: true);
    return repository.register(email.trim(), password);
  }

  Future<void> sendRecovery(String email) {
    final error = AuthValidation.email(email);
    if (error != null) throw AuthFailure(error);
    return repository.sendRecovery(email.trim());
  }

  Future<void> verifyRecovery(String email, String code) {
    final error = AuthValidation.email(email);
    if (error != null) throw AuthFailure(error);
    if (!RegExp(r'^\d{6,10}$').hasMatch(code.trim())) {
      throw const AuthFailure('Enter the verification code from your email');
    }
    return repository.verifyRecovery(email.trim(), code.trim());
  }

  Future<void> updatePassword(String password) {
    final error = AuthValidation.password(password, creating: true);
    if (error != null) throw AuthFailure(error);
    return repository.updatePassword(password);
  }
}
