import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/services/app_notifications.dart';
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

    // "QR scanned" notification (Wallet Activity → Notifications)
    AppNotifications.qrScanned(result.merchantName ?? '');

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
    const double cutoutSize = 260;
    const double cornerRadius = 16;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Scan QR',
            style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: kTextPrimary),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1 — Camera feed (full screen)
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // 2 — Dim overlay with transparent cutout, drawn by CustomPainter.
          //     This is the only approach that reliably centres on Android.
          CustomPaint(
            painter: _ScanOverlayPainter(
              cutoutSize: cutoutSize,
              cornerRadius: cornerRadius,
              dimColor: Colors.black.withOpacity(0.55),
            ),
          ),

          // 3 — Accent border exactly on the cutout (same size/position)
          Center(
            child: Container(
              width: cutoutSize,
              height: cutoutSize,
              decoration: BoxDecoration(
                border: Border.all(color: kAccent, width: 2.5),
                borderRadius: BorderRadius.circular(cornerRadius),
              ),
            ),
          ),

          // 4 — Corner accents
          Center(
            child: SizedBox(
              width: cutoutSize,
              height: cutoutSize,
              child: Stack(children: [
                _Corner(top: 0,    left: 0),
                _Corner(top: 0,    right: 0),
                _Corner(bottom: 0, left: 0,  flipV: true),
                _Corner(bottom: 0, right: 0, flipV: true),
              ]),
            ),
          ),

          // 5 — Bottom instruction label
          Positioned(
            bottom: 60, left: 0, right: 0,
            child: Column(children: [
              const Text(
                'Point at an SGQR or PayNow code',
                style: TextStyle(color: kTextPrimary, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: kAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kAccent.withOpacity(0.5)),
                ),
                child: const Text(
                  'SGQR · PayNow · EMVCo',
                  style: TextStyle(color: kAccent, fontSize: 12),
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

// ── Overlay painter ───────────────────────────────────────────────────────────
// Draws a semi-transparent rectangle over the full canvas, then punches
// a rounded-rect hole in the centre using BlendMode.clear.
// This works correctly on Android unlike the ColorFiltered/srcOut approach.
class _ScanOverlayPainter extends CustomPainter {
  final double cutoutSize;
  final double cornerRadius;
  final Color dimColor;

  const _ScanOverlayPainter({
    required this.cutoutSize,
    required this.cornerRadius,
    required this.dimColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Save layer so BlendMode.clear only affects this layer
    canvas.saveLayer(Offset.zero & size, Paint());

    // Fill everything with dim colour
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = dimColor,
    );

    // Punch a hole at the exact centre
    final cutoutRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: size.center(Offset.zero),
        width: cutoutSize,
        height: cutoutSize,
      ),
      Radius.circular(cornerRadius),
    );
    canvas.drawRRect(
      cutoutRect,
      Paint()..blendMode = BlendMode.clear,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) =>
      old.cutoutSize != cutoutSize ||
      old.dimColor != dimColor ||
      old.cornerRadius != cornerRadius;
}

// ── Corner accent widget ──────────────────────────────────────────────────────
class _Corner extends StatelessWidget {
  final double? top, bottom, left, right;
  final bool flipV;

  const _Corner({
    this.top,
    this.bottom,
    this.left,
    this.right,
    this.flipV = false,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: Transform.scale(
        // Mirror horizontally for right-side corners
        scaleX: (right != null && left == null) ? -1 : 1,
        scaleY: flipV ? -1 : 1,
        alignment: Alignment.center,
        child: CustomPaint(
          size: const Size(26, 26),
          painter: _CornerPainter(),
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kAccent
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path()
      ..moveTo(0, size.height * 0.55)
      ..lineTo(0, 0)
      ..lineTo(size.width * 0.55, 0);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}