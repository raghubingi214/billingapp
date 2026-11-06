import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:smart_billing/features/sales/data/supabase_draft_repository.dart';
import 'package:smart_billing/features/sales/domain/draft_repository.dart';
import 'package:smart_billing/features/sales/domain/pending_invoice_issue.dart';

void main() {
  for (final entry in [
    (code: 'P0001', message: 'INSUFFICIENT_STOCK', rejected: true),
    (code: 'P0001', message: 'PRODUCT_NOT_FOUND', rejected: true),
    (code: 'P0001', message: 'DRAFT_VERSION_CONFLICT', rejected: true),
    (code: '42501', message: 'ACCESS_DENIED', rejected: false),
    (code: 'P0001', message: 'IDEMPOTENCY_KEY_REUSED', rejected: false),
  ]) {
    test(
      'issue ${entry.message} preserves the correct recovery classification',
      () async {
        final client = SupabaseClient(
          'https://example.supabase.co',
          'test-key',
          httpClient: MockClient(
            (request) async => http.Response(
              jsonEncode({
                'code': entry.code,
                'message': entry.message,
                'details': null,
                'hint': null,
              }),
              400,
              headers: {'content-type': 'application/json'},
              request: request,
            ),
          ),
        );
        addTearDown(client.dispose);
        final repository = SupabaseDraftRepository(client);
        final failure = entry.rejected
            ? isA<InvoiceIssueRejected>()
            : isA<PostgrestException>();
        await expectLater(
          repository.issue(
            'request',
            'org',
            const SaleDraft({'id': 'draft', 'version': 2}),
            {},
            '2026-11-07',
          ),
          throwsA(failure),
        );
        await expectLater(
          repository.checkout(
            'request',
            'org',
            const SaleDraft({'id': 'draft', 'version': 2}),
            {},
            '2026-11-07',
            [],
          ),
          throwsA(failure),
        );
      },
    );
  }
  test('transport failure stays uncertain', () async {
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      httpClient: MockClient(
        (request) async => throw http.ClientException('Connection lost'),
      ),
    );
    addTearDown(client.dispose);
    await expectLater(
      SupabaseDraftRepository(client).issue(
        'request',
        'org',
        const SaleDraft({'id': 'draft', 'version': 2}),
        {},
        '2026-11-07',
      ),
      throwsA(isA<http.ClientException>()),
    );
  });
}
