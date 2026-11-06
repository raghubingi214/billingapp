import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/subscription_repository.dart';

class SupabaseSubscriptionRepository implements SubscriptionRepository {
  SupabaseSubscriptionRepository(this.client);
  final SupabaseClient client;
  @override
  Future<Map<String, dynamic>> summary(String organizationId) async =>
      Map<String, dynamic>.from(
        await client.rpc(
              'subscription_summary',
              params: {'p_organization_id': organizationId},
            )
            as Map,
      );
}
