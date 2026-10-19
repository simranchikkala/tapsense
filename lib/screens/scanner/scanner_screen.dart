import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:tapsense/services/qr_parser.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _scanned = false;

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    _scanned = true;
    _controller.stop();

    final raw = barcode!.rawValue!;
    final result = QrParser.parse(raw);

    // Navigate to confirm log with parsed data
    context.push('/confirm-log', extra: {
      'triggerType': 'qr_scan',
      'merchantName': result.merchantName,
      'merchantUen': result.merchantUen,
      'amount': result.amount,
      'rawQr': raw,
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan QR',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(children: [
        MobileScanner(
          controller: _controller,
          onDetect: _onDetect,
        ),

        // Overlay
        Center(
          child: Container(
            width: 260, height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF6C63FF), width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),

        // Bottom label
        Positioned(
          bottom: 60, left: 0, right: 0,
          child: Column(children: [
            const Text('Point at an SGQR or PayNow code',
              style: TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF6C63FF).withOpacity(0.2),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.5)),
              ),
              child: const Text('SGQR · PayNow · EMVCo',
                style: TextStyle(color: Color(0xFF6C63FF), fontSize: 12)),
            ),
          ]),
        ),
      ]),
    );
  }
}