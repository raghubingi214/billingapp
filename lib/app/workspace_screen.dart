import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../features/auth/presentation/auth_providers.dart';
import '../shared/domain/membership.dart';
import '../features/team/presentation/invitations_screen.dart';
import '../features/team/presentation/members_screen.dart';
import '../features/team/presentation/role_permissions_screen.dart';
import '../features/catalog/presentation/catalog_screen.dart';
import '../features/inventory/presentation/inventory_screen.dart';
import '../features/inventory/presentation/stock_approvals_screen.dart';
import '../features/suppliers/presentation/suppliers_screen.dart';
import '../features/purchases/presentation/purchases_screen.dart';
import '../features/customers/presentation/customers_screen.dart';
import '../features/sales/presentation/sales_screen.dart';
import '../features/dashboard/presentation/dashboard_panel.dart';
import '../features/reports/presentation/reports_screen.dart';
import '../features/reports/presentation/customer_aging_screen.dart';
import '../features/reports/presentation/stock_valuation_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/sales/presentation/drafts_screen.dart';
import '../features/audit/presentation/audit_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/onboarding/presentation/onboarding_providers.dart';
import 'theme/app_theme.dart';
import '../features/support/presentation/support_screen.dart';
import '../features/subscriptions/presentation/subscription_screen.dart';
import '../features/search/presentation/business_search_screen.dart';

class WorkspaceScreen extends StatefulWidget {
  const WorkspaceScreen({super.key, required this.membership});
  final Membership membership;
  @override
  State<WorkspaceScreen> createState() => _WorkspaceScreenState();
}

class _WorkspaceScreenState extends State<WorkspaceScreen> {
  int selected = 0;
  int revision = 0;
  @override
  void didUpdateWidget(WorkspaceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.membership.organizationId !=
        widget.membership.organizationId) {
      selected = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final membership = widget.membership;
    final canSell = membership.role != OrganizationRole.accountant;
    return Scaffold(
      body: switch (selected) {
        1 => SalesScreen(
          key: ValueKey('sales:$revision'),
          organizationId: membership.organizationId,
          canSell: canSell,
          canReturn: membership.role == OrganizationRole.owner,
          canRemind: membership.role != OrganizationRole.cashier,
        ),
        2 => InventoryScreen(
          organizationId: membership.organizationId,
          canCount: membership.role == OrganizationRole.owner,
          canRequest: membership.role == OrganizationRole.manager,
          canReadHistory: membership.role != OrganizationRole.cashier,
        ),
        3 => _WorkspaceHome(membership: membership, menuOnly: true),
        _ => _WorkspaceHome(
          key: ValueKey('home:$revision'),
          membership: membership,
        ),
      },
      floatingActionButton: canSell
          ? FloatingActionButton.extended(
              onPressed: () async {
                await Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) =>
                        DraftsScreen(organizationId: membership.organizationId),
                  ),
                );
                if (mounted) setState(() => revision++);
              },
              icon: const Icon(Icons.add),
              label: const Text('New Sale'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selected,
        onDestinationSelected: (index) => setState(() => selected = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.point_of_sale_outlined),
            selectedIcon: Icon(Icons.point_of_sale),
            label: 'POS',
          ),
          NavigationDestination(
            icon: Badge(
              label: Text('7'),
              child: Icon(Icons.inventory_2_outlined),
            ),
            selectedIcon: Badge(
              label: Text('7'),
              child: Icon(Icons.inventory_2),
            ),
            label: 'Inventory',
          ),
          NavigationDestination(
            icon: Icon(Icons.more_horiz),
            selectedIcon: Icon(Icons.more_horiz),
            label: 'More',
          ),
        ],
      ),
    );
  }
}

