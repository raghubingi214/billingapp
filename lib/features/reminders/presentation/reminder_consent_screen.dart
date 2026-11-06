import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../data/supabase_reminder_consent_repository.dart';
import '../domain/reminder_consent_repository.dart';

final reminderConsentRepositoryProvider = Provider<ReminderConsentRepository>(
  (ref) => SupabaseReminderConsentRepository(ref.watch(supabaseClientProvider)),
);

class ReminderConsentScreen extends ConsumerStatefulWidget {
  const ReminderConsentScreen({
    super.key,
    required this.organizationId,
    required this.customerId,
    required this.customerName,
  });
  final String organizationId, customerId, customerName;
  @override
  ConsumerState<ReminderConsentScreen> createState() => _ConsentState();
}

class _ConsentState extends ConsumerState<ReminderConsentScreen> {
  final evidence = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  String channel = 'email';
  bool allowed = false, loading = true, saving = false, loaded = false;
  String? error, key, fingerprint;
  int version = 0;
  bool contactChanged = false;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    evidence.dispose();
    super.dispose();
  }

  void selectChannel(String value) {
    channel = value;
    allowed = false;
    version = 0;
    contactChanged = false;
    evidence.clear();
    for (final row in rows) {
      if (row['channel'] == value) {
        allowed = row['allowed'] as bool;
        contactChanged =
            row.containsKey('current_recipient') &&
            row['recipient'] != row['current_recipient'];
        if (contactChanged) allowed = false;
        version = row['version'] as int;
      }
    }
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      loaded = false;
      error = null;
    });
    try {
      final data = await ref
          .read(reminderConsentRepositoryProvider)
          .load(widget.organizationId, widget.customerId);
      if (!mounted) return;
      setState(() {
        rows = data;
        loaded = true;
        selectChannel(channel);
      });
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Unable to load consent. Retry before editing.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> save() async {
    if (saving || !loaded) return;
    if (evidence.text.trim().length < 3) {
      setState(
        () => error =
            'Record consent evidence or an opt-out reason (at least 3 characters).',
      );
      return;
    }
    final current = '$channel:$allowed:$version:${evidence.text.trim()}';
    if (current != fingerprint) {
      fingerprint = current;
      key = const Uuid().v4();
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(reminderConsentRepositoryProvider)
          .save(
            key!,
            widget.organizationId,
            widget.customerId,
            channel,
            allowed,
            evidence.text.trim(),
            version,
          );
      if (!mounted) return;
      key = null;
      fingerprint = null;
      await load();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Consent could not be confirmed. Retry unchanged details, or reload if the record changed.',
        );
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Reminder consent'),
      actions: [
        IconButton(
          tooltip: 'Reload consent',
          onPressed: saving ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.customerName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const Text(
                  'Record the customer’s permission for each channel. This screen does not send a reminder.',
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(error!),
                  ),
                DropdownButtonFormField<String>(
                  initialValue: channel,
                  decoration: const InputDecoration(labelText: 'Channel'),
                  items:
                      const {
                            'email': 'Email',
                            'sms': 'SMS',
                            'whatsapp': 'WhatsApp',
                          }.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                  onChanged: saving || !loaded
                      ? null
                      : (value) => setState(() => selectChannel(value!)),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Customer allows overdue reminders'),
                  value: allowed,
                  onChanged: saving || !loaded
                      ? null
                      : (value) => setState(() => allowed = value),
                ),
                if (contactChanged)
                  const Text(
                    'Contact details changed since consent was recorded. Obtain fresh consent for the current contact before enabling reminders.',
                  ),
                TextField(
                  controller: evidence,
                  enabled: !saving && loaded,
                  maxLength: 500,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Consent evidence / opt-out reason',
                  ),
                ),
                FilledButton(
                  onPressed: saving || !loaded ? null : save,
                  child: Text(saving ? 'Saving…' : 'Save consent'),
                ),
              ],
            ),
    ),
  );
}
