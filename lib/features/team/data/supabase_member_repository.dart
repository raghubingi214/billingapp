import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/member_repository.dart';

class SupabaseMemberRepository implements MemberRepository {
  SupabaseMemberRepository(this.client);
  final SupabaseClient client;
  @override
  Future<List<StaffMember>> members(String organizationId) async {
    final invitations = await client
        .from('organization_invitations')
        .select('email,accepted_by')
        .eq('organization_id', organizationId)
        .eq('status', 'accepted');
    final labels = {
      for (final row in invitations) row['accepted_by']: row['email'] as String,
    };
    final members = <StaffMember>[];
    for (var offset = 0; ; offset += 100) {
      final rows = await client
          .from('organization_members')
          .select('id,user_id,role,status')
          .eq('organization_id', organizationId)
          .order('id')
          .range(offset, offset + 99);
      members.addAll(
        rows.map(
          (row) => StaffMember(
            row['id'] as String,
            labels[row['user_id']] ??
                (row['role'] == 'owner' ? 'Business owner' : 'Staff member'),
            row['role'] as String,
            row['status'] as String,
          ),
        ),
      );
      if (rows.length < 100) return members;
    }
  }

  @override
  Future<void> update(
    String requestId,
    String organizationId,
    StaffMember member,
    String role,
    String status,
  ) async {
    await client.rpc(
      'update_member',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_member_id': member.id,
        'p_role': role,
        'p_status': status,
      },
    );
  }
}
