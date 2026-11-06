class StaffMember {
  const StaffMember(this.id, this.label, this.role, this.status);
  final String id, label, role, status;
}

abstract interface class MemberRepository {
  Future<List<StaffMember>> members(String organizationId);
  Future<void> update(
    String requestId,
    String organizationId,
    StaffMember member,
    String role,
    String status,
  );
}
