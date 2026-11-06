import 'package:supabase_flutter/supabase_flutter.dart';
import '../domain/settings_repository.dart';

class SupabaseSettingsRepository implements SettingsRepository {
  SupabaseSettingsRepository(this.client);
  final SupabaseClient client;
  @override
  Future<BusinessSettings> load(String organizationId) async {
    final org = await client
        .from('organizations')
        .select()
        .eq('id', organizationId)
        .single();
    final settings = await client
        .from('business_settings')
        .select('version')
        .eq('organization_id', organizationId)
        .single();
    final series = await client
        .from('invoice_series')
        .select('prefix')
        .eq('organization_id', organizationId)
        .eq('active', true)
        .neq('doc_type', 'credit_note')
        .order('financial_year', ascending: false)
        .order('id')
        .limit(1);
    return BusinessSettings(settings['version'] as int, {
      ...org,
      'prefix': series.firstOrNull?['prefix'] ?? 'INV',
    });
  }

  @override
  Future<void> save(
    String requestId,
    String organizationId,
    int version,
    Map<String, Object?> values,
  ) async {
    await client.rpc(
      'update_business_settings',
      params: {
        'p_request_id': requestId,
        'p_organization_id': organizationId,
        'p_version': version,
        'p_data': values,
      },
    );
  }
}
