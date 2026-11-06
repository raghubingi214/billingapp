import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_billing/integrations/printing/invoice_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('issued snapshot renders a multi-line invoice PDF', () async {
    final invoice = <String, dynamic>{
      'document_type': 'tax_invoice',
      'invoice_number': 'INV/2627/000001',
      'invoice_date': '2026-11-05',
      'due_date': '2026-11-12',
      'place_of_supply': '36',
      'supplier_snapshot': {
        'name': 'Sample Store',
        'legal_name': 'Sample Store Trading',
        'address': {
          'line1': '12 Market Road',
          'city': 'Hyderabad',
          'postal_code': '500001',
        },
        'gstin': '36ABCDE1234F1Z5',
      },
      'recipient_snapshot': {
        'name': 'Sample Customer',
        'billing_address': '24 Commercial Street, Hyderabad',
      },
      'taxable_total': '1800.00',
      'tax_total': '324.00',
      'grand_total': '2124.00',
      'quote_snapshot': {
        'items': List.generate(
          12,
          (index) => {
            'name': 'Product ${index + 1} with descriptive packaging name',
            'hsn_sac': '1006',
            'qty': '1',
            'unit': 'pcs',
            'unit_price': '150.00',
            'discount': '0.00',
            'taxable_value': '150.00',
            'cgst': '13.50',
            'sgst': '13.50',
            'igst': '0.00',
            'total': '177.00',
          },
        ),
      },
    };
    final bytes = await InvoicePdf.render(invoice);
    expect(bytes.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    final directory = Directory('tmp/pdfs')..createSync(recursive: true);
    File(
      '${directory.path}/invoice-layout-fixture.pdf',
    ).writeAsBytesSync(bytes);
  });
}
