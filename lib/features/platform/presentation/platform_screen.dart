import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../data/supabase_platform_repository.dart';
import '../domain/platform_repository.dart';
import 'platform_plans_screen.dart';

final platformRepositoryProvider = Provider<PlatformRepository>(
  (ref) => SupabasePlatformRepository(ref.watch(supabaseClientProvider)),
);
final platformThreadProvider = FutureProvider.autoDispose
    .family<
      List<Map<String, dynamic>>,
      ({String userId, String supportId, int offset})
    >((ref, page) async {
      if (!await ref.watch(platformAccessProvider(page.userId).future)) {
        throw StateError('Platform access denied');
      }
      return ref
          .watch(platformRepositoryProvider)
          .supportThread(page.supportId, page.offset);
    });

final platformSupportProvider = FutureProvider.autoDispose
    .family<
      List<Map<String, dynamic>>,
      ({String userId, String status, int offset})
    >((ref, page) async {
      if (!await ref.watch(platformAccessProvider(page.userId).future)) {
        throw StateError('Platform access denied');
      }
      return ref
          .watch(platformRepositoryProvider)
          .supportQueue(page.status, page.offset);
    });

final platformAccessProvider = FutureProvider.autoDispose.family<bool, String>(
  (ref, userId) => ref.watch(platformRepositoryProvider).hasAccess(),
);

final platformOverviewProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, userId) async {
      if (!await ref.watch(platformAccessProvider(userId).future)) {
        throw StateError('Platform access denied');
      }
      return ref.watch(platformRepositoryProvider).overview();
    });

final platformBusinessesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({String userId, int offset})>((
      ref,
      page,
    ) async {
      if (!await ref.watch(platformAccessProvider(page.userId).future)) {
        throw StateError('Platform access denied');
      }
      return ref.watch(platformRepositoryProvider).businesses(page.offset);
    });

