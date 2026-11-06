abstract interface class SubscriptionRepository {
  Future<Map<String, dynamic>> summary(String organizationId);
}
