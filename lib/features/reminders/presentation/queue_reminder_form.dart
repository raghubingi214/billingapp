import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'reminder_history_screen.dart';
import '../domain/reminder_queue_repository.dart';

class QueueReminderForm extends ConsumerStatefulWidget {
  const QueueReminderForm({
    super.key,
    required this.organizationId,
    required this.invoiceId,
  });
  final String organizationId, invoiceId;
  @override
  ConsumerState<QueueReminderForm> createState() => _QueueState();
}

class _QueueState extends ConsumerState<QueueReminderForm> {
  String channel = 'email';
  String? command, commandChannel, error;
  bool busy = false;
  Future<void> queue() async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Queue overdue reminder?'),
        content: const Text(
          'This records a delivery request. Delivery is not enabled yet. Current consent, contact details and cooldown are checked by the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Queue request'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    if (commandChannel != channel) {
      commandChannel = channel;
      command = const Uuid().v4();
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(reminderQueueRepositoryProvider)
          .queue(command!, widget.organizationId, widget.invoiceId, channel);
      if (!mounted) return;
      command = null;
      commandChannel = null;
      ref.invalidate(reminderHistoryProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reminder queued. No message has been sent.'),
        ),
      );
    } on ReminderQueueFailure catch (failure) {
      if (mounted) setState(() => error = failure.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Could not confirm queueing. Check consent, overdue balance and cooldown, then retry unchanged details.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DropdownButtonFormField<String>(
        initialValue: channel,
        decoration: const InputDecoration(labelText: 'Reminder channel'),
        items: const {'email': 'Email', 'sms': 'SMS', 'whatsapp': 'WhatsApp'}
            .entries
            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
            .toList(),
        onChanged: busy ? null : (value) => setState(() => channel = value!),
      ),
      if (error != null) Text(error!),
      OutlinedButton(
        onPressed: busy ? null : queue,
        child: Text(busy ? 'Queueing…' : 'Queue overdue reminder'),
      ),
    ],
  );
}
