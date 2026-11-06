abstract interface class PlatformPlanRepository {
  Future<void> createDraft(String requestId, Map<String, dynamic> data);
  Future<List<Map<String, dynamic>>> page(int offset);
}
