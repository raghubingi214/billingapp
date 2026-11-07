import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../data/supabase_platform_plan_repository.dart';
import '../domain/platform_plan_repository.dart';
import '../data/suggested_plan_templates.dart';
import '../data/shared_preferences_pending_plan_store.dart';
import '../domain/pending_plan_draft.dart';

final pendingPlanDraftStoreProvider = Provider<PendingPlanDraftStore>(
  (ref) => SharedPreferencesPendingPlanStore(),
);

final suggestedPlanTemplatesProvider =
    FutureProvider.autoDispose<List<Map<String, String>>>(
      (ref) => SuggestedPlanTemplates().load(),
    );

final platformPlanRepositoryProvider = Provider<PlatformPlanRepository>(
  (ref) => SupabasePlatformPlanRepository(ref.watch(supabaseClientProvider)),
);
final platformPlansProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({String userId, int offset})>(
      (ref, page) =>
          ref.watch(platformPlanRepositoryProvider).page(page.offset),
    );

final platformSubscriptionProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, id) =>
          ref.watch(platformPlanRepositoryProvider).subscriptionOptions(id),
    );

class PlatformSubscriptionScreen extends ConsumerStatefulWidget {
  const PlatformSubscriptionScreen({
    super.key,
    required this.organizationId,
    required this.businessName,
  });
  final String organizationId;
  final String businessName;

  @override
  ConsumerState<PlatformSubscriptionScreen> createState() =>
      _PlatformSubscriptionScreenState();
}

