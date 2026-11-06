class TeamInvitation {
  const TeamInvitation({
    required this.id,
    required this.email,
    required this.role,
    required this.status,
  });
  final String id, email, role, status;
}

abstract interface class TeamRepository {
  Future<List<TeamInvitation>> invitations({String? organizationId});
  Future<void> invite(
    String requestId,
    String organizationId,
    String email,
    String role,
  );
  Future<void> accept(String invitationId);
  Future<void> revoke(
    String requestId,
    String organizationId,
    String invitationId,
  );
}
