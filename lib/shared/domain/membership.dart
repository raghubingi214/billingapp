enum OrganizationRole {
  owner,
  manager,
  cashier,
  accountant;

  String get label => name[0].toUpperCase() + name.substring(1);
}

class Membership {
  const Membership({
    required this.id,
    required this.organizationId,
    required this.organizationName,
    required this.role,
  });

  final String id;
  final String organizationId;
  final String organizationName;
  final OrganizationRole role;
}
