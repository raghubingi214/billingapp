import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../domain/member_repository.dart';
import '../data/supabase_member_repository.dart';

final memberRepositoryProvider = Provider<MemberRepository>(
  (ref) => SupabaseMemberRepository(ref.watch(supabaseClientProvider)),
);

class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key, required this.organizationId});
  final String organizationId;
  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  late Future<List<StaffMember>> members;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    members = ref.read(memberRepositoryProvider).members(widget.organizationId);
  }

  Future<void> change(StaffMember member, String role, String status) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change staff access?'),
        content: Text('${member.label}\nRole: $role\nAccess: $status'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || busy) return;
    setState(() => busy = true);
    try {
      await ref
          .read(memberRepositoryProvider)
          .update(
            const Uuid().v4(),
            widget.organizationId,
            member,
            role,
            status,
          );
      if (mounted) setState(reload);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Unable to change access. Check your connection and permissions.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Team access')),
    body: SafeArea(
      child: FutureBuilder<List<StaffMember>>(
        future: members,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: TextButton(
                onPressed: () => setState(reload),
                child: const Text('Could not load team. Retry'),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (busy) const LinearProgressIndicator(),
              for (final member in snapshot.data!)
                Card(
                  child: ListTile(
                    title: Text(member.label),
                    subtitle: Text('${member.role} · ${member.status}'),
                    trailing: member.role == 'owner'
                        ? null
                        : PopupMenuButton<String>(
                            enabled: !busy,
                            tooltip: 'Change staff access',
                            onSelected: (value) => value == 'revoke'
                                ? change(member, member.role, 'revoked')
                                : change(member, value, 'active'),
                            itemBuilder: (_) => [
                              for (final role in [
                                'manager',
                                'cashier',
                                'accountant',
                              ])
                                PopupMenuItem(
                                  value: role,
                                  child: Text('Set $role'),
                                ),
                              const PopupMenuItem(
                                value: 'revoke',
                                child: Text('Revoke access'),
                              ),
                            ],
                          ),
                  ),
                ),
            ],
          );
        },
      ),
    ),
  );
}
