import '../../../shared/domain/membership.dart';
import 'business_draft.dart';

abstract interface class OrganizationRepository {
  Future<List<Membership>> memberships(String userId);
  Future<String> onboard(BusinessDraft draft);
  Future<BusinessDraft?> loadDraft(String userId);
  Future<void> saveDraft(String userId, BusinessDraft draft);
  Future<void> clearDraft(String userId);
}

class OnboardingFailure implements Exception {
  const OnboardingFailure(this.message);
  final String message;
  @override
  String toString() => message;
}
