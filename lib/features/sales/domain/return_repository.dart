abstract interface class ReturnRepository {
  Future<void> post(
    String requestId,
    String organizationId,
    String invoiceId,
    String reason,
    List<Map<String, Object?>> items,
  );
}
