class AppEnvironment {
  const AppEnvironment({
    required this.supabaseUrl,
    required this.publishableKey,
  });
  final String supabaseUrl;
  final String publishableKey;
  factory AppEnvironment.fromDefines() => const AppEnvironment(
    supabaseUrl: String.fromEnvironment('SUPABASE_URL'),
    publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
  );
  void validate() {
    final uri = Uri.tryParse(supabaseUrl);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        !publishableKey.startsWith('sb_publishable_')) {
      throw const FormatException('Missing or invalid app configuration');
    }
  }
}
