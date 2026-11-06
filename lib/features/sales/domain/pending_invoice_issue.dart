import 'dart:convert';
import 'draft_repository.dart';

class InvoiceIssueRejected implements Exception {
  const InvoiceIssueRejected(this.code);
  final String code;
  String get message => switch (code) {
    'INSUFFICIENT_STOCK' =>
      'Invoice was not issued. Adjust quantities or check stock before retrying.',
    'CREDIT_LIMIT_EXCEEDED' =>
      'Invoice was not issued. Review the credit limit or collect payment.',
    'QUOTE_CHANGED' =>
      'Prices or taxes changed. Review the sale again before issuing.',
    'INVALID_DUE_DATE' => 'Invoice was not issued. Choose a valid due date.',
    'DRAFT_VERSION_CONFLICT' =>
      'The draft changed. Reopen the latest saved draft before issuing.',
    'PRODUCT_NOT_FOUND' =>
      'Invoice was not issued. Review the selected products before retrying.',
    _ =>
      'Invoice was not issued. Review stock, credit, prices or payments and try again.',
  };
}

/// Retains the exact confirmed command when the response is lost.
class PendingInvoiceIssue {
  PendingInvoiceIssue(
    this.requestId,
    this.organizationId,
    SaleDraft draft,
    Map<String, dynamic> quote,
    this.dueDate, {
    List<Map<String, String>> tenders = const [],
  }) : tenders = (jsonDecode(jsonEncode(tenders)) as List)
           .map((row) => Map<String, String>.from(row as Map))
           .toList(),
       draft = SaleDraft(
         Map<String, dynamic>.from(jsonDecode(jsonEncode(draft.values)) as Map),
       ),
       quote = Map<String, dynamic>.from(jsonDecode(jsonEncode(quote)) as Map);
  final String requestId, organizationId, dueDate;
  final SaleDraft draft;
  final Map<String, dynamic> quote;
  final List<Map<String, String>> tenders;
  Map<String, dynamic> toJson() => {
    'version': 1,
    'request_id': requestId,
    'organization_id': organizationId,
    'draft': draft.values,
    'quote': quote,
    'due_date': dueDate,
    'tenders': tenders,
  };
  factory PendingInvoiceIssue.fromJson(Map<String, dynamic> data) {
    if (data['version'] != 1) {
      throw const FormatException('Unknown invoice command version');
    }
    return PendingInvoiceIssue(
      data['request_id'] as String,
      data['organization_id'] as String,
      SaleDraft(Map<String, dynamic>.from(data['draft'] as Map)),
      Map<String, dynamic>.from(data['quote'] as Map),
      data['due_date'] as String,
      tenders: (data['tenders'] as List)
          .map((row) => Map<String, String>.from(row as Map))
          .toList(),
    );
  }
  Future<void> send(DraftRepository repository) => tenders.isEmpty
      ? repository.issue(requestId, organizationId, draft, quote, dueDate)
      : repository.checkout(
          requestId,
          organizationId,
          draft,
          quote,
          dueDate,
          tenders,
        );
}

abstract interface class PendingInvoiceStore {
  Future<List<PendingInvoiceIssue>> list(String actorId, String organizationId);
  Future<void> save(String actorId, PendingInvoiceIssue command);
  Future<void> clear(String actorId, PendingInvoiceIssue command);
}
