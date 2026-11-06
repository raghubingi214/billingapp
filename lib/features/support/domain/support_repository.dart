abstract interface class SupportRepository {
  Future<List<Map<String, dynamic>>> replies(
    String organizationId,
    String supportId,
    int offset,
  );
  Future<List<Map<String, dynamic>>> history(String organizationId, int offset);
  Future<void> submit(
    String requestId,
    String organizationId,
    String kind,
    String subject,
    String message,
  );
}
