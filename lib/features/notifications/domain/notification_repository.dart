class BusinessNotification {
  const BusinessNotification(
    this.id,
    this.title,
    this.body,
    this.entityType,
    this.entityId,
    this.read,
  );
  final String id, title, body, entityType, entityId;
  final bool read;
}

abstract interface class NotificationRepository {
  Future<List<BusinessNotification>> page(
    String organizationId,
    int offset,
    bool unreadOnly,
  );
  Future<void> markRead(String organizationId, String notificationId);
}
