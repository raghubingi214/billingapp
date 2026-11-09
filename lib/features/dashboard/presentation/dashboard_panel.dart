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
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          const Text(
            'FINANCIAL & FLOOR TELEMETRY',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Color(0xff8d90a0),
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.sync, size: 12, color: AppTheme.blue),
              const SizedBox(width: 4),
              Text(
                'Real-time',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.lightBlue,
                ),
              ),
            ],
          ),
        ],
      ),
      const SizedBox(height: 10),
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
              backgroundColor: const Color(0xff1c1f29),
              selectedColor: AppTheme.blue.withValues(alpha: 0.25),
              side: BorderSide(
                color: days == option ? AppTheme.blue : const Color(0xff31353f),
              ),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: days == option ? FontWeight.w700 : FontWeight.w500,
                color: days == option ? AppTheme.lightBlue : const Color(0xff8d90a0),
              ),
            ),
          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: () => setState(reload),
            icon: const Icon(Icons.refresh, size: 18, color: AppTheme.lightBlue),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xff1c1f29),
              side: const BorderSide(color: Color(0xff31353f)),
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
              '+18.4%',
              const Color(0xff4edea3),
              'Billed net sales',
              true,
            ),
            (
              'Collections',
              '₹${data.collections}',
              Icons.account_balance_wallet_outlined,
              '98% Settled',
              AppTheme.blue,
              'Cash & digital receipts',
              false,
            ),
            (
              'Outstanding · all dates',
              '₹${data.outstanding}',
              Icons.pending_actions_outlined,
              'Overdue',
              AppTheme.amber,
              'Receivables ledger',
              false,
            ),
            (
              'Low-stock product/outlet pairs',
              '${data.lowStock}',
              Icons.warning_amber_rounded,
              'Alert',
              AppTheme.rose,
              'SKUs below min limit',
              false,
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
                    color: AppTheme.blue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppTheme.blue.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.person_outline, size: 16, color: AppTheme.lightBlue),
                      SizedBox(width: 8),
                      Text(
                        'Your sales and receipts',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.lightBlue,
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
                      childAspectRatio: 1.05,
                      children: [
                        for (final m in metrics)
                          _MetricCard(
                            title: m.$1,
                            value: m.$2,
                            icon: m.$3,
                            badge: m.$4,
                            color: m.$5,
                            subtitle: m.$6,
                            hasProgressBar: m.$7,
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
                            hasProgressBar: m.$7,
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
                  const Icon(Icons.sync, size: 12, color: Color(0xff8d90a0)),
                  Text(
                    'Updated ${DateTime.tryParse(data.refreshedAt)?.toLocal().toString() ?? data.refreshedAt}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xff8d90a0),
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
    this.hasProgressBar = false,
  });

  final String title;
  final String value;
  final IconData icon;
  final String badge;
  final Color color;
  final String subtitle;
  final bool hasProgressBar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xff1c1f29),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xff31353f)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
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
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(9999),
                  border: Border.all(color: color.withValues(alpha: 0.35)),
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
          const SizedBox(height: 6),
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Color(0xff8d90a0),
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
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Colors.white,
                letterSpacing: -0.5,
              ),
            ),
          ),
          if (hasProgressBar) ...[
            const SizedBox(height: 2),
            ClipRRect(
              borderRadius: BorderRadius.circular(9999),
              child: LinearProgressIndicator(
                value: 0.82,
                minHeight: 4,
                backgroundColor: const Color(0xff262a34),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xff8d90a0),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
