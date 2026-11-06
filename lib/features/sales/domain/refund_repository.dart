abstract interface class RefundRepository {
  Future<void> record(
    String requestId,
    String organizationId,
    String invoiceId,
    String amount,
    String method,
    String reference,
    String reason,
  );
}
