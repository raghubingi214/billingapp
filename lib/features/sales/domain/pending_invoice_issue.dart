import 'dart:convert';
import 'draft_repository.dart';

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
