abstract interface class PlatformRepository {
  Future<bool> hasAccess();
  Future<List<Map<String, dynamic>>> supportThread(
    String supportId,
    int offset,
  );
  Future<void> replyToSupport(String requestId, String supportId, String body);
  Future<void> beginSupportReview(String requestId, String supportId);
  Future<Map<String, dynamic>> overview();
  Future<List<Map<String, dynamic>>> businesses(int offset);
  Future<List<Map<String, dynamic>>> supportQueue(String status, int offset);
}
