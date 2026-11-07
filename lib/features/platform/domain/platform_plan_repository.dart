abstract interface class PlatformPlanRepository {
  Future<void> createDraft(String requestId, Map<String, dynamic> data);
  Future<List<Map<String, dynamic>>> page(int offset);
  Future<Map<String, dynamic>> subscriptionOptions(String organizationId);
  Future<void> assignSubscription(
    String requestId,
    String organizationId,
    String planId,
    int? expectedVersion,
  );
}
