import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/domain/membership.dart';
import 'onboarding_providers.dart';
import '../../team/presentation/invitations_screen.dart';
import '../../team/presentation/role_permissions_screen.dart';
import '../../platform/presentation/platform_screen.dart';

class OrganizationPickerScreen extends ConsumerWidget {
  const OrganizationPickerScreen({
    super.key,
    required this.userId,
    required this.onSelected,
    required this.onCreate,
    this.onSignOut,
  });
  final String userId;
  final ValueChanged<Membership> onSelected;
  final VoidCallback onCreate;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final businesses = ref.watch(membershipProvider(userId));
    final isPlatformAdmin =
        ref.watch(platformAccessProvider(userId)).asData?.value == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Your businesses'),
        actions: [
          if (isPlatformAdmin)
            IconButton(
              tooltip: 'Platform administration',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => PlatformScreen(userId: userId),
                ),
              ),
            ),
          IconButton(
            tooltip: 'Your invitations',
            icon: const Icon(Icons.mail_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => InvitationsScreen(
                  onAccepted: () {
                    ref.invalidate(membershipProvider(userId));
                  },
                ),
              ),
            ),
          ),
          if (onSignOut != null)
            IconButton(
              onPressed: onSignOut,
              tooltip: 'Sign out',
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: businesses.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'We could not load your businesses. Check your connection and retry.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => ref.invalidate(membershipProvider(userId)),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          ),
          data: (memberships) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(membershipProvider(userId));
              await ref.read(membershipProvider(userId).future);
            },
            child: ListView(
              padding: const EdgeInsets.all(20),
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                Text(
                  memberships.isEmpty
                      ? 'Start with your business'
                      : 'Choose a workspace',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  memberships.isEmpty
                      ? 'Set up your shop details to begin billing and managing inventory.'
                      : 'Each business keeps its records and team access separate.',
                ),
                const SizedBox(height: 24),
                ...memberships.map(
                  (membership) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: const Icon(Icons.storefront_outlined),
                        title: Text(membership.organizationName),
                        subtitle: Text(membership.role.label),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          ref
                              .read(activeOrganizationProvider(userId).notifier)
                              .select(membership);
                          onSelected(membership);
                        },
                      ),
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add),
                  label: const Text('Set up a business'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => RolePermissionsScreen(
                        isPlatformAdmin: isPlatformAdmin,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.info_outline),
                  label: const Text('Roles and permissions'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
