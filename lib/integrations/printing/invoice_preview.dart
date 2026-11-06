import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'invoice_pdf.dart';

class InvoicePreview extends StatelessWidget {
  const InvoicePreview({super.key, required this.invoice});
  final Map<String, dynamic> invoice;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Invoice PDF')),
    body: PdfPreview(
      pdfFileName:
          '${invoice['invoice_number'].toString().replaceAll('/', '-')}.pdf',
      canChangePageFormat: false,
      canChangeOrientation: false,
      build: (_) => InvoicePdf.render(invoice),
    ),
  );
}
