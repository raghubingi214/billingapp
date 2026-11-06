import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../supabase/supabase_provider.dart';

class StoredInvoicePreview extends ConsumerStatefulWidget {
  const StoredInvoicePreview({
    super.key,
    required this.organizationId,
    required this.invoiceId,
    required this.invoiceNumber,
  });
  final String organizationId, invoiceId, invoiceNumber;
  @override
  ConsumerState<StoredInvoicePreview> createState() =>
      _StoredInvoicePreviewState();
}

class _StoredInvoicePreviewState extends ConsumerState<StoredInvoicePreview> {
  late Future<Uint8List> bytes;
  @override
  void initState() {
    super.initState();
    reload();
  }

  void reload() {
    bytes = download();
  }

  Future<Uint8List> download() async {
    final result = await ref
        .read(supabaseClientProvider)
        .functions
        .invoke(
          'invoice-pdf',
          body: {
            'organization_id': widget.organizationId,
            'invoice_id': widget.invoiceId,
          },
        );
    if (result.status != 200) throw StateError('PDF unavailable');
    final uri = Uri.parse((result.data as Map)['url'] as String);
    final project = Uri.parse(ref.read(supabaseClientProvider).rest.url);
    if (uri.scheme != 'https' || uri.host != project.host) {
      throw StateError('Invalid file host');
    }
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) throw StateError('Download failed');
      final builder = BytesBuilder();
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        builder.add(chunk);
        if (builder.length > 10485760) throw StateError('PDF too large');
      }
      final data = builder.takeBytes();
      if (data.length < 4 || String.fromCharCodes(data.take(4)) != '%PDF') {
        throw StateError('Invalid PDF');
      }
      return data;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Invoice PDF')),
    body: FutureBuilder<Uint8List>(
      future: bytes,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: () => setState(reload),
              child: const Text('Unable to prepare private invoice PDF. Retry'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return PdfPreview(
          pdfFileName: '${widget.invoiceNumber.replaceAll('/', '-')}.pdf',
          canChangePageFormat: false,
          canChangeOrientation: false,
          build: (_) async => snapshot.data!,
        );
      },
    ),
  );
}
