import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/auth_use_cases.dart';
import 'auth_providers.dart';

enum _AuthMode { signIn, register, recover }

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key});
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _code = TextEditingController();
  _AuthMode _mode = _AuthMode.signIn;
  bool _showPassword = false;
  bool _emailRequested = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    _code.dispose();
    super.dispose();
  }

  void _changeMode(_AuthMode mode) {
    _form.currentState?.reset();
    setState(() {
      _mode = mode;
      _emailRequested = false;
      _password.clear();
      _confirm.clear();
      _code.clear();
    });
    ref.read(authControllerProvider.notifier).clearMessage();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    final controller = ref.read(authControllerProvider.notifier);
    switch (_mode) {
      case _AuthMode.signIn:
        await controller.signIn(_email.text, _password.text);
      case _AuthMode.register:
        await controller.register(_email.text, _password.text);
      case _AuthMode.recover:
        if (_emailRequested) {
          await controller.verifyRecovery(_email.text, _code.text);
        } else {
          final success = await controller.sendRecovery(_email.text);
          if (mounted && success) setState(() => _emailRequested = true);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(authControllerProvider);
    final theme = Theme.of(context);
    final title = switch (_mode) {
      _AuthMode.signIn => 'Welcome back',
      _AuthMode.register => 'Start your business journey',
      _AuthMode.recover => 'Recover your account',
    };
    final subtitle = switch (_mode) {
      _AuthMode.signIn => 'Sign in to manage your shop.',
      _AuthMode.register => 'Create an account, then set up your business.',
      _AuthMode.recover =>
        'We’ll email you a secure way to reset your password.',
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xff152B49),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(
                            Icons.receipt_long_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'SMART BILLING & INVENTORY',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: const Color(0xff2563EB),
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        title,
                        style: theme.textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: const Color(0xff152B49),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(subtitle, style: theme.textTheme.bodyLarge),
                      const SizedBox(height: 28),
                      TextFormField(
                        key: const Key('auth-email'),
                        controller: _email,
                        enabled: !action.busy,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: _mode == _AuthMode.recover
                            ? TextInputAction.done
                            : TextInputAction.next,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        decoration: const InputDecoration(
                          labelText: 'Email address',
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        validator: AuthValidation.email,
                      ),
                      if (_mode != _AuthMode.recover) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const Key('auth-password'),
                          controller: _password,
                          enabled: !action.busy,
                          obscureText: !_showPassword,
                          enableSuggestions: false,
                          autocorrect: false,
                          autofillHints: [
                            _mode == _AuthMode.register
                                ? AutofillHints.newPassword
                                : AutofillHints.password,
                          ],
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _showPassword
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => AuthValidation.password(
                            value,
                            creating: _mode == _AuthMode.register,
                          ),
                        ),
                      ],
                      if (_mode == _AuthMode.register) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirm,
                          enabled: !action.busy,
                          obscureText: true,
                          autofillHints: const [AutofillHints.newPassword],
                          decoration: const InputDecoration(
                            labelText: 'Confirm password',
                            prefixIcon: Icon(Icons.lock_outline),
                          ),
                          validator: (value) => value == _password.text
                              ? null
                              : 'Passwords do not match',
                        ),
                      ],
                      if (_mode == _AuthMode.signIn)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: action.busy
                                ? null
                                : () => _changeMode(_AuthMode.recover),
                            child: const Text('Forgot password?'),
                          ),
                        ),
                      if (_mode == _AuthMode.recover && _emailRequested) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _code,
                          enabled: !action.busy,
                          keyboardType: TextInputType.number,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          decoration: const InputDecoration(
                            labelText: 'Email code (if provided)',
                            helperText:
                                'You can also open the recovery link on this phone.',
                            helperMaxLines: 3,
                          ),
                          validator: (value) =>
                              value != null &&
                                  RegExp(r'^\d{6,10}$').hasMatch(value.trim())
                              ? null
                              : 'Enter a valid verification code',
                        ),
                      ],
                      if (action.message != null)
                        AuthMessage(
                          message: action.message!,
                          isError: action.isError,
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        key: const Key('auth-submit'),
                        onPressed: action.busy ? null : _submit,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                        ),
                        child: action.busy
                            ? const SizedBox.square(
                                dimension: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(switch (_mode) {
                                _AuthMode.signIn => 'Sign in',
                                _AuthMode.register => 'Create account',
                                _AuthMode.recover =>
                                  _emailRequested
                                      ? 'Verify code'
                                      : 'Send recovery email',
                              }),
                      ),
                      if (_mode == _AuthMode.recover && _emailRequested)
                        TextButton(
                          onPressed: action.busy
                              ? null
                              : () => ref
                                    .read(authControllerProvider.notifier)
                                    .sendRecovery(_email.text),
                          child: const Text('Resend recovery email'),
                        ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: action.busy
                            ? null
                            : () => _changeMode(
                                _mode == _AuthMode.signIn
                                    ? _AuthMode.register
                                    : _AuthMode.signIn,
                              ),
                        child: Text(
                          _mode == _AuthMode.signIn
                              ? 'New here? Create an account'
                              : 'Back to sign in',
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Your business records are available only to authorized members of your business.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AuthMessage extends StatelessWidget {
  const AuthMessage({super.key, required this.message, required this.isError});
  final String message;
  final bool isError;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isError
            ? Theme.of(context).colorScheme.errorContainer
            : const Color(0xffE7F4F1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          color: isError
              ? Theme.of(context).colorScheme.onErrorContainer
              : const Color(0xff152B49),
        ),
      ),
    ),
  );
}
