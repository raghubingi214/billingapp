import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/dashboard_repository.dart';
import '../data/supabase_dashboard_repository.dart';
import '../../../app/theme/app_theme.dart';

final dashboardRepositoryProvider = Provider<DashboardRepository>(
  (ref) => SupabaseDashboardRepository(ref.watch(supabaseClientProvider)),
);

class DashboardPanel extends ConsumerStatefulWidget {
  const DashboardPanel({super.key, required this.organizationId});
  final String organizationId;
  @override
  ConsumerState<DashboardPanel> createState() => _DashboardPanelState();
}

class _DashboardPanelState extends ConsumerState<DashboardPanel> {
  late Future<DashboardSummary> summary;
  int days = 1;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    final today = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    final from = today
        .subtract(Duration(days: days - 1))
        .toIso8601String()
        .substring(0, 10);
    summary = ref
        .read(dashboardRepositoryProvider)
        .summary(
          widget.organizationId,
          from,
          today.toIso8601String().substring(0, 10),
        );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final option in [1, 7, 30])
            ChoiceChip(
              label: Text(option == 1 ? 'Today' : '$option days'),
              selected: days == option,
              onSelected: (_) => setState(() {
                days = option;
                reload();
              }),
              showCheckmark: false,
              selectedColor: AppTheme.blue.withValues(alpha: 0.12),
              side: BorderSide(
                color: days == option ? AppTheme.blue : const Color(0xffCBD5E1),
              ),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: days == option ? FontWeight.w700 : FontWeight.w500,
                color: days == option ? AppTheme.blue : const Color(0xff475569),
              ),
            ),
          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: () => setState(reload),
            icon: const Icon(Icons.refresh, size: 20),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              side: const BorderSide(color: Color(0xffE2E8F0)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      FutureBuilder<DashboardSummary>(
        future: summary,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton.icon(
                onPressed: () => setState(reload),
                icon: const Icon(Icons.refresh),
                label: const Text('Unable to load summary. Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
              ),
            );
          }
          final data = snapshot.data!;
          final metrics = [
            (
              'Sales',
              '₹${data.sales}',
              Icons.trending_up,
              'Live',
              AppTheme.blue,
              'Billed net sales',
            ),
            (
              'Collections',
              '₹${data.collections}',
              Icons.account_balance_wallet_outlined,
              'Settled',
              AppTheme.emerald,
              'Cash & digital receipts',
            ),
            (
              'Outstanding · all dates',
              '₹${data.outstanding}',
              Icons.pending_actions_outlined,
              'Dues',
              AppTheme.amber,
              'Receivables ledger',
            ),
            (
              'Low-stock product/outlet pairs',
              '${data.lowStock}',
              Icons.inventory_2_outlined,
              'Alert',
              AppTheme.rose,
              'SKUs below min limit',
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data.cashierScope)
                Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.blue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.blue.withValues(alpha: 0.2)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.person_outline, size: 16, color: AppTheme.blue),
                      SizedBox(width: 8),
                      Text(
                        'Your sales and receipts',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.blue,
                        ),
                      ),
                    ],
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final isWide = constraints.maxWidth >= 380;
                  if (isWide) {
                    return GridView.count(
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      childAspectRatio: 1.15,
                      children: [
                        for (final m in metrics)
                          _MetricCard(
                            title: m.$1,
                            value: m.$2,
                            icon: m.$3,
                            badge: m.$4,
                            color: m.$5,
                            subtitle: m.$6,
                          ),
                      ],
                    );
                  }
                  return Column(
                    children: [
                      for (final m in metrics)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _MetricCard(
                            title: m.$1,
                            value: m.$2,
                            icon: m.$3,
                            badge: m.$4,
                            color: m.$5,
                            subtitle: m.$6,
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 4,
                children: [
                  const Icon(Icons.sync, size: 12, color: Color(0xff94A3B8)),
                  Text(
                    'Updated ${DateTime.tryParse(data.refreshedAt)?.toLocal().toString() ?? data.refreshedAt}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff94A3B8),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    ],
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.badge,
    required this.color,
    required this.subtitle,
  });

  final String title;
  final String value;
  final IconData icon;
  final String badge;
  final Color color;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xffE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xff0F172A).withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xff64748B),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xff0F172A),
                letterSpacing: -0.5,
              ),
            ),
          ),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xff94A3B8),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
