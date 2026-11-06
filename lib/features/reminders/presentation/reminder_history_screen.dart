import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../data/supabase_reminder_queue_repository.dart';
import '../domain/reminder_queue_repository.dart';

final reminderQueueRepositoryProvider = Provider<ReminderQueueRepository>(
  (ref) => SupabaseReminderQueueRepository(ref.watch(supabaseClientProvider)),
);
final reminderHistoryProvider = FutureProvider.autoDispose
    .family<
      List<Map<String, dynamic>>,
      ({String organizationId, String customerId, int offset})
    >(
      (ref, page) => ref
          .watch(reminderQueueRepositoryProvider)
          .history(page.organizationId, page.customerId, page.offset),
    );

class ReminderHistoryScreen extends ConsumerStatefulWidget {
  const ReminderHistoryScreen({
    super.key,
    required this.organizationId,
    required this.customerId,
  });
  final String organizationId, customerId;
  @override
  ConsumerState<ReminderHistoryScreen> createState() => _HistoryState();
}

class _HistoryState extends ConsumerState<ReminderHistoryScreen>
    with WidgetsBindingObserver {
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
      ref.invalidate(reminderHistoryProvider);
    }
  }

  String date(Object? value) {
    final parsed = DateTime.tryParse('$value');
    return parsed == null
        ? 'Date unavailable'
        : DateFormat.yMMMd().add_jm().format(parsed.toLocal());
  }

  @override
  Widget build(BuildContext context) {
    final page = (
      organizationId: widget.organizationId,
      customerId: widget.customerId,
      offset: offset,
    );
    final history = ref.watch(reminderHistoryProvider(page));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminder history'),
        actions: [
          IconButton(
            tooltip: 'Refresh reminders',
            onPressed: () => ref.invalidate(reminderHistoryProvider(page)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: history.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: FilledButton(
              onPressed: () => ref.invalidate(reminderHistoryProvider(page)),
              child: const Text('Retry reminders'),
            ),
          ),
          data: (rows) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'Queued means waiting for delivery. It does not confirm that a message was sent.',
              ),
              const SizedBox(height: 16),
              if (rows.isEmpty) const Text('No reminders on this page.'),
              for (final row in rows)
                Card(
                  child: ListTile(
                    title: Text(
                      '${row['channel']} · ${const {'queued': 'Queued', 'processing': 'Processing', 'delivered': 'Delivered', 'failed': 'Failed', 'cancelled': 'Cancelled'}[row['state']] ?? 'Unknown'}',
                    ),
                    subtitle: Text(date(row['created_at'])),
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
