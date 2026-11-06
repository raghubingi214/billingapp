class AuditEvent {
  const AuditEvent(
    this.action,
    this.createdAt,
    this.actorId,
    this.recordId,
    this.beforeData,
    this.afterData,
  );
  final String action, createdAt, actorId, recordId;
  final Map<String, dynamic>? beforeData, afterData;
}

abstract interface class AuditRepository {
  Future<List<AuditEvent>> page(String organizationId, int offset);
}
