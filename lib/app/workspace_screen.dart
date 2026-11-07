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
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'Sales',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Inventory',
          ),
          NavigationDestination(icon: Icon(Icons.menu), label: 'More'),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (!menuOnly)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.storefront_outlined,
                      color: AppTheme.blue,
                      size: 40,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      membership.organizationName,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    const Text('Your business workspace'),
                    const SizedBox(height: 16),
                    Text(
                      'Business setup saved. Your account is linked to this organization.',
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 20),
          if (!menuOnly)
            DashboardPanel(
              key: ValueKey(membership.organizationId),
              organizationId: membership.organizationId,
            ),
          const SizedBox(height: 20),
          Text(
            menuOnly ? 'Business tools' : 'Quick actions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          if (menuOnly)
            Card(
              child: ListTile(
                title: const Text('Roles and permissions'),
                leading: const Icon(Icons.info_outline),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        RolePermissionsScreen(membership: membership),
                  ),
                ),
              ),
            ),
          if (membership.role == OrganizationRole.owner)
            Card(
              child: ListTile(
                title: const Text('Help & requests'),
                leading: const Icon(Icons.help_outline),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SupportScreen(
                      actorId:
                          ref.read(authSessionProvider).asData?.value?.userId ??
                          '',
                      organizationId: membership.organizationId,
                    ),
                  ),
                ),
              ),
            ),
          if (membership.role == OrganizationRole.owner)
            Card(
              child: ListTile(
                title: const Text('Subscription'),
                leading: const Icon(Icons.card_membership_outlined),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SubscriptionScreen(
                      organizationId: membership.organizationId,
                    ),
                  ),
                ),
              ),
            ),
          if (membership.role == OrganizationRole.owner)
            Card(
              child: ListTile(
                title: const Text('Business settings'),
                leading: const Icon(Icons.settings_outlined),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(
                      organizationId: membership.organizationId,
                      onSaved: () {
                        final id = ref
                            .read(authSessionProvider)
                            .asData
                            ?.value
                            ?.userId;
                        if (id != null) ref.invalidate(membershipProvider(id));
                      },
                    ),
                  ),
                ),
              ),
            ),
          if ([
            OrganizationRole.owner,
            OrganizationRole.accountant,
          ].contains(membership.role))
            Card(
              child: ListTile(
                title: const Text('Audit history'),
                leading: const Icon(Icons.history),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) =>
                        AuditScreen(organizationId: membership.organizationId),
                  ),
                ),
              ),
            ),
          if ([
            OrganizationRole.owner,
            OrganizationRole.accountant,
          ].contains(membership.role))
            Card(
              child: ListTile(
                title: const Text('Reports'),
                leading: const Icon(Icons.bar_chart),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ReportsScreen(
                      organizationId: membership.organizationId,
                    ),
                  ),
                ),
              ),
            ),
          Card(
            child: ListTile(
              title: const Text('Sales invoices'),
              leading: const Icon(Icons.receipt_long_outlined),
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
          ),
          if (membership.role != OrganizationRole.cashier)
            Card(
              child: ListTile(
                title: const Text('Customer aging'),
                leading: const Icon(Icons.schedule_outlined),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => CustomerAgingScreen(
                      organizationId: membership.organizationId,
                    ),
                  ),
                ),
              ),
            ),
          if (membership.role != OrganizationRole.cashier)
            Card(
              child: ListTile(
                title: const Text('Customers'),
                leading: const Icon(Icons.people_outline),
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
            ),
          if (membership.role != OrganizationRole.cashier)
            Card(
              child: ListTile(
                title: const Text('Purchases'),
                leading: const Icon(Icons.shopping_bag_outlined),
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
            ),
          if (membership.role != OrganizationRole.cashier)
            Card(
              child: ListTile(
                title: const Text('Suppliers'),
                leading: const Icon(Icons.local_shipping_outlined),
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
            ),
          if (membership.role != OrganizationRole.cashier)
            Card(
              child: ListTile(
                title: const Text('Stock valuation'),
                leading: const Icon(Icons.calculate_outlined),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StockValuationScreen(
                      organizationId: membership.organizationId,
                    ),
                  ),
                ),
              ),
            ),
          Card(
            child: ListTile(
              title: const Text('Stock'),
              leading: const Icon(Icons.warehouse_outlined),
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
          ),
          Card(
            child: ListTile(
              title: const Text('Products & services'),
              leading: const Icon(Icons.inventory_2_outlined),
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
          ),
          if (membership.role == OrganizationRole.owner)
            Card(
              child: ListTile(
                title: const Text('Team access'),
                leading: const Icon(Icons.manage_accounts_outlined),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => MembersScreen(
                      organizationId: membership.organizationId,
                    ),
                  ),
                ),
              ),
            ),
          if (membership.role == OrganizationRole.owner)
            Card(
              child: ListTile(
                leading: const Icon(Icons.group_outlined),
                title: const Text('Team invitations'),
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
            ),
          if ([
            OrganizationRole.owner,
            OrganizationRole.manager,
          ].contains(membership.role))
            Card(
              child: ListTile(
                title: const Text('Stock approvals'),
                leading: const Icon(Icons.fact_check_outlined),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => StockApprovalsScreen(
                      organizationId: membership.organizationId,
                      canReview: membership.role == OrganizationRole.owner,
                    ),
                  ),
                ),
              ),
            ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline, color: AppTheme.teal),
              title: Text('Business profile'),
              subtitle: Text('Organization and default outlet created'),
            ),
          ),
          const Card(
            child: ListTile(
              leading: Icon(Icons.lock_outline),
              title: Text('Account access'),
              subtitle: Text('Protected by your active business membership'),
            ),
          ),
        ],
      ),
    ),
  );
}
