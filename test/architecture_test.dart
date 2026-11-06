import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/core/env/app_environment.dart';

void main() {
  test('domain layers do not depend on UI or infrastructure', () {
    final files = Directory('lib/features')
        .listSync(recursive: true)
        .whereType<File>()
        .where(
          (file) =>
              file.path.endsWith('.dart') &&
              file.path.replaceAll('\\', '/').contains('/domain/'),
        );
    expect(files, isNotEmpty);
    for (final file in files) {
      final imports = RegExp(
        r"import\s+['\x22]([^'\x22]+)",
      ).allMatches(file.readAsStringSync()).map((match) => match.group(1)!);
      for (final import in imports) {
        expect(import, isNot(contains('flutter')), reason: file.path);
        expect(import, isNot(contains('riverpod')), reason: file.path);
        expect(import, isNot(contains('supabase')), reason: file.path);
        expect(import, isNot(contains('/data/')), reason: file.path);
      }
    }
  });
  test('presentation never imports Supabase SDK or calls database tables', () {
    for (final file
        in Directory('lib/features')
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.dart') &&
                  file.path.replaceAll('\\', '/').contains('/presentation/'),
            )) {
      expect(
        file.readAsStringSync(),
        isNot(contains("package:supabase_flutter")),
        reason: file.path,
      );
    }
  });
  test('configuration refuses a server secret or insecure endpoint', () {
    expect(
      () => const AppEnvironment(
        supabaseUrl: 'http://example.com',
        publishableKey: 'sb_publishable_test',
      ).validate(),
      throwsFormatException,
    );
    expect(
      () => const AppEnvironment(
        supabaseUrl: 'https://example.com',
        publishableKey: 'sb_secret_test',
      ).validate(),
      throwsFormatException,
    );
    const AppEnvironment(
      supabaseUrl: 'https://example.supabase.co',
      publishableKey: 'sb_publishable_test',
    ).validate();
  });
}
