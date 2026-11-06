class PendingSupportRequest {
  const PendingSupportRequest(
    this.requestId,
    this.organizationId,
    this.kind,
    this.subject,
    this.message,
  );
  final String requestId, organizationId, kind, subject, message;
  Map<String, Object> toJson() => {
    'version': 1,
    'request_id': requestId,
    'organization_id': organizationId,
    'kind': kind,
    'subject': subject,
    'message': message,
  };
  factory PendingSupportRequest.fromJson(Map<String, dynamic> data) {
    if (data['version'] != 1) {
      throw const FormatException('Unknown request version');
    }
    return PendingSupportRequest(
      data['request_id'] as String,
      data['organization_id'] as String,
      data['kind'] as String,
      data['subject'] as String,
      data['message'] as String,
    );
  }
}

abstract interface class PendingSupportStore {
  Future<void> save(String actor, PendingSupportRequest request);
  Future<PendingSupportRequest?> load(String actor, String organizationId);
  Future<void> clear(String actor, String organizationId);
}
