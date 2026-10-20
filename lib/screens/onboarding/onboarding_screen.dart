import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tapsense/app/theme.dart';

class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kAccent, Color(0xFF9C88FF)],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.wallet, color: kTextPrimary, size: 36),
              ),
              const SizedBox(height: 28),
              const Text('Meet TapSense',
                style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800,
                    color: kTextPrimary)),
              const SizedBox(height: 12),
              const Text(
                'Your smart wallet companion. TapSense catches the moment you pay and logs it — no bank access, no SMS reading. Everything stays on your phone.',
                style: TextStyle(fontSize: 15, color: kTextSecondary, height: 1.6),
              ),
              const SizedBox(height: 40),
              _feature(Icons.bluetooth, 'Wallet pairing',
                  'Connects to your TapSense hardware over Bluetooth'),
              const SizedBox(height: 20),
              _feature(Icons.qr_code_scanner, 'QR scanning',
                  'Reads SGQR & PayNow codes, pre-fills the amount'),
              const SizedBox(height: 20),
              _feature(Icons.auto_awesome, 'Weekly AI digest',
                  'Smart spending summaries every Sunday'),
              const Spacer(),
              SizedBox(
                width: double.infinity, height: 52,
                child: ElevatedButton(
                  onPressed: () => context.go('/home'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kAccent,
                    foregroundColor: kTextPrimary,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text("Let's go",
                      style: TextStyle(fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _feature(IconData icon, String title, String desc) {
    return Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: kAccent, size: 22),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 14,
                fontWeight: FontWeight.w700, color: kTextPrimary)),
            Text(desc, style: const TextStyle(fontSize: 12,
                color: kTextSecondary)),
          ],
        )),
      ],
    );
  }
}