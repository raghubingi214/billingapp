abstract interface class ReminderConsentRepository {
  Future<List<Map<String, dynamic>>> load(
    String organizationId,
    String customerId,
  );
  Future<void> save(
    String requestId,
    String organizationId,
    String customerId,
    String channel,
    bool allowed,
    String evidence,
    int version,
  );
}
