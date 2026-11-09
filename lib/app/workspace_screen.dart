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
import '../core/widgets/executive_ui.dart';

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
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Sales',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: 'Inventory',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu),
            selectedIcon: Icon(Icons.menu_open),
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
    appBar: AppBar(
      title: Text(menuOnly ? 'More' : 'Smart Billing'),
      actions: [
        IconButton(
          tooltip: 'Search business',
          icon: const Icon(Icons.search),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BusinessSearchScreen(membership: membership),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Notifications',
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => NotificationsScreen(
                organizationId: membership.organizationId,
              ),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Switch business',
          icon: const Icon(Icons.swap_horiz),
          onPressed: () => context.go('/businesses'),
        ),
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
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        children: [
          ExecutiveStoreRibbon(
            roleLabel: membership.role == OrganizationRole.owner
                ? 'SuperAdmin / Owner'
                : membership.role.label,
          ),
          if (!menuOnly)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.blue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.storefront_outlined,
                            color: AppTheme.blue,
                            size: 28,
                          ),
                        ),
                        ExecutiveBadge(
                          label: membership.role.label.toUpperCase(),
                          color: AppTheme.blue,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      membership.organizationName,
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Your business workspace',
                      style: TextStyle(color: Color(0xff8d90a0)),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Business setup saved. Your account is linked to this organization.',
                      style: TextStyle(color: Color(0xff8d90a0)),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          if (!menuOnly)
            DashboardPanel(
              key: ValueKey(membership.organizationId),
              organizationId: membership.organizationId,
            ),
          const SizedBox(height: 20),
          Text(
            menuOnly ? 'Business tools' : 'Quick actions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
          ),
          const SizedBox(height: 10),
          if (menuOnly)
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
      ),
    ),
  );
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
