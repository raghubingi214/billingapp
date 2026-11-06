import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../../integrations/supabase/supabase_provider.dart';
import '../data/supabase_team_repository.dart';
import '../domain/team_repository.dart';

final teamRepositoryProvider = Provider<TeamRepository>(
  (ref) => SupabaseTeamRepository(ref.watch(supabaseClientProvider)),
);

class InvitationsScreen extends ConsumerStatefulWidget {
  const InvitationsScreen({
    super.key,
    this.organizationId,
    required this.onAccepted,
  });
  final String? organizationId;
  final VoidCallback onAccepted;
  @override
  ConsumerState<InvitationsScreen> createState() => _InvitationsScreenState();
}

class _InvitationsScreenState extends ConsumerState<InvitationsScreen> {
  final email = TextEditingController();
  String role = 'cashier';
  String requestId = const Uuid().v4();
  String? submittedPayload;
  bool busy = false;
  late Future<List<TeamInvitation>> pending;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    pending = ref
        .read(teamRepositoryProvider)
        .invitations(organizationId: widget.organizationId);
  }

  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> run(Future<void> Function(TeamRepository) action) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await action(ref.read(teamRepositoryProvider));
      if (!mounted) return;
      setState(reload);
      widget.onAccepted();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Could not complete the request. Check your access and try again.',
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
    appBar: AppBar(
      title: Text(
        widget.organizationId == null ? 'Your invitations' : 'Team invitations',
      ),
    ),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.organizationId != null) ...[
            const Text(
              'Invite staff using their account email. They can accept after signing in and verifying their email.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Staff email'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: role,
              decoration: const InputDecoration(labelText: 'Role'),
              items: [
                'cashier',
                'manager',
                'accountant',
              ].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: busy ? null : (value) => setState(() => role = value!),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy
                  ? null
                  : () {
                      if (!RegExp(
                        r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                      ).hasMatch(email.text.trim())) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Enter a valid email.')),
                        );
                        return;
                      }
                      final payload =
                          '${email.text.trim().toLowerCase()}|$role';
                      if (submittedPayload != payload) {
                        requestId = const Uuid().v4();
                        submittedPayload = payload;
                      }
                      run(
                        (repository) => repository.invite(
                          requestId,
                          widget.organizationId!,
                          email.text,
                          role,
                        ),
                      );
                    },
              child: Text(busy ? 'Please wait…' : 'Create invitation'),
            ),
            const SizedBox(height: 24),
          ],
          FutureBuilder<List<TeamInvitation>>(
            future: pending,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return TextButton(
                  onPressed: () => setState(reload),
                  child: const Text('Unable to load invitations. Retry'),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.data!.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('No invitations to show.'),
                );
              }
              return Column(
                children: snapshot.data!
                    .map(
                      (invitation) => Card(
                        child: ListTile(
                          title: Text(invitation.email),
                          subtitle: Text(
                            '${invitation.role} · ${invitation.status}',
                          ),
                          trailing: invitation.status != 'pending'
                              ? null
                              : TextButton(
                                  onPressed: busy
                                      ? null
                                      : () => run(
                                          (repository) =>
                                              widget.organizationId == null
                                              ? repository.accept(invitation.id)
                                              : repository.revoke(
                                                  const Uuid().v4(),
                                                  widget.organizationId!,
                                                  invitation.id,
                                                ),
                                        ),
                                  child: Text(
                                    widget.organizationId == null
                                        ? 'Accept'
                                        : 'Revoke',
                                  ),
                                ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    ),
  );
}
