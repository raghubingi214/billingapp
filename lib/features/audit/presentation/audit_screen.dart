import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/audit_repository.dart';
import '../data/supabase_audit_repository.dart';

final auditRepositoryProvider = Provider<AuditRepository>(
  (ref) => SupabaseAuditRepository(ref.watch(supabaseClientProvider)),
);

class AuditScreen extends ConsumerStatefulWidget {
  const AuditScreen({super.key, required this.organizationId});
  final String organizationId;
  @override
  ConsumerState<AuditScreen> createState() => _AuditScreenState();
}

class _AuditScreenState extends ConsumerState<AuditScreen> {
  List<AuditEvent> rows = [];
  bool busy = false, more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    load(reset: true);
  }

  Future<void> load({bool reset = false}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      if (reset) rows = [];
      final page = await ref
          .read(auditRepositoryProvider)
          .page(widget.organizationId, rows.length);
      if (mounted) {
        setState(() {
          rows = [...rows, ...page];
          more = page.length == 50;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'Unable to load audit history. Check access and retry.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Audit history')),
    body: SafeArea(
      child: RefreshIndicator(
        onRefresh: () => load(reset: true),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (error != null)
              TextButton(onPressed: () => load(), child: Text(error!)),
            if (!busy && rows.isEmpty)
              const ListTile(title: Text('No recorded changes')),
            for (final event in rows)
              Card(
                child: ExpansionTile(
                  title: Text(
                    event.action.replaceAll('.', ' ').replaceAll('_', ' '),
                  ),
                  subtitle: Text(
                    '${DateTime.tryParse(event.createdAt)?.toUtc().add(const Duration(hours: 5, minutes: 30)) ?? event.createdAt} IST',
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SelectableText('Actor ID: ${event.actorId}'),
                          SelectableText('Record ID: ${event.recordId}'),
                          if (event.beforeData != null) ...[
                            const SizedBox(height: 12),
                            const Text('Before'),
                            SelectableText(
                              const JsonEncoder.withIndent(
                                '  ',
                              ).convert(event.beforeData),
                            ),
                          ],
                          if (event.afterData != null) ...[
                            const SizedBox(height: 12),
                            const Text('After'),
                            SelectableText(
                              const JsonEncoder.withIndent(
                                '  ',
                              ).convert(event.afterData),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            if (more && !busy)
              TextButton(
                onPressed: () => load(),
                child: const Text('Load more'),
              ),
          ],
        ),
      ),
    ),
  );
}
