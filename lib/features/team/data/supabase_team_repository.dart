import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/team_repository.dart';

class SupabaseTeamRepository implements TeamRepository {
  SupabaseTeamRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<TeamInvitation>> invitations({String? organizationId}) async {
    final result = <TeamInvitation>[];
    for (var offset = 0; ; offset += 100) {
      var query = client
          .from('organization_invitations')
          .select('id,email,role,status');
      if (organizationId != null) {
        query = query.eq('organization_id', organizationId);
      } else {
        query = query
            .eq('email', client.auth.currentUser?.email?.toLowerCase() ?? '')
            .eq('status', 'pending');
      }
      final rows = await query.order('id').range(offset, offset + 99);
      result.addAll(
        rows.map(
          (row) => TeamInvitation(
            id: row['id'] as String,
            email: row['email'] as String,
            role: row['role'] as String,
            status: row['status'] as String,
          ),
        ),
      );
      if (rows.length < 100) return result;
    }
  }

  @override
  Future<void> invite(
    String requestId,
    String organizationId,
    String email,
    String role,
  ) async {
    await client.rpc(
      'invite_member',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_email': email.trim().toLowerCase(),
        'p_role': role,
      },
    );
  }

  @override
  Future<void> accept(String invitationId) async {
    await client.rpc(
      'accept_invitation',
      params: {'p_invitation_id': invitationId},
    );
  }

  @override
  Future<void> revoke(
    String requestId,
    String organizationId,
    String invitationId,
  ) async {
    await client.rpc(
      'revoke_invitation',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_invitation_id': invitationId,
      },
    );
  }
}
