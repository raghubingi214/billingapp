import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/dashboard_repository.dart';
import '../data/supabase_dashboard_repository.dart';

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
        children: [
          for (final option in [1, 7, 30])
            ChoiceChip(
              label: Text(option == 1 ? 'Today' : '$option days'),
              selected: days == option,
              onSelected: (_) => setState(() {
                days = option;
                reload();
              }),
            ),
          IconButton(
            tooltip: 'Refresh dashboard',
            onPressed: () => setState(reload),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      FutureBuilder<DashboardSummary>(
        future: summary,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return TextButton(
              onPressed: () => setState(reload),
              child: const Text('Unable to load summary. Retry'),
            );
          }
          if (!snapshot.hasData) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final data = snapshot.data!;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data.cashierScope) const Text('Your sales and receipts'),
              for (final metric in [
                ('Sales', '₹${data.sales}'),
                ('Collections', '₹${data.collections}'),
                ('Outstanding · all dates', '₹${data.outstanding}'),
                ('Low-stock product/outlet pairs', '${data.lowStock}'),
              ])
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(metric.$1),
                        const SizedBox(height: 8),
                        Text(
                          metric.$2,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ],
                    ),
                  ),
                ),
              Text(
                'Updated ${DateTime.tryParse(data.refreshedAt)?.toLocal().toString() ?? data.refreshedAt}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    ],
  );
}
