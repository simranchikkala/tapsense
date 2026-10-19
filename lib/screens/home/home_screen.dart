import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tapsense/services/auth_service.dart';
import 'package:tapsense/services/bluetooth_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    walletBluetooth.events.listen((event) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Wallet: ${event.label}'),
            backgroundColor: const Color(0xFF6C63FF),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F0F1A),
        title: const Text(
          'TapSense',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF9E9EBE)),
            onPressed: () async {
              await AuthService.signOut();
              if (context.mounted) context.go('/login');
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Wallet status card ──────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: walletBluetooth.isConnected
                      ? const Color(0xFF22C55E).withOpacity(0.4)
                      : const Color(0xFF2A2A4A),
                ),
              ),
              child: Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: walletBluetooth.isConnected
                        ? const Color(0xFF22C55E).withOpacity(0.15)
                        : const Color(0xFF6C63FF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    walletBluetooth.isConnected
                        ? Icons.bluetooth_connected
                        : Icons.bluetooth_disabled,
                    color: walletBluetooth.isConnected
                        ? const Color(0xFF22C55E)
                        : const Color(0xFF6C63FF),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        walletBluetooth.isConnected
                            ? 'Wallet Connected'
                            : 'No Wallet Paired',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        walletBluetooth.isConnected
                            ? 'Listening for payment events'
                            : 'Tap to pair your TapSense wallet',
                        style: const TextStyle(
                          color: Color(0xFF9E9EBE),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!walletBluetooth.isConnected)
                  ElevatedButton(
                    onPressed: () => context.push('/pairing'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6C63FF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Pair',
                        style: TextStyle(fontSize: 13)),
                  ),
                if (walletBluetooth.isConnected)
                  IconButton(
                    icon: const Icon(Icons.vibration,
                        color: Color(0xFF22C55E)),
                    onPressed: () => walletBluetooth.testBuzz(),
                    tooltip: 'Test buzz',
                  ),
              ]),
            ),

            const SizedBox(height: 24),

            // ── Action buttons ──────────────────────────────────────
            Row(children: [
              Expanded(
                child: _ActionBtn(
                  icon: Icons.qr_code_scanner,
                  label: 'Scan QR',
                  color: const Color(0xFF6C63FF),
                  onTap: () => context.push('/scanner'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionBtn(
                  icon: Icons.add_circle_outline,
                  label: 'Manual',
                  color: const Color(0xFF22C55E),
                  onTap: () => context.push('/confirm-log', extra: {
                    'triggerType': 'manual',
                    'merchantName': null,
                    'merchantUen': null,
                    'amount': null,
                    'rawQr': null,
                  }),
                ),
              ),
            ]),

            const SizedBox(height: 12),

            // ── Mock wallet events (testing without hardware) ───────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A4A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '🧪 Mock Wallet Events',
                    style: TextStyle(
                      color: Color(0xFF9E9EBE),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/confirm-log', extra: {
                          'triggerType': 'card_removed',
                          'merchantName': null,
                          'merchantUen': null,
                          'amount': null,
                          'rawQr': null,
                        }),
                        icon: const Icon(Icons.credit_card, size: 14),
                        label: const Text('Card Out',
                            style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFFBE0B),
                          side: const BorderSide(color: Color(0xFFFFBE0B)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => context.push('/confirm-log', extra: {
                          'triggerType': 'button_press',
                          'merchantName': null,
                          'merchantUen': null,
                          'amount': null,
                          'rawQr': null,
                        }),
                        icon: const Icon(Icons.radio_button_checked, size: 14),
                        label: const Text('Button',
                            style: TextStyle(fontSize: 12)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF4ECDC4),
                          side: const BorderSide(color: Color(0xFF4ECDC4)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
            ),

          ],
        ),
      ),
    );
  }
}

// ── Reusable action button widget ─────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Column(children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ]),
      ),
    );
  }
}