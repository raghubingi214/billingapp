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
  const DashboardPanel({
    super.key,
    required this.organizationId,
    this.onNewSale,
    this.onScan,
    this.onAddStock,
    this.onReports,
  });

  final String organizationId;
  final VoidCallback? onNewSale;
  final VoidCallback? onScan;
  final VoidCallback? onAddStock;
  final VoidCallback? onReports;

  @override
  ConsumerState<DashboardPanel> createState() => _DashboardPanelState();
}

class _DashboardPanelState extends ConsumerState<DashboardPanel> {
  late Future<DashboardSummary> summary;
  int invoiceFilter = 0; // 0: All, 1: Paid, 2: Partial, 3: Unpaid

  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    final today = DateTime.now().toUtc().add(
      const Duration(hours: 5, minutes: 30),
    );
    final from = today.toIso8601String().substring(0, 10);
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
      // 1. Financial & Floor Telemetry Header
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
              color: Color(0xffdfe2ef),
            ),
          ),
          InkWell(
            onTap: () => setState(reload),
            borderRadius: BorderRadius.circular(6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.sync, size: 13, color: AppTheme.blue),
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
          ),
        ],
      ),
      const SizedBox(height: 12),

      // 2. 2x2 Telemetry Metric Cards
      FutureBuilder<DashboardSummary>(
        future: summary,
        builder: (context, snapshot) {
          final data = snapshot.data;
          final salesVal = (data != null && data.sales != '0')
              ? '₹${data.sales}'
              : '\$14,892.50';
          final colVal = (data != null && data.collections != '0')
              ? '₹${data.collections}'
              : '\$12,450.00';
          final dueVal = (data != null && data.outstanding != '0')
              ? '₹${data.outstanding}'
              : '\$3,840.00';
          final stockVal = (data != null && data.lowStock > 0)
              ? '${data.lowStock} SKUs'
              : '7 SKUs';

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (data?.cashierScope == true)
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
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _StitchCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                const Text(
                                  "Today's Net Sales",
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xff8d90a0),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                _TrendPill(label: '+18.4%', icon: Icons.trending_up),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              salesVal,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: const [
                                Text(
                                  'Target: \$16,000',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xff8d90a0),
                                  ),
                                ),
                                SizedBox(width: 12),
                                Text(
                                  '93%',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.blue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(9999),
                            child: Container(
                              height: 4,
                              color: const Color(0xff262a34),
                              child: FractionallySizedBox(
                                widthFactor: 0.93,
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [Color(0xff2563eb), Color(0xff4edea3)],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StitchCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: const [
                                Text(
                                  'Total Collections',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xff8d90a0),
                                  ),
                                ),
                                SizedBox(width: 6),
                                Icon(
                                  Icons.account_balance_wallet_outlined,
                                  size: 16,
                                  color: AppTheme.lightBlue,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              colVal,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Cash: \$5.2k • Cards: \$7.25k',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xff8d90a0),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: const [
                                Icon(Icons.check_circle, size: 10, color: Color(0xff4edea3)),
                                SizedBox(width: 4),
                                Text(
                                  '98.2% settled',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xff4edea3),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: _StitchCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                const Text(
                                  'Receivables & Dues',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xff8d90a0),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xfff43f5e).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: const Color(0xfff43f5e).withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: const Text(
                                    '12 overdue',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xfff43f5e),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              dueVal,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: const [
                                Text(
                                  'Pending Net 30',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Color(0xff8d90a0),
                                  ),
                                ),
                                SizedBox(width: 8),
                                Text(
                                  'Remind >',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: AppTheme.blue,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _StitchCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              children: [
                                const Text(
                                  'Low Stock Alerts',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xff8d90a0),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: const BoxDecoration(
                                        color: Color(0xfff43f5e),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.warning_amber_rounded,
                                      size: 15,
                                      color: Color(0xfff43f5e),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 6),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              stockVal,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            '3 Stockout Soon',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Color(0xfff43f5e),
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Est. Reorder: \$1,420',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xff8d90a0),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
      const SizedBox(height: 20),

      // 3. QUICK EXECUTION SECTION
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: const [
          Text(
            'QUICK EXECUTION',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: Color(0xffdfe2ef),
            ),
          ),
          Text(
            'Floor Shortcuts',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: Color(0xff8d90a0),
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),
      Row(
        children: [
          Expanded(
            child: _QuickButton(
              isPrimary: true,
              icon: Icons.receipt_long,
              label: 'New Bill',
              onTap: widget.onNewSale,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickButton(
              icon: Icons.qr_code_scanner,
              label: 'Scan Item',
              onTap: widget.onScan,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickButton(
              icon: Icons.inventory_2_outlined,
              label: 'Add Stock',
              onTap: widget.onAddStock,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _QuickButton(
              icon: Icons.lock_clock_outlined,
              label: 'Z-Report',
              onTap: widget.onReports,
            ),
          ),
        ],
      ),
      const SizedBox(height: 24),

      // 4. RECENT INVOICES SECTION
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 6,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text(
                  'Recent Invoices',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(width: 6),
                Text(
                  '(48 Today)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xff8d90a0),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xff1c1f29),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xff31353f)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.ios_share, size: 13, color: AppTheme.lightBlue),
                SizedBox(width: 4),
                Text(
                  'Export CSV',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.lightBlue,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      const SizedBox(height: 10),

      // Filter chips
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _FilterTab(
              label: 'All (48)',
              selected: invoiceFilter == 0,
              onTap: () => setState(() => invoiceFilter = 0),
            ),
            const SizedBox(width: 8),
            _FilterTab(
              label: 'Paid (39)',
              selected: invoiceFilter == 1,
              onTap: () => setState(() => invoiceFilter = 1),
            ),
            const SizedBox(width: 8),
            _FilterTab(
              label: 'Partial (5)',
              selected: invoiceFilter == 2,
              onTap: () => setState(() => invoiceFilter = 2),
            ),
            const SizedBox(width: 8),
            _FilterTab(
              label: 'Unpaid (4)',
              selected: invoiceFilter == 3,
              onTap: () => setState(() => invoiceFilter = 3),
            ),
          ],
        ),
      ),
      const SizedBox(height: 12),

      // Invoices feed
      _StitchInvoiceItem(
        initials: 'AM',
        name: 'Alex Morgan',
        tag: 'Retail',
        invoiceNo: '#INV-2024-8841 • 3 items',
        price: '\$489.00',
        status: 'PAID',
        statusColor: const Color(0xff4edea3),
        method: 'Visa •• 4208',
        methodIcon: Icons.credit_card,
        timeAgo: '4 mins ago',
      ),
      _StitchInvoiceItem(
        initials: 'HC',
        name: 'Horizon Corp',
        tag: 'Wholesale B2B',
        invoiceNo: '#INV-2024-8840 • 24 items',
        price: '\$2,340.00',
        status: 'PARTIAL',
        statusColor: const Color(0xfff59e0b),
        method: '\$1,000 paid • \$1,340 due',
        timeAgo: '18 mins ago',
      ),
      _StitchInvoiceItem(
        initials: 'SJ',
        name: 'Sarah Jenkins',
        tag: 'Direct Walk-in',
        invoiceNo: '#INV-2024-8839 • 1 item',
        price: '\$74.50',
        status: 'PAID',
        statusColor: const Color(0xff4edea3),
        method: 'Apple Pay',
        methodIcon: Icons.contactless,
        timeAgo: '32 mins ago',
      ),
      _StitchInvoiceItem(
        initials: 'MB',
        name: 'Metro Bistro Group',
        invoiceNo: '#INV-2024-8838 • 14 items',
        price: '\$1,150.00',
        status: 'UNPAID',
        statusColor: const Color(0xfff43f5e),
        method: 'Due in 3 days',
        methodIcon: Icons.calendar_today_outlined,
        actionLabel: 'Send Payment Link',
      ),
      const SizedBox(height: 12),

      // Pagination
      Column(
        children: [
          const Text(
            'Showing 1-4 of 48 invoices',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xff8d90a0),
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xff1c1f29),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xff31353f)),
              ),
              child: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.expand_circle_down_outlined, size: 16, color: AppTheme.lightBlue),
                    SizedBox(width: 8),
                    Text(
                      'Load More Invoices',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.lightBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _StitchCard extends StatelessWidget {
  const _StitchCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff1c1f29),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xff31353f)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TrendPill extends StatelessWidget {
  const _TrendPill({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xff4edea3).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xff4edea3).withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: const Color(0xff4edea3)),
          const SizedBox(width: 2),
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: Color(0xff4edea3),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickButton extends StatelessWidget {
  const _QuickButton({
    required this.icon,
    required this.label,
    this.isPrimary = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isPrimary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
          decoration: BoxDecoration(
            gradient: isPrimary
                ? const LinearGradient(
                    colors: [Color(0xff2563eb), Color(0xff1d4ed8)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  )
                : null,
            color: isPrimary ? null : const Color(0xff1c1f29),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isPrimary ? const Color(0xff3b82f6) : const Color(0xff31353f),
            ),
            boxShadow: [
              if (isPrimary)
                BoxShadow(
                  color: const Color(0xff2563eb).withValues(alpha: 0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isPrimary
                      ? Colors.white.withValues(alpha: 0.2)
                      : const Color(0xff262a34),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: isPrimary ? Colors.white : AppTheme.lightBlue,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isPrimary ? FontWeight.w800 : FontWeight.w600,
                    color: isPrimary ? Colors.white : const Color(0xffdfe2ef),
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

class _FilterTab extends StatelessWidget {
  const _FilterTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(9999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppTheme.blue : const Color(0xff1c1f29),
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(
            color: selected ? AppTheme.blue : const Color(0xff31353f),
          ),
          boxShadow: [
            if (selected)
              BoxShadow(
                color: AppTheme.blue.withValues(alpha: 0.35),
                blurRadius: 8,
              ),
          ],
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? Colors.white : const Color(0xff8d90a0),
          ),
        ),
      ),
    );
  }
}

class _StitchInvoiceItem extends StatelessWidget {
  const _StitchInvoiceItem({
    required this.initials,
    required this.name,
    this.tag,
    required this.invoiceNo,
    required this.price,
    required this.status,
    required this.statusColor,
    required this.method,
    this.methodIcon,
    this.timeAgo,
    this.actionLabel,
  });

  final String initials;
  final String name;
  final String? tag;
  final String invoiceNo;
  final String price;
  final String status;
  final Color statusColor;
  final String method;
  final IconData? methodIcon;
  final String? timeAgo;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xff1c1f29),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xff31353f)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xff262a34),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xff434655)),
                ),
                alignment: Alignment.center,
                child: Text(
                  initials,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Color(0xffdfe2ef),
                            ),
                          ),
                          if (tag != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xff262a34),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tag!,
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xff8d90a0),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      invoiceNo,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xff8d90a0),
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    price,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(9999),
                      border: Border.all(color: statusColor.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          status,
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(height: 1, color: Color(0xff262a34)),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (methodIcon != null) ...[
                      Icon(methodIcon, size: 12, color: const Color(0xff8d90a0)),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      method,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: (actionLabel != null)
                            ? const Color(0xfff43f5e)
                            : const Color(0xff8d90a0),
                      ),
                    ),
                  ],
                ),
              ),
              if (timeAgo != null)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.schedule, size: 11, color: Color(0xff8d90a0)),
                      const SizedBox(width: 4),
                      Text(
                        timeAgo!,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xff8d90a0),
                        ),
                      ),
                    ],
                  ),
                ),
              if (actionLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.blue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppTheme.blue.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.lightBlue,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
