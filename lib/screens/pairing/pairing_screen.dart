import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:tapsense/services/bluetooth_service.dart';

class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key});

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  List<ScanResult> _results = [];
  bool _scanning = false;
  bool _connecting = false;
  String? _connectingId;

  @override
  void initState() {
    super.initState();
    _startScan();
  }

  void _startScan() {
    setState(() { _scanning = true; _results = []; });
    walletBluetooth.scan().listen((results) {
      setState(() => _results = results);
    }, onDone: () {
      setState(() => _scanning = false);
    });
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  Future<void> _connect(BluetoothDevice device) async {
    setState(() { _connecting = true; _connectingId = device.remoteId.str; });
    walletBluetooth.stopScan();
    final success = await walletBluetooth.connect(device);
    if (mounted) {
      if (success) {
        _showSuccess(device.platformName);
      } else {
        setState(() { _connecting = false; _connectingId = null; });
        _showError();
      }
    }
  }

  void _showSuccess(String name) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF22C55E).withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Color(0xFF22C55E), size: 32),
          ),
          const SizedBox(height: 16),
          Text('Connected to $name',
            style: const TextStyle(color: Colors.white,
                fontWeight: FontWeight.w700, fontSize: 16),
            textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Your TapSense wallet is ready',
            style: TextStyle(color: Color(0xFF9E9EBE), fontSize: 13),
            textAlign: TextAlign.center),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/home');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Go to Home'),
            ),
          ),
        ]),
      ),
    );
  }

  void _showError() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Could not connect. Try again.'),
        backgroundColor: Color(0xFFFF6B6B),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text('Pair Wallet',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF6C63FF).withOpacity(0.15),
                    const Color(0xFF9C88FF).withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.bluetooth_searching,
                    color: Color(0xFF6C63FF), size: 32),
                const SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Looking for your wallet',
                      style: TextStyle(color: Colors.white,
                          fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      _scanning ? 'Scanning for nearby devices...'
                                : 'Scan complete — ${_results.length} device(s) found',
                      style: const TextStyle(color: Color(0xFF9E9EBE),
                          fontSize: 12)),
                  ],
                )),
                if (_scanning)
                  const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Color(0xFF6C63FF))),
              ]),
            ),

            const SizedBox(height: 24),
            const Text('Nearby Devices',
              style: TextStyle(color: Color(0xFF9E9EBE),
                  fontSize: 12, fontWeight: FontWeight.w600,
                  letterSpacing: 1)),
            const SizedBox(height: 12),

            // Device list
            Expanded(
              child: _results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.bluetooth_disabled,
                          color: const Color(0xFF9E9EBE).withOpacity(0.4),
                          size: 48),
                        const SizedBox(height: 12),
                        const Text('No devices found',
                          style: TextStyle(color: Color(0xFF9E9EBE))),
                        const SizedBox(height: 4),
                        const Text('Make sure your wallet is turned on',
                          style: TextStyle(color: Color(0xFF6B6B8A),
                              fontSize: 12)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final r = _results[i];
                      final name = r.device.platformName.isEmpty
                          ? 'Unknown Device' : r.device.platformName;
                      final isConnecting =
                          _connectingId == r.device.remoteId.str;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A2E),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: const Color(0xFF2A2A4A)),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: const Color(0xFF6C63FF).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.wallet,
                                color: Color(0xFF6C63FF), size: 20),
                          ),
                          title: Text(name,
                            style: const TextStyle(color: Colors.white,
                                fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(r.device.remoteId.str,
                            style: const TextStyle(color: Color(0xFF6B6B8A),
                                fontSize: 11)),
                          trailing: isConnecting
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF6C63FF)))
                              : ElevatedButton(
                                  onPressed: _connecting ? null
                                      : () => _connect(r.device),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF6C63FF),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 8),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Connect',
                                      style: TextStyle(fontSize: 12)),
                                ),
                        ),
                      );
                    },
                  ),
            ),

            // Rescan button
            if (!_scanning)
              SizedBox(
                width: double.infinity, height: 48,
                child: OutlinedButton.icon(
                  onPressed: _startScan,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Scan Again'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF6C63FF),
                    side: const BorderSide(color: Color(0xFF6C63FF)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}