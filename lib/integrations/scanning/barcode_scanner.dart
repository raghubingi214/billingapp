import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

typedef ScanBarcode = Future<String?> Function(BuildContext context);

final barcodeScannerProvider = Provider<ScanBarcode>(
  (ref) =>
      (context) => Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
      ),
);

class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});
  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  bool returned = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan product barcode')),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: MobileScanner(
              onDetect: (capture) {
                if (returned || !mounted) return;
                final values = capture.barcodes
                    .map((b) => b.rawValue?.trim())
                    .whereType<String>()
                    .where(
                      (v) =>
                          v.isNotEmpty &&
                          v.length <= 120 &&
                          !RegExp(r'[\x00-\x1F\x7F]').hasMatch(v),
                    )
                    .toSet();
                if (values.length != 1) return;
                returned = true;
                Navigator.of(context).pop(values.single);
              },
              errorBuilder: (context, error) => const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Camera unavailable. Allow camera access in phone settings, '
                    'or go back and enter the barcode manually.',
                  ),
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Point the camera at one product barcode. You can also enter it manually.',
            ),
          ),
        ],
      ),
    ),
  );
}
