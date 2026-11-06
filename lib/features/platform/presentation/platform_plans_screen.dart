import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../data/supabase_platform_plan_repository.dart';
import '../domain/platform_plan_repository.dart';
import '../data/suggested_plan_templates.dart';

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
                    builder: (_) => const PlatformPlanDraftScreen(),
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
  const PlatformPlanDraftScreen({super.key});
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
  bool busy = false;
  String? error, command, fingerprint;
  @override
  void dispose() {
    for (final controller in fields.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (busy || !form.currentState!.validate()) return;
    final data = <String, dynamic>{
      for (final entry in fields.entries) entry.key: entry.value.text.trim(),
      'billing_interval': interval,
      'report_types': ['sales', 'purchases', 'payments'],
    };
    if (fields['trial_invoice_limit']!.text.trim().isEmpty) {
      data['trial_invoice_limit'] = null;
    }
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
          .read(platformPlanRepositoryProvider)
          .createDraft(command!, data);
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
    body: SafeArea(
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
                'trial_invoice_limit': 'Entire trial invoice cap (optional)',
              }.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: fields[entry.key],
                    enabled: !busy,
                    decoration: InputDecoration(labelText: entry.value),
                    keyboardType: ['code', 'name'].contains(entry.key)
                        ? TextInputType.text
                        : const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      final text = value?.trim() ?? '';
                      if (entry.key == 'code') {
                        return RegExp(r'^[a-z][a-z0-9_]{1,63}$').hasMatch(text)
                            ? null
                            : 'Use 2–64 lowercase letters, numbers or underscores';
                      }
                      if (entry.key == 'name') {
                        return text.isNotEmpty && text.length <= 120
                            ? null
                            : 'Enter a name up to 120 characters';
                      }
                      if (entry.key == 'price_inr') {
                        return RegExp(r'^\d+([.]\d{1,2})?$').hasMatch(text)
                            ? null
                            : 'Enter a non-negative price with up to 2 decimals';
                      }
                      if (entry.key == 'trial_invoice_limit' && text.isEmpty) {
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
                  DropdownMenuItem(value: 'month', child: Text('Monthly')),
                  DropdownMenuItem(value: 'year', child: Text('Annual')),
                ],
                onChanged: busy
                    ? null
                    : (value) => setState(() => interval = value!),
              ),
              const Text('Includes sales, purchase and cash-flow reports.'),
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
