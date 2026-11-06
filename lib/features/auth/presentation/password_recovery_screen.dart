import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../domain/auth_use_cases.dart';
import 'auth_providers.dart';
import 'auth_screen.dart';

class PasswordRecoveryScreen extends ConsumerStatefulWidget {
  const PasswordRecoveryScreen({super.key});
  @override
  ConsumerState<PasswordRecoveryScreen> createState() =>
      _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState
    extends ConsumerState<PasswordRecoveryScreen> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Choose a new password',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'After saving, sign in again with your new password.',
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _password,
                      enabled: !action.busy,
                      obscureText: true,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: const InputDecoration(
                        labelText: 'New password',
                      ),
                      validator: (value) =>
                          AuthValidation.password(value, creating: true),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirm,
                      enabled: !action.busy,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Confirm new password',
                      ),
                      validator: (value) => value == _password.text
                          ? null
                          : 'Passwords do not match',
                    ),
                    if (action.message != null)
                      AuthMessage(
                        message: action.message!,
                        isError: action.isError,
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: action.busy
                          ? null
                          : () async {
                              if (_form.currentState!.validate()) {
                                await ref
                                    .read(authControllerProvider.notifier)
                                    .updatePassword(_password.text);
                              }
                            },
                      child: Text(action.busy ? 'Saving…' : 'Save password'),
                    ),
                    TextButton(
                      onPressed: action.busy
                          ? null
                          : () => ref
                                .read(authControllerProvider.notifier)
                                .signOut(),
                      child: const Text('Cancel and sign out'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
