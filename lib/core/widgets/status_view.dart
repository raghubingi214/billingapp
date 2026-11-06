import 'package:flutter/material.dart';

class StatusView extends StatelessWidget {
  const StatusView({
    super.key,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.loading = false,
  });
  final String title, message;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool loading;
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const CircularProgressIndicator()
              else
                const Icon(Icons.storefront_outlined, size: 48),
              const SizedBox(height: 24),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              if (onAction != null) ...[
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: onAction,
                  child: Text(actionLabel ?? 'Retry'),
                ),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}
