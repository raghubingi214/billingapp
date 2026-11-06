import 'business_draft.dart';
import 'organization_repository.dart';

class CreateOrganization {
  const CreateOrganization(this.repository);
  final OrganizationRepository repository;

  Future<String> call(BusinessDraft draft) {
    final errors = draft.validate();
    if (errors.isNotEmpty) throw OnboardingFailure(errors.values.first);
    if (draft.requestId.isEmpty) {
      throw const OnboardingFailure('Unable to prepare setup. Please retry.');
    }
    return repository.onboard(draft);
  }
}
