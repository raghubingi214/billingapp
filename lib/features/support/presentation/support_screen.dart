import 'support_providers.dart';
export 'support_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'support_thread_screen.dart';
import '../domain/pending_support_request.dart';

class SupportScreen extends ConsumerStatefulWidget {
  const SupportScreen({
    super.key,
    required this.organizationId,
    required this.actorId,
  });
  final String organizationId, actorId;
  @override
  ConsumerState<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends ConsumerState<SupportScreen>
    with WidgetsBindingObserver {
  final subject = TextEditingController(), message = TextEditingController();
  final form = GlobalKey<FormState>();
  String kind = 'help';
  String? error, pendingKey, pendingPayload;
  bool busy = true;
  int offset = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    restore();
  }

  Future<void> restore() async {
    try {
      if (widget.actorId.isEmpty) throw StateError('Missing identity');
      final saved = await ref
          .read(pendingSupportStoreProvider)
          .load(widget.actorId, widget.organizationId);
      if (!mounted) return;
      if (saved != null) {
        kind = saved.kind;
        subject.text = saved.subject;
        message.text = saved.message;
        pendingKey = saved.requestId;
        pendingPayload =
            '${saved.kind}\u0000${saved.subject}\u0000${saved.message}';
      }
      setState(() => busy = false);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Unable to restore your pending request. Reopen this screen to retry.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(supportHistoryProvider);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    subject.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    final textSubject = subject.text.trim(), textMessage = message.text.trim();
    final selectedKind = kind;
    if (selectedKind == 'account_closure') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Request account closure?'),
          content: const Text(
            'This sends a request for review. Tax records may need to be retained. Your business is not deleted immediately.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send request'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    final payload = '$selectedKind\u0000$textSubject\u0000$textMessage';
    if (pendingPayload != payload) {
      pendingKey = const Uuid().v4();
      pendingPayload = payload;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(pendingSupportStoreProvider)
          .save(
            widget.actorId,
            PendingSupportRequest(
              pendingKey!,
              widget.organizationId,
              selectedKind,
              textSubject,
              textMessage,
            ),
          );
      await ref
          .read(supportRepositoryProvider)
          .submit(
            pendingKey!,
            widget.organizationId,
            selectedKind,
            textSubject,
            textMessage,
          );
      await ref
          .read(pendingSupportStoreProvider)
          .clear(widget.actorId, widget.organizationId);
      if (!mounted) return;
      pendingKey = null;
      pendingPayload = null;
      subject.clear();
      message.clear();
      offset = 0;
      ref.invalidate(supportHistoryProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request recorded. You can follow its status below.'),
        ),
      );
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Unable to confirm submission. Retry with the same details to check safely.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = (organizationId: widget.organizationId, offset: offset);
    final history = ref.watch(supportHistoryProvider(page));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help & requests'),
        actions: [
          IconButton(
            tooltip: 'Refresh request history',
            onPressed: () => ref.invalidate(supportHistoryProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    key: ValueKey(kind),
                    initialValue: kind,
                    decoration: const InputDecoration(
                      labelText: 'Request type',
                    ),
                    items:
                        const {
                              'help': 'Help',
                              'feedback': 'Feedback',
                              'export': 'Business data export',
                              'account_closure': 'Account closure',
                            }.entries
                            .map(
                              (e) => DropdownMenuItem(
                                value: e.key,
                                child: Text(e.value),
                              ),
                            )
                            .toList(),
                    onChanged: busy
                        ? null
                        : (value) => setState(() => kind = value!),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: subject,
                    enabled: !busy,
                    maxLength: 160,
                    decoration: const InputDecoration(labelText: 'Subject'),
                    validator: (value) => (value?.trim().length ?? 0) < 3
                        ? 'Enter at least 3 characters'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: message,
                    enabled: !busy,
                    maxLength: 4000,
                    minLines: 3,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      labelText: 'Details',
                      helperText:
                          'Do not include passwords or payment card details.',
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 10
                        ? 'Enter at least 10 characters'
                        : null,
                  ),
                  if (error != null) Text(error!),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: Text(busy ? 'Sending…' : 'Submit request'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
            const Text('Request history'),
            history.when(
              skipLoadingOnRefresh: false,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => TextButton(
                onPressed: () => ref.invalidate(supportHistoryProvider(page)),
                child: const Text('Retry history'),
              ),
              data: (rows) => Column(
                children: [
                  if (rows.isEmpty)
                    const ListTile(title: Text('No requests on this page.')),
                  for (final row in rows)
                    ListTile(
                      title: Text('${row['subject']}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SupportThreadScreen(
                            organizationId: widget.organizationId,
                            supportId: row['id'] as String,
                            subject: row['subject'] as String,
                          ),
                        ),
                      ),
                      subtitle: Text('${row['status']} · ${row['created_at']}'),
                    ),
                  Wrap(
                    spacing: 12,
                    children: [
                      TextButton(
                        onPressed: offset == 0
                            ? null
                            : () => setState(() => offset -= 50),
                        child: const Text('Previous'),
                      ),
                      TextButton(
                        onPressed: rows.length < 50
                            ? null
                            : () => setState(() => offset += 50),
                        child: const Text('Next'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
