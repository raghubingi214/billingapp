import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Template v1 uses only issued snapshots and original totals.
class InvoicePdf {
  static Future<Uint8List> render(Map<String, dynamic> invoice) async {
    final font = pw.Font.ttf(
      await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'),
    );
    final document = pw.Document();
    final business = invoice['supplier_snapshot'] as Map;
    final customer = invoice['recipient_snapshot'] as Map;
    final quote = invoice['quote_snapshot'] as Map;
    final items = quote['items'] as List;
    final title = switch (invoice['document_type']) {
      'tax_invoice' => 'Tax Invoice',
      'bill_of_supply' => 'Bill of Supply',
      _ => 'Invoice',
    };
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        footer: (context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Issued invoice · Template v1',
              style: const pw.TextStyle(fontSize: 8),
            ),
            pw.Text(
              'Page ${context.pageNumber} / ${context.pagesCount}',
              style: const pw.TextStyle(fontSize: 8),
            ),
          ],
        ),
        build: (context) => [
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 24,
              color: PdfColor.fromHex('#152B49'),
            ),
          ),
          pw.SizedBox(height: 12),
          pw.Text(
            business['legal_name']?.toString() ?? business['name'].toString(),
            style: const pw.TextStyle(fontSize: 16),
          ),
          pw.Text(_address(business['address'])),
          if (business['gstin'] != null) pw.Text('GSTIN: ${business['gstin']}'),
          pw.SizedBox(height: 16),
          pw.Text('Invoice: ${invoice['invoice_number']}'),
          pw.Text(
            'Issued: ${invoice['invoice_date']}   Due: ${invoice['due_date']}',
          ),
          pw.Text('Place of supply: ${invoice['place_of_supply']}'),
          pw.SizedBox(height: 16),
          pw.Text('Bill to: ${customer['name']}'),
          if (customer['billing_address'] != null)
            pw.Text(customer['billing_address'].toString()),
          if (customer['gstin'] != null) pw.Text('GSTIN: ${customer['gstin']}'),
          pw.SizedBox(height: 20),
          pw.TableHelper.fromTextArray(
            headers: [
              'Item / HSN',
              'Qty',
              'Rate INR',
              'Discount',
              'Taxable',
              'CGST',
              'SGST',
              'IGST',
              'Total INR',
            ],
            data: items
                .map(
                  (dynamic item) => [
                    '${item['name']}\n${item['hsn_sac'] ?? ''}',
                    '${item['qty']} ${item['unit']}',
                    item['unit_price'],
                    item['discount'],
                    item['taxable_value'],
                    item['cgst'],
                    item['sgst'],
                    item['igst'],
                    item['total'],
                  ],
                )
                .toList(),
            headerStyle: pw.TextStyle(fontSize: 8, color: PdfColors.white),
            headerDecoration: pw.BoxDecoration(
              color: PdfColor.fromHex('#152B49'),
            ),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.all(5),
          ),
          pw.SizedBox(height: 20),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Taxable value: INR ${invoice['taxable_total']}'),
                pw.Text('Tax: INR ${invoice['tax_total']}'),
                pw.Text(
                  'Grand total: INR ${invoice['grand_total']}',
                  style: const pw.TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    return document.save();
  }

  static String _address(dynamic address) => address is Map
      ? [
          address['line1'],
          address['city'],
          address['postal_code'],
        ].where((v) => v != null).join(', ')
      : address?.toString() ?? '';
}
