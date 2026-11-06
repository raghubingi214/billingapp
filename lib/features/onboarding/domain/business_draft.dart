enum TaxRegime {
  unregistered(
    'Unregistered',
    'Create ordinary commercial invoices without collecting GST.',
  ),
  regular(
    'Regular GST',
    'Use your GST registration and approved tax settings.',
  ),
  composition(
    'Composition',
    'Issue bills of supply without collecting GST from customers.',
  );

  const TaxRegime(this.label, this.description);
  final String label;
  final String description;
}

class BusinessDraft {
  const BusinessDraft({
    this.name = '',
    this.legalName = '',
    this.stateCode = '',
    this.line1 = '',
    this.city = '',
    this.postalCode = '',
    this.taxRegime = TaxRegime.unregistered,
    this.gstin = '',
    this.prefix = 'INV',
    this.requestId = '',
    this.step = 0,
    this.submitted = false,
  });

  final String name,
      legalName,
      stateCode,
      line1,
      city,
      postalCode,
      gstin,
      prefix,
      requestId;
  final TaxRegime taxRegime;
  final int step;
  final bool submitted;

  BusinessDraft copyWith({
    String? name,
    String? legalName,
    String? stateCode,
    String? line1,
    String? city,
    String? postalCode,
    TaxRegime? taxRegime,
    String? gstin,
    String? prefix,
    String? requestId,
    int? step,
    bool? submitted,
  }) => BusinessDraft(
    name: name ?? this.name,
    legalName: legalName ?? this.legalName,
    stateCode: stateCode ?? this.stateCode,
    line1: line1 ?? this.line1,
    city: city ?? this.city,
    postalCode: postalCode ?? this.postalCode,
    taxRegime: taxRegime ?? this.taxRegime,
    gstin: gstin ?? this.gstin,
    prefix: prefix ?? this.prefix,
    requestId: requestId ?? this.requestId,
    step: step ?? this.step,
    submitted: submitted ?? this.submitted,
  );

  Map<String, String> validateProfile() => {
    if (name.trim().isEmpty) 'name': 'Enter the shop or business name',
    if (legalName.trim().isEmpty) 'legalName': 'Enter the legal business name',
    if (!RegExp(r'^\d{2}$').hasMatch(stateCode))
      'stateCode': 'Choose a state or territory',
    if (line1.trim().isEmpty) 'line1': 'Enter the business address',
    if (city.trim().isEmpty) 'city': 'Enter the city',
    if (!RegExp(r'^[1-9]\d{5}$').hasMatch(postalCode.trim()))
      'postalCode': 'Enter a six-digit PIN code',
  };

  Map<String, String> validateTax() => {
    if (!RegExp(r'^[A-Z0-9]{1,4}$').hasMatch(prefix.trim()))
      'prefix': 'Use 1–4 uppercase letters or numbers',
    if (taxRegime != TaxRegime.unregistered &&
        (!RegExp(
              r'^\d{2}[A-Z]{5}\d{4}[A-Z][1-9A-Z]Z[0-9A-Z]$',
            ).hasMatch(gstin.trim()) ||
            !gstin.startsWith(stateCode)))
      'gstin': 'Enter a valid GSTIN matching your business state',
  };

  Map<String, String> validate() => {...validateProfile(), ...validateTax()};

  /// Excludes navigation state and the key itself so retries identify input.
  String get fingerprint => [
    name.trim(),
    legalName.trim(),
    stateCode,
    line1.trim(),
    city.trim(),
    postalCode.trim(),
    taxRegime.name,
    taxRegime == TaxRegime.unregistered ? '' : gstin.trim(),
    prefix.trim(),
  ].join('\u0000');
}
