import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/app/theme.dart';
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
        // ── Upsert wallet row so rename + settings can find it ──
        await _upsertWallet(
          deviceId: device.remoteId.str,
          deviceName: device.platformName,
        );
        _showSuccess(device.platformName);
      } else {
        setState(() { _connecting = false; _connectingId = null; });
        _showError();
      }
    }
  }

  Future<void> _upsertWallet({
    required String deviceId,
    required String deviceName,
  }) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Use upsert so re-pairing the same device updates rather than errors
      await Supabase.instance.client.from('wallets').upsert(
        {
          'user_id': userId,
          'device_id': deviceId,
          'device_name': deviceName,
          // wallet_name defaults to device_name on first pair;
          // if a row already exists (same user_id) the wallet_name
          // the user set is preserved because we only upsert on
          // the user_id conflict column.
          'wallet_name': deviceName,
        },
        onConflict: 'user_id', // one wallet per user
        ignoreDuplicates: false,
      );
    } catch (e) {
      // Non-fatal — pairing still succeeds, rename will just show default name
      debugPrint('wallet upsert error: $e');
    }
  }

  void _showSuccess(String name) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: kSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: kSuccess.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: kSuccess, size: 32),
          ),
          const SizedBox(height: 16),
          Text('Connected to $name',
            style: const TextStyle(color: kTextPrimary,
                fontWeight: FontWeight.w700, fontSize: 16),
            textAlign: TextAlign.center),
          const SizedBox(height: 8),
          const Text('Your TapSense wallet is ready',
            style: TextStyle(color: kTextSecondary, fontSize: 13),
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
                backgroundColor: kAccent,
                foregroundColor: kTextPrimary,
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
        backgroundColor: kError,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        title: const Text('Pair Wallet',
            style: TextStyle(color: kTextPrimary, fontWeight: FontWeight.w700)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: kTextPrimary),
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
                    kAccent.withOpacity(0.15),
                    kAccent.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kAccent.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.bluetooth_searching,
                    color: kAccent, size: 32),
                const SizedBox(width: 16),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Looking for your wallet',
                      style: TextStyle(color: kTextPrimary,
                          fontWeight: FontWeight.w700, fontSize: 15)),
                    const SizedBox(height: 4),
                    Text(
                      _scanning ? 'Scanning for nearby devices...'
                                : 'Scan complete — ${_results.length} device(s) found',
                      style: const TextStyle(color: kTextSecondary,
                          fontSize: 12)),
                  ],
                )),
                if (_scanning)
                  const SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: kAccent)),
              ]),
            ),

            const SizedBox(height: 24),
            const Text('Nearby Devices',
              style: TextStyle(color: kTextSecondary,
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
                          color: kTextSecondary.withOpacity(0.4),
                          size: 48),
                        const SizedBox(height: 12),
                        const Text('No devices found',
                          style: TextStyle(color: kTextSecondary)),
                        const SizedBox(height: 4),
                        const Text('Make sure your wallet is turned on',
                          style: TextStyle(color: kTextMuted,
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
                          color: kSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBorder),
                        ),
                        child: ListTile(
                          leading: Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: kAccent.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.wallet,
                                color: kAccent, size: 20),
                          ),
                          title: Text(name,
                            style: const TextStyle(color: kTextPrimary,
                                fontWeight: FontWeight.w600, fontSize: 14)),
                          subtitle: Text(r.device.remoteId.str,
                            style: const TextStyle(color: kTextMuted,
                                fontSize: 11)),
                          trailing: isConnecting
                              ? const SizedBox(width: 20, height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: kAccent))
                              : ElevatedButton(
                                  onPressed: _connecting ? null
                                      : () => _connect(r.device),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: kAccent,
                                    foregroundColor: kTextPrimary,
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
                    foregroundColor: kAccent,
                    side: const BorderSide(color: kAccent),
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