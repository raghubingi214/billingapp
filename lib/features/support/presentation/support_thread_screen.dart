import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'support_providers.dart';

final supportRepliesProvider = FutureProvider.autoDispose
    .family<
      List<Map<String, dynamic>>,
      ({String organizationId, String supportId, int offset})
    >(
      (ref, page) => ref
          .watch(supportRepositoryProvider)
          .replies(page.organizationId, page.supportId, page.offset),
    );

class SupportThreadScreen extends ConsumerStatefulWidget {
  const SupportThreadScreen({
    super.key,
    required this.organizationId,
    required this.supportId,
    required this.subject,
  });
  final String organizationId, supportId, subject;
  @override
  ConsumerState<SupportThreadScreen> createState() => _SupportThreadState();
}

class _SupportThreadState extends ConsumerState<SupportThreadScreen>
    with WidgetsBindingObserver {
  String _date(Object? value) {
    final date = DateTime.tryParse('$value');
    return date == null
        ? 'Date unavailable'
        : DateFormat.yMMMd().add_jm().format(date.toLocal());
  }

  int offset = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(supportRepliesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = (
      organizationId: widget.organizationId,
      supportId: widget.supportId,
      offset: offset,
    );
    final replies = ref.watch(supportRepliesProvider(page));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support responses'),
        actions: [
          IconButton(
            tooltip: 'Refresh responses',
            onPressed: () => ref.invalidate(supportRepliesProvider(page)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: replies.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: FilledButton(
              onPressed: () => ref.invalidate(supportRepliesProvider(page)),
              child: const Text('Retry responses'),
            ),
          ),
          data: (rows) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                widget.subject,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty) const Text('No responses on this page yet.'),
              for (final row in rows)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Support team'),
                        const SizedBox(height: 8),
                        SelectableText('${row['body']}'),
                        const SizedBox(height: 8),
                        Text(_date(row['created_at'])),
                      ],
                    ),
                  ),
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
      ),
    );
  }
}
