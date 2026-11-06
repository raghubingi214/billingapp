import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../data/supabase_subscription_repository.dart';
import '../domain/subscription_repository.dart';

final subscriptionRepositoryProvider = Provider<SubscriptionRepository>(
  (ref) => SupabaseSubscriptionRepository(ref.watch(supabaseClientProvider)),
);
final subscriptionSummaryProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>(
      (ref, organizationId) =>
          ref.watch(subscriptionRepositoryProvider).summary(organizationId),
    );

class SubscriptionScreen extends ConsumerStatefulWidget {
  const SubscriptionScreen({super.key, required this.organizationId});
  final String organizationId;
  @override
  ConsumerState<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends ConsumerState<SubscriptionScreen>
    with WidgetsBindingObserver {
  String get organizationId => widget.organizationId;
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
      ref.invalidate(subscriptionSummaryProvider(organizationId));
    }
  }

  String _date(Object? value) {
    final date = DateTime.tryParse('$value');
    return date == null
        ? 'Unavailable'
        : DateFormat.yMMMd().add_jm().format(date.toLocal());
  }

  String _status(Object? value) => switch (value) {
    'trial' => 'Trial',
    'pending' => 'Not started',
    'active' => 'Active',
    'grace' => 'Grace period',
    'expired' => 'Expired',
    'failed_renewal' => 'Renewal failed',
    _ => 'Unavailable',
  };
  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(subscriptionSummaryProvider(organizationId));
    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: SafeArea(
        child: summary.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: FilledButton(
              onPressed: () =>
                  ref.invalidate(subscriptionSummaryProvider(organizationId)),
              child: const Text('Retry subscription'),
            ),
          ),
          data: (data) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(subscriptionSummaryProvider(organizationId));
              try {
                await ref.read(
                  subscriptionSummaryProvider(organizationId).future,
                );
              } catch (_) {
                /* Error is rendered below. */
              }
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                if (data['status'] == 'unconfigured') ...[
                  const Text(
                    'No subscription assigned',
                    style: TextStyle(fontSize: 22),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'A plan has not been assigned to this business yet.',
                  ),
                ] else ...[
                  Text(
                    '${data['plan_name']}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text('Status: ${_status(data['status'])}'),
                  Text(
                    '₹${data['price_inr']} / ${data['billing_interval'] == 'year' ? 'year' : 'month'}',
                  ),
                  Text('Period ends: ${_date(data['period_end'])}'),
                  if (data['grace_until'] != null)
                    Text('Grace ends: ${_date(data['grace_until'])}'),
                  if (data['cancel_at_period_end'] == true)
                    const Text('Renewal is cancelled for the next period.'),
                  const SizedBox(height: 20),
                  if (data['usage'] is Map) ...[
                    const Text('Current usage'),
                    const SizedBox(height: 8),
                    for (final key in ['invoices', 'staff', 'locations'])
                      Text(
                        '${{'invoices': data['invoice_usage_period'] == 'trial' ? 'Invoices during trial' : 'Invoices this month', 'staff': 'Active staff memberships', 'locations': 'Locations'}[key]}: ${(data['usage'] as Map)[key]} / ${(data['limits'] as Map)[key] ?? 'Unlimited'}',
                      ),
                    const SizedBox(height: 20),
                  ],
                  const Text('Plan limits'),
                  for (final entry
                      in (data['limits'] as Map<String, dynamic>).entries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        {
                              'invoices':
                                  data['invoice_usage_period'] == 'trial'
                                  ? 'Invoices for entire trial'
                                  : 'Invoices per month',
                              'staff': 'Staff memberships',
                              'locations': 'Locations',
                              'reminders': 'Reminders per month',
                              'reports': 'Available reports',
                            }[entry.key] ??
                            entry.key,
                      ),
                      subtitle: Text(
                        entry.value is List
                            ? ((entry.value as List).isEmpty
                                  ? 'None included'
                                  : (entry.value as List).join(', '))
                            : '${entry.value ?? 'Unlimited'}',
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
