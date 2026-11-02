// lib/widgets/battery_badge.dart
//
// Wallet battery %, updating live. Turns red below 15 %.
// Shows nothing while the battery is unknown (not connected / old firmware).
//
//   const BatteryBadge()            // small icon + "82%"
//   const BatteryBadge(showLabel: true)   // "Battery 82%"

import 'package:flutter/material.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/services/bluetooth_service.dart';

class BatteryBadge extends StatelessWidget {
  const BatteryBadge({super.key, this.showLabel = false, this.fontSize = 12});

  final bool showLabel;
  final double fontSize;

  static const int lowThreshold = 15;

  static IconData iconFor(int pct) {
    if (pct < lowThreshold) return Icons.battery_alert_rounded;
    if (pct < 35) return Icons.battery_2_bar_rounded;
    if (pct < 60) return Icons.battery_4_bar_rounded;
    if (pct < 90) return Icons.battery_5_bar_rounded;
    return Icons.battery_full_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final normal = dark ? kTextSecondary : kTextSecondaryLight;
    final low = dark ? kError : kErrorLight;

    return ValueListenableBuilder<int?>(
      valueListenable: walletBluetooth.batteryPercent,
      builder: (context, pct, _) {
        if (pct == null) return const SizedBox.shrink();
        final color = pct < lowThreshold ? low : normal;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(iconFor(pct), color: color, size: fontSize + 4),
          const SizedBox(width: 3),
          Text(showLabel ? 'Battery $pct%' : '$pct%',
              style: TextStyle(
                  color: color,
                  fontSize: fontSize,
                  fontWeight:
                      pct < lowThreshold ? FontWeight.w700 : FontWeight.w500)),
        ]);
      },
    );
  }
}