class _PlatformSubscriptionScreenState
    extends ConsumerState<PlatformSubscriptionScreen> {
  String? selected;
  String? requestId;
  bool busy = false;

  Future<void> assign(Map plan, int? version) async {
    if (busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Assign ${plan['name']}?'),
        content: Text(
          'This changes the subscription for ${widget.businessName}. '
          'This manual assignment does not collect payment or renew automatically.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm assignment'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || busy) return;
    setState(() => busy = true);
    try {
      await ref
          .read(platformPlanRepositoryProvider)
          .assignSubscription(
            requestId ??= const Uuid().v4(),
            widget.organizationId,
            plan['id'] as String,
            version,
          );
      if (!mounted) return;
      setState(() {
        selected = null;
        requestId = null;
      });
      ref.invalidate(platformSubscriptionProvider(widget.organizationId));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Subscription updated')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Assignment could not be confirmed. Retry or reload plans.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = platformSubscriptionProvider(widget.organizationId);
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Manage subscription'),
          actions: [
            IconButton(
              tooltip: 'Reload plans',
              onPressed: busy
                  ? null
                  : () {
                      setState(() {
                        selected = null;
                        requestId = null;
                      });
                      ref.invalidate(provider);
                    },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: SafeArea(
          child: ref
              .watch(provider)
              .when(
                skipLoadingOnRefresh: false,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (_, _) => Center(
                  child: TextButton(
                    onPressed: () => ref.invalidate(provider),
                    child: const Text('Retry loading subscription'),
                  ),
                ),
                data: (data) {
                  final current = data['current'] as Map?;
                  final plans = (data['plans'] as List).cast<Map>();
                  final plan = plans
                      .where((item) => item['id'] == selected)
                      .firstOrNull;
                  final gatewayManaged = current?['gateway_managed'] == true;
                  return ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text(
                        widget.businessName,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      Text('Current plan: ${current?['name'] ?? 'Unassigned'}'),
                      const SizedBox(height: 16),
                      if (gatewayManaged)
                        const Text(
                          'This subscription is managed by the payment provider.',
                        )
                      else if (plans.isEmpty)
                        const Text('No active plans are available.')
                      else ...[
                        DropdownButtonFormField<String>(
                          key: ValueKey(plan?['id']),
                          initialValue: plan?['id'] as String?,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'New plan',
                          ),
                          items: [
                            for (final option in plans)
                              DropdownMenuItem(
                                value: option['id'] as String,
                                child: Text(
                                  '${option['name']} · ₹${option['price_inr']} / ${option['interval']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: busy
                              ? null
                              : (id) => setState(() {
                                  selected = id;
                                  requestId = null;
                                }),
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: busy || plan == null
                              ? null
                              : () => assign(plan, current?['version'] as int?),
                          child: Text(busy ? 'Assigning…' : 'Assign plan'),
                        ),
                      ],
                    ],
                  );
                },
              ),
        ),
      ),
    );
  }
}

class PlatformPlansScreen extends ConsumerStatefulWidget {
  const PlatformPlansScreen({super.key, required this.userId});
  final String userId;
  @override
  ConsumerState<PlatformPlansScreen> createState() => _PlansState();
}

class _PlansState extends ConsumerState<PlatformPlansScreen>
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
      ref.invalidate(platformPlansProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = (userId: widget.userId, offset: offset);
    final plans = ref.watch(platformPlansProvider(page));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Platform plans'),
        actions: [
          if (plans.hasValue)
            IconButton(
              tooltip: 'Create inactive draft',
              icon: const Icon(Icons.add),
              onPressed: () async {
                final saved = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) =>
                        PlatformPlanDraftScreen(userId: widget.userId),
                  ),
                );
                if (saved == true && mounted) {
                  ref.invalidate(platformPlansProvider);
                }
              },
            ),
          IconButton(
            tooltip: 'Refresh plans',
            onPressed: () => ref.invalidate(platformPlansProvider(page)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: plans.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Unable to load plans. Platform access and a working connection are required.',
                  ),
                  FilledButton(
                    onPressed: () =>
                        ref.invalidate(platformPlansProvider(page)),
                    child: const Text('Retry plans'),
                  ),
                ],
              ),
            ),
          ),
          data: (rows) => ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (rows.isEmpty)
                const Text(
                  'No plans on this page. Drafts must be configured before a plan can be offered.',
                ),
              for (final plan in rows)
                Card(
                  child: ExpansionTile(
                    title: Text('${plan['name']}'),
                    subtitle: Text(
                      '${plan['active'] == true ? 'Active' : 'Inactive draft'} · ₹${plan['price_inr']} / ${plan['billing_interval']}',
                    ),
                    children: [
                      for (final entry in {
                        'monthly_invoice_limit': 'Invoices per month',
                        'trial_invoice_limit': 'Invoices during trial',
                        'staff_limit': 'Users including owner',
                        'location_limit': 'Locations',
                        'monthly_reminder_limit': 'Reminders per month',
                      }.entries)
                        ListTile(
                          title: Text(entry.value),
                          subtitle: Text(
                            '${plan[entry.key] ?? 'No explicit limit'}',
                          ),
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
    );
  }
}

class PlatformPlanDraftScreen extends ConsumerStatefulWidget {
  const PlatformPlanDraftScreen({super.key, required this.userId});
  final String userId;
  @override
  ConsumerState<PlatformPlanDraftScreen> createState() => _DraftState();
}

class _DraftState extends ConsumerState<PlatformPlanDraftScreen> {
  void fillTemplate(Map<String, String> template) {
    setState(() {
      for (final entry in fields.entries) {
        entry.value.text = template[entry.key] ?? '';
      }
      interval = template['billing_interval']!;
      reportTypes = template['report_types']!.split(',');
      command = null;
      fingerprint = null;
      error = null;
    });
  }

  final form = GlobalKey<FormState>();
  final fields = {
    for (final key in [
      'code',
      'name',
      'price_inr',
      'monthly_invoice_limit',
      'staff_limit',
      'location_limit',
      'monthly_reminder_limit',
      'trial_invoice_limit',
    ])
      key: TextEditingController(),
  };
  String interval = 'month';
  List<String> reportTypes = ['sales', 'purchases', 'payments'];
  bool busy = true;
  bool restored = false;
  String? error, command, fingerprint;
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final pending = await ref
          .read(pendingPlanDraftStoreProvider)
          .load(widget.userId);
      if (!mounted) return;
      if (pending != null) {
        for (final entry in fields.entries) {
          entry.value.text = '${pending.data[entry.key] ?? ''}';
        }
        interval = pending.data['billing_interval'] as String;
        reportTypes = List<String>.from(pending.data['report_types'] as List);
        command = pending.requestId;
        fingerprint = payload().toString();
      }
      setState(() {
        busy = false;
        restored = true;
      });
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Unable to restore your pending draft. Retry when storage is available.',
        );
      }
    }
  }

  Map<String, dynamic> payload() => {
    for (final entry in fields.entries) entry.key: entry.value.text.trim(),
    'billing_interval': interval,
    'report_types': reportTypes,
    'trial_invoice_limit': fields['trial_invoice_limit']!.text.trim().isEmpty
        ? null
        : fields['trial_invoice_limit']!.text.trim(),
  };
  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final data = payload();
    final current = data.toString();
    if (current != fingerprint) {
      fingerprint = current;
      command = const Uuid().v4();
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref
          .read(pendingPlanDraftStoreProvider)
          .save(widget.userId, PendingPlanDraft(command!, data));
      await ref
          .read(platformPlanRepositoryProvider)
          .createDraft(command!, data);
      await ref.read(pendingPlanDraftStoreProvider).clear(widget.userId);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'Draft could not be confirmed. Check the unique code and retry unchanged values.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Create inactive plan')),
    body: !restored
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (error == null) const CircularProgressIndicator(),
                  if (error != null) ...[
                    Text(error!),
                    FilledButton(
                      onPressed: restore,
                      child: const Text('Retry draft recovery'),
                    ),
                  ],
                ],
              ),
            ),
          )
        : SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Saving creates an inactive draft. It does not change merchant subscriptions or collect payment.',
                    ),
                    const SizedBox(height: 16),
                    ref
                        .watch(suggestedPlanTemplatesProvider)
                        .when(
                          loading: () => const LinearProgressIndicator(),
                          error: (_, _) => TextButton(
                            onPressed: () =>
                                ref.invalidate(suggestedPlanTemplatesProvider),
                            child: const Text('Retry suggested templates'),
                          ),
                          data: (templates) => DropdownButtonFormField<int>(
                            decoration: const InputDecoration(
                              labelText: 'Suggested plan template (optional)',
                            ),
                            items: [
                              for (var i = 0; i < templates.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(templates[i]['name']!),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (index) => fillTemplate(templates[index!]),
                          ),
                        ),
                    for (final entry in const {
                      'code': 'Unique plan code',
                      'name': 'Plan name',
                      'price_inr': 'Price in INR',
                      'monthly_invoice_limit': 'Invoices per month',
                      'staff_limit': 'Users including owner',
                      'location_limit': 'Locations',
                      'monthly_reminder_limit': 'Reminders per month',
                      'trial_invoice_limit':
                          'Entire trial invoice cap (optional)',
                    }.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextFormField(
                          controller: fields[entry.key],
                          enabled: !busy,
                          decoration: InputDecoration(labelText: entry.value),
                          keyboardType: ['code', 'name'].contains(entry.key)
                              ? TextInputType.text
                              : const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (entry.key == 'code') {
                              return RegExp(
                                    r'^[a-z][a-z0-9_]{1,63}$',
                                  ).hasMatch(text)
                                  ? null
                                  : 'Use 2–64 lowercase letters, numbers or underscores';
                            }
                            if (entry.key == 'name') {
                              return text.isNotEmpty && text.length <= 120
                                  ? null
                                  : 'Enter a name up to 120 characters';
                            }
                            if (entry.key == 'price_inr') {
                              return RegExp(
                                    r'^\d+([.]\d{1,2})?$',
                                  ).hasMatch(text)
                                  ? null
                                  : 'Enter a non-negative price with up to 2 decimals';
                            }
                            if (entry.key == 'trial_invoice_limit' &&
                                text.isEmpty) {
                              return null;
                            }
                            final amount = int.tryParse(text);
                            return amount != null &&
                                    amount >=
                                        ([
                                              'staff_limit',
                                              'location_limit',
                                            ].contains(entry.key)
                                            ? 1
                                            : 0) &&
                                    amount <= 2147483647
                                ? null
                                : 'Enter a valid whole-number limit';
                          },
                        ),
                      ),
                    DropdownButtonFormField<String>(
                      key: ValueKey(interval),
                      initialValue: interval,
                      decoration: const InputDecoration(
                        labelText: 'Billing interval',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'month',
                          child: Text('Monthly'),
                        ),
                        DropdownMenuItem(value: 'year', child: Text('Annual')),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setState(() => interval = value!),
                    ),
                    Text(
                      'Reports included: ${reportTypes.map((type) => type == 'payments' ? 'cash flow' : type).join(', ')}',
                    ),
                    if (error != null) Text(error!),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: busy ? null : save,
                      child: Text(busy ? 'Saving…' : 'Save inactive draft'),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
