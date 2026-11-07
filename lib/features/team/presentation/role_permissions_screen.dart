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

  static const _roles = [
    (
      'Superadmin',
      Icons.admin_panel_settings_outlined,
      'Platform-wide',
      'Browse businesses, review and reply to support requests, create plan drafts, and assign active subscription plans. Access to a shop’s billing and inventory comes from a separate business membership.',
    ),
    (
      'Business Owner',
      Icons.storefront_outlined,
      'One business at a time',
      'Set up a business, invite staff, manage team access and business settings, issue invoices, process sales returns, manage purchases and stock, approve stock adjustments, view reports and audit history, and view the assigned subscription.',
    ),
    (
      'Manager',
      Icons.manage_accounts_outlined,
      'Assigned business',
      'Issue invoices, manage products, customers and suppliers, receive purchases and record supplier payments, and submit stock adjustment requests for the owner to approve.',
    ),
    (
      'Cashier',
      Icons.point_of_sale_outlined,
      'Assigned business',
      'Create and issue sales, take checkout payments, and look up products, prices and available stock for billing.',
    ),
    (
      'Accountant',
      Icons.calculate_outlined,
      'Assigned business',
      'Review invoices, customer balances and supplier purchases, and access financial reports, exports and audit history.',
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
            Text('Business setup', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'A business owner can set up their own shop from Your businesses. '
              'Superadmin manages subscriptions from Platform administration.',
            ),
            if (isPlatformAdmin || current != null) ...[
              const SizedBox(height: 16),
              if (isPlatformAdmin) const Text('Your platform role: Superadmin'),
              if (current != null)
                Text(
                  'Your role in ${current.organizationName}: ${current.role.label}',
                ),
            ],
            const SizedBox(height: 16),
            for (final (name, icon, scope, permissions) in _roles)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, color: theme.colorScheme.primary),
                      const SizedBox(height: 8),
                      Text(name, style: theme.textTheme.titleMedium),
                      Text(scope, style: theme.textTheme.labelMedium),
                      const SizedBox(height: 8),
                      Text(permissions),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
