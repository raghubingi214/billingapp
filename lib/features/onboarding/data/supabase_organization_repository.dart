import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../shared/domain/membership.dart';
import '../domain/business_draft.dart';
import '../domain/organization_repository.dart';

class SupabaseOrganizationRepository implements OrganizationRepository {
  SupabaseOrganizationRepository(this.client);
  final SupabaseClient client;

  @override
  Future<List<Membership>> memberships(String userId) async {
    try {
      final result = <Membership>[];
      for (var offset = 0; ; offset += 100) {
        final rows = await client
            .from('organization_members')
            .select('id,organization_id,role,organizations!inner(id,name)')
            .eq('user_id', userId)
            .eq('status', 'active')
            .order('id')
            .range(offset, offset + 99);
        result.addAll(
          rows.map(
            (row) => Membership(
              id: row['id'] as String,
              organizationId: row['organization_id'] as String,
              organizationName:
                  (row['organizations'] as Map<String, dynamic>)['name']
                      as String,
              role: OrganizationRole.values.byName(row['role'] as String),
            ),
          ),
        );
        if (rows.length < 100) return result;
      }
    } catch (_) {
      throw const OnboardingFailure(
        'Unable to load your businesses. Check your connection and retry.',
      );
    }
  }

  @override
  Future<String> onboard(BusinessDraft draft) async {
    try {
      final result = await client.rpc(
        'onboard_organization',
        params: {
          'p_request_id': draft.requestId,
          'p_name': draft.name.trim(),
          'p_legal_name': draft.legalName.trim(),
          'p_state_code': draft.stateCode,
          'p_address': {
            'line1': draft.line1.trim(),
            'city': draft.city.trim(),
            'postal_code': draft.postalCode.trim(),
          },
          'p_tax_regime': draft.taxRegime.name,
          'p_gstin': draft.taxRegime == TaxRegime.unregistered
              ? null
              : draft.gstin.trim(),
          'p_prefix': draft.prefix.trim(),
        },
      );
      return (result as Map<String, dynamic>)['organization_id'] as String;
    } on PostgrestException catch (error) {
      if (error.code == '42501' || error.code == '28000') {
        throw const OnboardingFailure(
          'Your session needs attention. Sign in again to continue.',
        );
      }
      throw const OnboardingFailure(
        'Business setup could not be completed. Check your details and retry.',
      );
    } catch (_) {
      throw const OnboardingFailure(
        'Connection interrupted. Your details are saved; retry to finish safely.',
      );
    }
  }

  String _key(String userId) => 'onboarding.draft.v1.$userId';

  @override
  Future<BusinessDraft?> loadDraft(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId));
    if (raw == null) return null;
    try {
      final value = jsonDecode(raw) as Map<String, dynamic>;
      return BusinessDraft(
        name: value['name'] as String,
        legalName: value['legalName'] as String,
        stateCode: value['stateCode'] as String,
        line1: value['line1'] as String,
        city: value['city'] as String,
        postalCode: value['postalCode'] as String,
        taxRegime: TaxRegime.values.byName(value['taxRegime'] as String),
        gstin: value['gstin'] as String,
        prefix: value['prefix'] as String,
        requestId: value['requestId'] as String,
        step: (value['step'] as int).clamp(0, 2),
        submitted: value['submitted'] as bool? ?? false,
      );
    } catch (_) {
      await prefs.remove(_key(userId));
      return null;
    }
  }

  @override
  Future<void> saveDraft(String userId, BusinessDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = await prefs.setString(
      _key(userId),
      jsonEncode({
        'name': draft.name,
        'legalName': draft.legalName,
        'stateCode': draft.stateCode,
        'line1': draft.line1,
        'city': draft.city,
        'postalCode': draft.postalCode,
        'taxRegime': draft.taxRegime.name,
        'gstin': draft.gstin,
        'prefix': draft.prefix,
        'requestId': draft.requestId,
        'step': draft.step,
        'submitted': draft.submitted,
      }),
    );
    if (!saved) {
      throw const OnboardingFailure(
        'Unable to save setup on this device. Please retry.',
      );
    }
  }

  @override
  Future<void> clearDraft(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(userId));
  }
}