class PlatformScreen extends ConsumerWidget {
  const PlatformScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(platformAccessProvider(userId));
    return Scaffold(
      appBar: AppBar(title: const Text('Platform administration')),
      body: _PlatformResumeCheck(
        userId: userId,
        child: SafeArea(
          child: access.when(
            skipLoadingOnRefresh: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: FilledButton(
                onPressed: () => ref.invalidate(platformAccessProvider(userId)),
                child: const Text('Retry access check'),
              ),
            ),
            data: (allowed) => allowed
                ? _overview(ref)
                : const Center(
                    child: Text(
                      'Platform access is not enabled for this account.',
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _overview(WidgetRef ref) => ref
      .watch(platformOverviewProvider(userId))
      .when(
        skipLoadingOnRefresh: false,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => Center(
          child: FilledButton(
            onPressed: () => ref.invalidate(platformOverviewProvider(userId)),
            child: const Text('Retry overview'),
          ),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(platformAccessProvider(userId));
            ref.invalidate(platformOverviewProvider(userId));
            try {
              await ref.read(platformOverviewProvider(userId).future);
            } catch (_) {
              // The provider renders access and network failures in the page.
            }
          },
          child: ListView(
            padding: const EdgeInsets.all(20),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              const Text('Platform overview'),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(ref.context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlatformPlansScreen(userId: userId),
                  ),
                ),
                icon: const Icon(Icons.card_membership_outlined),
                label: const Text('Plan catalog'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(ref.context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlatformSupportScreen(userId: userId),
                  ),
                ),
                icon: const Icon(Icons.support_agent),
                label: const Text('Support queue'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(ref.context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => PlatformBusinessesScreen(userId: userId),
                  ),
                ),
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('Browse businesses'),
              ),
              const SizedBox(height: 16),
              for (final entry in const {
                'businesses': 'Businesses',
                'active_businesses': 'Active businesses',
                'suspended_businesses': 'Suspended businesses',
                'active_staff_members': 'Active staff memberships',
              }.entries)
                Card(
                  child: ListTile(
                    title: Text(entry.value),
                    trailing: Text('${data[entry.key] ?? 0}'),
                  ),
                ),
            ],
          ),
        ),
      );
}

class PlatformBusinessesScreen extends ConsumerStatefulWidget {
  const PlatformBusinessesScreen({super.key, required this.userId});
  final String userId;
  @override
  ConsumerState<PlatformBusinessesScreen> createState() =>
      _PlatformBusinessesState();
}

class _PlatformBusinessesState extends ConsumerState<PlatformBusinessesScreen> {
  int offset = 0;
  @override
  Widget build(BuildContext context) {
    final page = (userId: widget.userId, offset: offset);
    final rows = ref.watch(platformBusinessesProvider(page));
    return Scaffold(
      appBar: AppBar(title: const Text('Platform businesses')),
      body: _PlatformResumeCheck(
        userId: widget.userId,
        child: SafeArea(
          child: rows.when(
            skipLoadingOnRefresh: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: FilledButton(
                onPressed: () {
                  ref.invalidate(platformAccessProvider(widget.userId));
                  ref.invalidate(platformBusinessesProvider(page));
                },
                child: const Text('Retry access and load'),
              ),
            ),
            data: (items) => ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (items.isEmpty) const Text('No businesses on this page.'),
                for (final item in items)
                  Card(
                    child: ListTile(
                      title: Text(item['name'] as String),
                      subtitle: Text(
                        '${item['status']} · ${item['staff_count']} active staff',
                      ),
                      isThreeLine: false,
                    ),
                  ),
                Wrap(
                  spacing: 12,
                  children: [
                    OutlinedButton(
                      onPressed: offset == 0
                          ? null
                          : () => setState(() => offset -= 50),
                      child: const Text('Previous'),
                    ),
                    OutlinedButton(
                      onPressed: items.length < 50
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
      ),
    );
  }
}

class PlatformSupportScreen extends ConsumerStatefulWidget {
  const PlatformSupportScreen({super.key, required this.userId});
  final String userId;
  @override
  ConsumerState<PlatformSupportScreen> createState() => _PlatformSupportState();
}

class _PlatformSupportState extends ConsumerState<PlatformSupportScreen> {
  final commandKeys = <String, String>{};
  bool busy = false;
  String? error;
  Future<void> review(String id) async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start reviewing this request?'),
        content: const Text('The owner will see the request as in review.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Start review'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    final command = commandKeys.putIfAbsent(id, () => const Uuid().v4());
    try {
      await ref
          .read(platformRepositoryProvider)
          .beginSupportReview(command, id);
      if (!mounted) return;
      commandKeys.remove(id);
      ref.invalidate(platformSupportProvider);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Review could not be confirmed. Retry or refresh the queue.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String status = 'open';
  int offset = 0;
  @override
  Widget build(BuildContext context) {
    final page = (userId: widget.userId, status: status, offset: offset);
    final queue = ref.watch(platformSupportProvider(page));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support queue'),
        actions: [
          IconButton(
            tooltip: 'Refresh queue',
            onPressed: () =>
                ref.invalidate(platformAccessProvider(widget.userId)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _PlatformResumeCheck(
        userId: widget.userId,
        child: SafeArea(
          child: Column(
            children: [
              if (error != null)
                Padding(padding: const EdgeInsets.all(16), child: Text(error!)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(
                    labelText: 'Request status',
                  ),
                  items:
                      const {
                            'open': 'Open',
                            'in_review': 'In review',
                            'resolved': 'Resolved',
                            'cancelled': 'Cancelled',
                          }.entries
                          .map(
                            (e) => DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setState(() {
                    status = value!;
                    offset = 0;
                  }),
                ),
              ),
              Expanded(
                child: queue.when(
                  skipLoadingOnRefresh: false,
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, _) => Center(
                    child: FilledButton(
                      onPressed: () =>
                          ref.invalidate(platformAccessProvider(widget.userId)),
                      child: const Text('Retry access and queue'),
                    ),
                  ),
                  data: (rows) => ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (rows.isEmpty) const Text('No requests on this page.'),
                      for (final row in rows)
                        Card(
                          child: ExpansionTile(
                            title: Text('${row['subject']}'),
                            subtitle: Text(
                              '${row['business_name']} · ${row['kind']}',
                            ),
                            children: [
                              if (['open', 'in_review'].contains(row['status']))
                                OutlinedButton.icon(
                                  onPressed: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => PlatformReplyScreen(
                                        userId: widget.userId,
                                        supportId: row['id'] as String,
                                        subject: row['subject'] as String,
                                      ),
                                    ),
                                  ),
                                  icon: const Icon(Icons.reply),
                                  label: const Text('Reply to owner'),
                                ),
                              if (row['status'] == 'open')
                                FilledButton(
                                  onPressed: busy
                                      ? null
                                      : () => review(row['id'] as String),
                                  child: const Text('Start review'),
                                ),
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: SelectableText('${row['message']}'),
                              ),
                            ],
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
            ],
          ),
        ),
      ),
    );
  }
}

class PlatformReplyScreen extends ConsumerStatefulWidget {
  const PlatformReplyScreen({
    super.key,
    required this.userId,
    required this.supportId,
    required this.subject,
  });
  final String userId, supportId, subject;
  @override
  ConsumerState<PlatformReplyScreen> createState() => _PlatformReplyState();
}

class _PlatformReplyState extends ConsumerState<PlatformReplyScreen> {
  int threadOffset = 0;
  final body = TextEditingController();
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? error, commandKey, commandBody;
  @override
  void dispose() {
    body.dispose();
    super.dispose();
  }

  Future<void> send() async {
    if (busy || !form.currentState!.validate()) return;
    final text = body.text.trim();
    if (commandBody != text) {
      commandKey = const Uuid().v4();
      commandBody = text;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(platformRepositoryProvider)
          .replyToSupport(commandKey!, widget.supportId, text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reply sent to the business owner.')),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Unable to confirm reply. Retry unchanged text to safely check the result.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = ref.watch(platformAccessProvider(widget.userId));
    return Scaffold(
      appBar: AppBar(title: const Text('Reply to owner')),
      body: _PlatformResumeCheck(
        userId: widget.userId,
        child: SafeArea(
          child: access.when(
            skipLoadingOnRefresh: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => Center(
              child: FilledButton(
                onPressed: () =>
                    ref.invalidate(platformAccessProvider(widget.userId)),
                child: const Text('Retry access'),
              ),
            ),
            data: (allowed) => !allowed
                ? const Center(
                    child: Text(
                      'Platform access is not enabled for this account.',
                    ),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            widget.subject,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: body,
                            enabled: !busy,
                            minLines: 4,
                            maxLines: 12,
                            maxLength: 4000,
                            decoration: const InputDecoration(
                              labelText: 'Response to business owner',
                            ),
                            validator: (value) =>
                                (value?.trim().isEmpty ?? true)
                                ? 'Enter a response'
                                : null,
                          ),
                          if (error != null) Text(error!),
                          const SizedBox(height: 16),
                          FilledButton(
                            onPressed: busy ? null : send,
                            child: Text(busy ? 'Sending…' : 'Send reply'),
                          ),
                          const SizedBox(height: 24),
                          const Text('Previous responses'),
                          ref
                              .watch(
                                platformThreadProvider((
                                  userId: widget.userId,
                                  supportId: widget.supportId,
                                  offset: threadOffset,
                                )),
                              )
                              .when(
                                skipLoadingOnRefresh: false,
                                loading: () => const Center(
                                  child: CircularProgressIndicator(),
                                ),
                                error: (_, _) => TextButton(
                                  onPressed: () =>
                                      ref.invalidate(platformThreadProvider),
                                  child: const Text('Retry response history'),
                                ),
                                data: (rows) => Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (rows.isEmpty)
                                      const Text('No responses on this page.'),
                                    for (final row in rows)
                                      Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: SelectableText(
                                            '${row['body']}',
                                          ),
                                        ),
                                      ),
                                    Wrap(
                                      spacing: 12,
                                      children: [
                                        TextButton(
                                          onPressed: threadOffset == 0
                                              ? null
                                              : () => setState(
                                                  () => threadOffset -= 50,
                                                ),
                                          child: const Text(
                                            'Previous responses',
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: rows.length < 50
                                              ? null
                                              : () => setState(
                                                  () => threadOffset += 50,
                                                ),
                                          child: const Text('Next responses'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
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

class _PlatformResumeCheck extends ConsumerStatefulWidget {
  const _PlatformResumeCheck({required this.userId, required this.child});
  final String userId;
  final Widget child;
  @override
  ConsumerState<_PlatformResumeCheck> createState() =>
      _PlatformResumeCheckState();
}

class _PlatformResumeCheckState extends ConsumerState<_PlatformResumeCheck>
    with WidgetsBindingObserver {
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
      ref.invalidate(platformAccessProvider(widget.userId));
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
