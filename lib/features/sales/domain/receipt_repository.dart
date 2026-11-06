abstract interface class ReceiptRepository {
  Future<void> record(
    String requestId,
    String organizationId,
    String customerId,
    String invoiceId,
    String amount,
    String method,
    String reference,
    String date,
  );
}
