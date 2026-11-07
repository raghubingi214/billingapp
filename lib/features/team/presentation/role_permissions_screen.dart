import 'package:flutter/material.dart';
import '../../../shared/domain/membership.dart';

class RolePermissionsScreen extends StatelessWidget {
  const RolePermissionsScreen({
    super.key,
    this.membership,
    this.isPlatformAdmin = false,
  });

  final Membership? membership;
  final bool isPlatformAdmin;

  static const _roles = <_RoleAccess>[
    _RoleAccess(
      name: 'Superadmin',
      scope: 'Platform-wide access',
      icon: Icons.admin_panel_settings_outlined,
      summary:
          'Operates the Smart Billing platform across businesses. This role does not automatically grant access to a shop’s invoices, customers, or stock.',
      permissions: [
        _PermissionGroup('Platform', [
          _Permission('Platform overview and business counts', 'View'),
          _Permission('Browse business names and account status', 'View'),
          _Permission(
            'Assign an active subscription plan to a business',
            'Manage',
          ),
          _Permission('Review support requests and send replies', 'Manage'),
        ]),
        _PermissionGroup('Business records', [
          _Permission(
            'Invoices, customers, suppliers, payments, and inventory',
            'No access by platform role',
          ),
          _Permission(
            'Shop settings and shop team',
            'No access by platform role',
          ),
        ]),
      ],
    ),
    _RoleAccess(
      name: 'Business Owner',
      scope: 'Full access to businesses they own',
      icon: Icons.storefront_outlined,
      summary:
          'Sets up and operates a shop, manages its staff and settings, and can use the business modules below.',
      permissions: [
        _PermissionGroup('Business and team', [
          _Permission('Create a business and configure its profile', 'Manage'),
          _Permission(
            'Invite staff, change staff roles, revoke access',
            'Manage',
          ),
          _Permission('Business settings and invoice configuration', 'Manage'),
          _Permission('View current subscription and usage', 'View'),
        ]),
        _PermissionGroup('Sales and customers', [
          _Permission('Products, prices, and product images', 'Manage'),
          _Permission('Customers and customer balances', 'Manage'),
          _Permission('Create, edit, and issue invoices', 'Manage'),
          _Permission('Record customer receipts and refunds', 'Manage'),
          _Permission('Review and post sales returns', 'Manage'),
        ]),
        _PermissionGroup('Purchases and inventory', [
          _Permission(
            'Suppliers, purchase receipts, and supplier payments',
            'Manage',
          ),
          _Permission('Purchase returns and supplier credit refunds', 'Manage'),
          _Permission('Stock history and adjustment approvals', 'Manage'),
        ]),
        _PermissionGroup('Reports and support', [
          _Permission(
            'Financial, customer aging, and stock valuation reports',
            'View',
          ),
          _Permission(
            'Export available reports and customer statements',
            'Export',
          ),
          _Permission('Business audit history', 'View'),
          _Permission('Create support requests and view replies', 'Manage'),
          _Permission(
            'Manage customer reminder consent and send reminders',
            'Manage',
          ),
        ]),
      ],
    ),
    _RoleAccess(
      name: 'Manager',
      scope: 'Operational access to an assigned business',
      icon: Icons.manage_accounts_outlined,
      summary:
          'Runs day-to-day sales, purchasing, and stock work. A manager cannot change business ownership, staff access, or owner-only settings.',
      permissions: [
        _PermissionGroup('Sales and customers', [
          _Permission('Products, prices, and product images', 'Manage'),
          _Permission('Customer and supplier records', 'Manage'),
          _Permission('Create and issue invoices; record receipts', 'Manage'),
          _Permission('Review sales and customer ledgers', 'View'),
          _Permission('Post sales returns or refunds', 'Not permitted'),
        ]),
        _PermissionGroup('Purchases and inventory', [
          _Permission(
            'Receive purchases and record supplier payments',
            'Manage',
          ),
          _Permission('Purchase returns and supplier credit refunds', 'Manage'),
          _Permission('Review stock and submit adjustment requests', 'Manage'),
          _Permission('Approve stock adjustments', 'Not permitted'),
        ]),
        _PermissionGroup('Reports and team', [
          _Permission('Customer aging and stock valuation reports', 'View'),
          _Permission(
            'Financial reports and business audit history',
            'Not permitted',
          ),
          _Permission(
            'Invite staff, change roles, and business settings',
            'Not permitted',
          ),
          _Permission('Manage customer reminders', 'Manage'),
        ]),
      ],
    ),
    _RoleAccess(
      name: 'Cashier',
      scope: 'Checkout access to an assigned business',
      icon: Icons.point_of_sale_outlined,
      summary:
          'Handles checkout and can review their own sales. Financial records and business administration stay restricted.',
      permissions: [
        _PermissionGroup('Checkout', [
          _Permission('Look up products, prices, and available stock', 'View'),
          _Permission('Create and update own sales drafts', 'Manage'),
          _Permission('Issue invoices and take customer payments', 'Manage'),
          _Permission('Review own sales; see limited dashboard totals', 'View'),
        ]),
        _PermissionGroup('Restricted areas', [
          _Permission(
            'Other staff sales and customer financial reports',
            'Not permitted',
          ),
          _Permission(
            'Purchases, supplier payments, stock approvals',
            'Not permitted',
          ),
          _Permission(
            'Team access, business settings, and subscriptions',
            'Not permitted',
          ),
        ]),
      ],
    ),
    _RoleAccess(
      name: 'Accountant',
      scope: 'Financial review access to an assigned business',
      icon: Icons.calculate_outlined,
      summary:
          'Reviews business finances and reporting. This role is intended for accounting work, not changing business settings or staff access.',
      permissions: [
        _PermissionGroup('Financial records', [
          _Permission('Invoices, customer balances, and ledgers', 'View'),
          _Permission(
            'Supplier records, purchases, and payment history',
            'View',
          ),
          _Permission(
            'Financial reports, customer aging, and stock valuation',
            'View',
          ),
          _Permission('Export reports and customer statements', 'Export'),
          _Permission(
            'Review audit history and stock adjustment requests',
            'View',
          ),
        ]),
        _PermissionGroup('Restricted actions', [
          _Permission(
            'Issue invoices, collect payments, or post purchases',
            'Not permitted',
          ),
          _Permission(
            'Change products, stock, settings, or team roles',
            'Not permitted',
          ),
          _Permission('Manage customer reminders', 'Manage'),
        ]),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final current = membership;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Roles and permissions')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Who manages what?', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'A business owner creates and manages their shop. Superadmin manages the platform, business plan assignments, and support. A Superadmin only sees a shop’s private business data if separately added to that shop.',
            ),
            if (isPlatformAdmin || current != null) ...[
              const SizedBox(height: 16),
              if (isPlatformAdmin)
                const _CurrentRoleChip(label: 'Your platform role: Superadmin'),
              if (current != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _CurrentRoleChip(
                    label:
                        'Your role in ${current.organizationName}: ${current.role.label}',
                  ),
                ),
            ],
            const SizedBox(height: 20),
            Text('Role details', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final role in _roles)
              Card(
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  leading: Icon(role.icon, color: theme.colorScheme.primary),
                  title: Text(role.name),
                  subtitle: Text(role.scope),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(role.summary),
                    for (final group in role.permissions) ...[
                      const SizedBox(height: 16),
                      Text(group.title, style: theme.textTheme.titleSmall),
                      const SizedBox(height: 4),
                      for (final permission in group.permissions)
                        _PermissionRow(permission: permission),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
            const Text(
              'Access is enforced by the signed-in role and database policies. These built-in roles are fixed; this screen explains their access and does not edit permissions.',
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleAccess {
  const _RoleAccess({
    required this.name,
    required this.scope,
    required this.icon,
    required this.summary,
    required this.permissions,
  });
  final String name;
  final String scope;
  final IconData icon;
  final String summary;
  final List<_PermissionGroup> permissions;
}

class _PermissionGroup {
  const _PermissionGroup(this.title, this.permissions);
  final String title;
  final List<_Permission> permissions;
}

class _Permission {
  const _Permission(this.label, this.level);
  final String label;
  final String level;
}

class _CurrentRoleChip extends StatelessWidget {
  const _CurrentRoleChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(label),
  );
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({required this.permission});
  final _Permission permission;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final denied =
        permission.level == 'Not permitted' ||
        permission.level == 'No access by platform role';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            denied ? Icons.block_outlined : Icons.check_circle_outline,
            size: 18,
            color: denied ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(permission.label)),
          const SizedBox(width: 8),
          Text(
            permission.level,
            textAlign: TextAlign.end,
            style: theme.textTheme.labelMedium?.copyWith(
              color: denied
                  ? theme.colorScheme.error
                  : theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