class _WorkspaceHome extends ConsumerWidget {
  const _WorkspaceHome({
    super.key,
    required this.membership,
    this.menuOnly = false,
  });
  final bool menuOnly;
  final Membership membership;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: menuOnly
        ? AppBar(
            title: const Text('More'),
            actions: [
              IconButton(
                tooltip: 'Sign out',
                icon: const Icon(Icons.logout),
                onPressed: () async {
                  try {
                    await ref.read(authRepositoryProvider).signOut();
                  } catch (_) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Could not sign out. Please try again.'),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          )
        : null,
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          if (!menuOnly) ...[
            _StitchExecutiveHeader(membership: membership),
            const SizedBox(height: 16),
            DashboardPanel(
              key: ValueKey(membership.organizationId),
              organizationId: membership.organizationId,
              onNewSale: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => DraftsScreen(
                    organizationId: membership.organizationId,
                  ),
                ),
              ),
              onScan: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BusinessSearchScreen(
                    membership: membership,
                  ),
                ),
              ),
              onAddStock: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => InventoryScreen(
                    organizationId: membership.organizationId,
                    canCount: membership.role == OrganizationRole.owner,
                    canRequest: membership.role == OrganizationRole.manager,
                    canReadHistory: true,
                  ),
                ),
              ),
              onReports: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReportsScreen(
                    organizationId: membership.organizationId,
                  ),
                ),
              ),
            ),
          ],
          if (menuOnly) ...[
            Text(
              'Business tools',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
            ),
            const SizedBox(height: 10),
            _ToolCard(
              title: 'Roles and permissions',
              subtitle: 'View access matrix across merchant roles',
              icon: Icons.shield_outlined,
              color: AppTheme.blue,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RolePermissionsScreen(membership: membership),
                ),
              ),
            ),
          if (membership.role == OrganizationRole.owner)
            _ToolCard(
              title: 'Help & requests',
              subtitle: 'Platform support, tickets and help threads',
              icon: Icons.help_outline,
              color: AppTheme.sapphire,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SupportScreen(
                    actorId: ref.read(authSessionProvider).asData?.value?.userId ?? '',
                    organizationId: membership.organizationId,
                  ),
                ),
              ),
            ),
          if (membership.role == OrganizationRole.owner)
            _ToolCard(
              title: 'Subscription',
              subtitle: 'Active plan, entitlements and billing limits',
              icon: Icons.card_membership_outlined,
              color: AppTheme.emerald,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SubscriptionScreen(
                    organizationId: membership.organizationId,
                  ),
                ),
              ),
            ),
          if (membership.role == OrganizationRole.owner)
            _ToolCard(
              title: 'Business settings',
              subtitle: 'GSTIN, invoice numbering, tax & store profile',
              icon: Icons.settings_outlined,
              color: AppTheme.navy,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SettingsScreen(
                    organizationId: membership.organizationId,
                    onSaved: () {
                      final id = ref.read(authSessionProvider).asData?.value?.userId;
                      if (id != null) ref.invalidate(membershipProvider(id));
                    },
                  ),
                ),
              ),
            ),
          if ([OrganizationRole.owner, OrganizationRole.accountant].contains(membership.role))
            _ToolCard(
              title: 'Audit history',
              subtitle: 'Immutable record of operations & adjustments',
              icon: Icons.history,
              color: const Color(0xff6366F1),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AuditScreen(organizationId: membership.organizationId),
                ),
              ),
            ),
          if ([OrganizationRole.owner, OrganizationRole.accountant].contains(membership.role))
            _ToolCard(
              title: 'Reports',
              subtitle: 'Financial statements, sales and tax breakdowns',
              icon: Icons.bar_chart,
              color: AppTheme.emerald,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ReportsScreen(organizationId: membership.organizationId),
                ),
              ),
            ),
          _ToolCard(
            title: 'Sales invoices',
            subtitle: 'Recent issued bills, receipts and payments',
            icon: Icons.receipt_long_outlined,
            color: AppTheme.blue,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SalesScreen(
                  organizationId: membership.organizationId,
                  canSell: membership.role != OrganizationRole.accountant,
                  canReturn: membership.role == OrganizationRole.owner,
                  canRemind: membership.role != OrganizationRole.cashier,
                ),
              ),
            ),
          ),
          if (membership.role != OrganizationRole.cashier)
            _ToolCard(
              title: 'Customer aging',
              subtitle: 'Outstanding buckets and overdue payment triage',
              icon: Icons.schedule_outlined,
              color: AppTheme.amber,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CustomerAgingScreen(
                    organizationId: membership.organizationId,
                  ),
                ),
              ),
            ),
          if (membership.role != OrganizationRole.cashier)
            _ToolCard(
              title: 'Customers',
              subtitle: 'Client directories, credit limits and balances',
              icon: Icons.people_outline,
              color: const Color(0xff0EA5E9),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => CustomersScreen(
                    organizationId: membership.organizationId,
                    canManage: [
                      OrganizationRole.owner,
                      OrganizationRole.manager,
                    ].contains(membership.role),
                  ),
                ),
              ),
            ),
          if (membership.role != OrganizationRole.cashier)
            _ToolCard(
              title: 'Purchases',
              subtitle: 'Vendor bills, inbound goods and payables',
              icon: Icons.shopping_bag_outlined,
              color: const Color(0xff8B5CF6),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PurchasesScreen(
                    organizationId: membership.organizationId,
                    canReceive: [
                      OrganizationRole.owner,
                      OrganizationRole.manager,
                    ].contains(membership.role),
                  ),
                ),
              ),
            ),
          if (membership.role != OrganizationRole.cashier)
            _ToolCard(
              title: 'Suppliers',
              subtitle: 'Vendor profiles, tax details and terms',
              icon: Icons.local_shipping_outlined,
              color: const Color(0xff14B8A6),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => SuppliersScreen(
                    organizationId: membership.organizationId,
                    canManage: [
                      OrganizationRole.owner,
                      OrganizationRole.manager,
                    ].contains(membership.role),
                  ),
                ),
              ),
            ),
          if (membership.role != OrganizationRole.cashier)
            _ToolCard(
              title: 'Stock valuation',
              subtitle: 'Weighted-average cost and asset totals',
              icon: Icons.calculate_outlined,
              color: AppTheme.blue,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StockValuationScreen(
                    organizationId: membership.organizationId,
                  ),
                ),
              ),
            ),
          _ToolCard(
            title: 'Stock',
            subtitle: 'Inventory on hand and outlet positions',
            icon: Icons.warehouse_outlined,
            color: const Color(0xffD97706),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => InventoryScreen(
                  organizationId: membership.organizationId,
                  canCount: membership.role == OrganizationRole.owner,
                  canRequest: membership.role == OrganizationRole.manager,
                  canReadHistory: membership.role != OrganizationRole.cashier,
                ),
              ),
            ),
          ),
          _ToolCard(
            title: 'Products & services',
            subtitle: 'Master catalog, SKU codes and price master',
            icon: Icons.inventory_2_outlined,
            color: AppTheme.blue,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => CatalogScreen(
                  organizationId: membership.organizationId,
                  canManage: [
                    OrganizationRole.owner,
                    OrganizationRole.manager,
                  ].contains(membership.role),
                ),
              ),
            ),
          ),
          if (membership.role == OrganizationRole.owner)
            _ToolCard(
              title: 'Team access',
              subtitle: 'Staff memberships and role assignments',
              icon: Icons.manage_accounts_outlined,
              color: const Color(0xffEC4899),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => MembersScreen(
                    organizationId: membership.organizationId,
                  ),
                ),
              ),
            ),
          if (membership.role == OrganizationRole.owner)
            _ToolCard(
              title: 'Team invitations',
              subtitle: 'Pending staff invitations and verification',
              icon: Icons.group_outlined,
              color: AppTheme.sapphire,
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => InvitationsScreen(
                    organizationId: membership.organizationId,
                    onAccepted: () {},
                  ),
                ),
              ),
            ),
          if ([OrganizationRole.owner, OrganizationRole.manager].contains(membership.role))
            _ToolCard(
              title: 'Stock approvals',
              subtitle: 'Manager adjustment requests awaiting review',
              icon: Icons.fact_check_outlined,
              color: AppTheme.amber,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => StockApprovalsScreen(
                    organizationId: membership.organizationId,
                    canReview: membership.role == OrganizationRole.owner,
                  ),
                ),
              ),
            ),
          _ToolCard(
            title: 'Business profile',
            subtitle: 'Organization and default outlet created',
            icon: Icons.check_circle_outline,
            color: AppTheme.emerald,
            onTap: null,
          ),
          _ToolCard(
            title: 'Account access',
            subtitle: 'Protected by your active business membership',
            icon: Icons.lock_outline,
            color: const Color(0xff64748B),
            onTap: null,
          ),
          ],
        ],
      ),
    ),
  );
}

