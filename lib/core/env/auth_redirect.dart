class AuthRedirect {
  static String resolve({
    required bool isWeb,
    required Uri baseUri,
    String override = '',
  }) {
    if (!isWeb) return 'smartbilling://auth-callback';
    final target = override.isEmpty
        ? Uri.parse('${baseUri.origin}/')
        : Uri.parse(override);
    if (!['http', 'https'].contains(target.scheme) ||
        target.host.isEmpty ||
        target.userInfo.isNotEmpty) {
      throw const FormatException(
        'Web authentication requires an HTTP redirect',
      );
    }
    return target.toString();
  }
}
