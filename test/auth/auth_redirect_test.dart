import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/core/env/auth_redirect.dart';

void main() {
  test('installed app always uses registered native callback', () {
    expect(
      AuthRedirect.resolve(
        isWeb: false,
        baseUri: Uri.parse('file:///app'),
        override: 'http://localhost:8087',
      ),
      'smartbilling://auth-callback',
    );
  });
  test('web callback uses current origin without router path or query', () {
    expect(
      AuthRedirect.resolve(
        isWeb: true,
        baseUri: Uri.parse('http://localhost:8087/sign-in?email=test'),
      ),
      'http://localhost:8087/',
    );
  });
  test('web does not request a native callback', () {
    expect(
      () => AuthRedirect.resolve(
        isWeb: true,
        baseUri: Uri.parse('http://localhost:8087'),
        override: 'smartbilling://auth-callback',
      ),
      throwsFormatException,
    );
  });
}
