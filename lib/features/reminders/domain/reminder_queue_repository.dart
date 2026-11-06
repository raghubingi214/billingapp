abstract interface class ReminderQueueRepository {
  Future<void> queue(
    String requestId,
    String organizationId,
    String invoiceId,
    String channel,
  );
  Future<List<Map<String, dynamic>>> history(
    String organizationId,
    String customerId,
    int offset,
  );
}

class ReminderQueueFailure implements Exception {
  const ReminderQueueFailure(this.message);
  final String message;
}
