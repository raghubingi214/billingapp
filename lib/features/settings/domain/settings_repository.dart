class BusinessSettings {
  const BusinessSettings(this.version, this.values);
  final int version;
  final Map<String, dynamic> values;
}

abstract interface class SettingsRepository {
  Future<BusinessSettings> load(String organizationId);
  Future<void> save(
    String requestId,
    String organizationId,
    int version,
    Map<String, Object?> values,
  );
}