class _StitchExecutiveHeader extends StatelessWidget {
  const _StitchExecutiveHeader({required this.membership});
  final Membership membership;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xff1c1f29),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xff31353f)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.network(
                      'https://lh3.googleusercontent.com/aida-public/AB6AXuD38hbvwXevnJ4MQJQNos0JSPhiTKrVCWgN5mK-xJmKgr15fCkVMIaNBsNXlS8QgJ7gcnFfmrK1elgL7s5ScE38gD8GXb14BJfPp9HkUBJGICs2MFBLi3klLflarmkoNHpsaoAubBkhcuaGrB7gYxwWxfKnusF2g4sqBDroBr1wHSUCXwcA4V_J2Qt-Z11AI2JPWOmnVBKC8jkZdtscKoEEy6vKb4fTgnAOufR3q002AqY2yR3NCDlGoToKXGQ6slP5S0sDx7FZd4w',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => const Center(
                        child: Text(
                          'MV',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                            color: Color(0xffb4c5ff),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: const Color(0xff4edea3),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xff0a0e17),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: () => context.go('/businesses'),
                borderRadius: BorderRadius.circular(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      membership.role == OrganizationRole.owner
                          ? 'Marcus Vance • SuperAdmin'
                          : 'Operator • ${membership.role.label}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: Color(0xff8d90a0),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            membership.organizationName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.keyboard_arrow_down,
                          size: 18,
                          color: AppTheme.blue,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => BusinessSearchScreen(membership: membership),
                ),
              ),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xff1c1f29),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xff31353f)),
                ),
                child: const Icon(
                  Icons.qr_code_scanner,
                  size: 18,
                  color: AppTheme.lightBlue,
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => NotificationsScreen(
                    organizationId: membership.organizationId,
                  ),
                ),
              ),
              borderRadius: BorderRadius.circular(10),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xff1c1f29),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xff31353f)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(
                      Icons.notifications_outlined,
                      size: 19,
                      color: Color(0xffdfe2ef),
                    ),
                    Positioned(
                      right: 4,
                      top: 4,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: Color(0xfff43f5e),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 12,
                          minHeight: 12,
                        ),
                        child: const Text(
                          '2',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
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
                  Container(
                    width: 6,
                    height: 6,
                    decoration: const BoxDecoration(
                      color: Color(0xff4edea3),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'Store Open',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xff4edea3),
                    ),
                  ),
                  const Text(
                    ' • Reg #01 Active',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Color(0xff8d90a0),
                    ),
                  ),
                ],
              ),
            ),
            const FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.point_of_sale, size: 13, color: Color(0xff8d90a0)),
                  SizedBox(width: 4),
                  Text(
                    'Drawer: ',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xff8d90a0),
                    ),
                  ),
                  Text(
                    '\$1,250.00',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.blue,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.title,
    this.subtitle,
    required this.icon,
    required this.color,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final Color color;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xffdfe2ef),
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xff8d90a0),
                ),
              )
            : null,
        trailing: trailing ?? (onTap != null ? const Icon(Icons.chevron_right, size: 20, color: Color(0xff8d90a0)) : null),
        onTap: onTap,
      ),
    );
  }
}
