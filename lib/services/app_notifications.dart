// lib/services/app_notifications.dart
//
// In-app notifications for TapSense.
// Each call:
//   1. saves a row to Supabase `wallet_notifications` (shown in Wallet Activity → Notifications)
//   2. shows the in-app banner at the top of the screen
//   3. bumps [changes] so open screens refresh
//
// Call the helper that matches what happened, e.g.
//   AppNotifications.qrScanned('Hawker Centre');
//   AppNotifications.voiceLogRecorded('S\$6.50 at Hawker Centre');
//   AppNotifications.categoryOverBudget('Food', spent: 120, cap: 100);
// Device taps are recorded automatically by WalletActivity.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'debug_log.dart';
import 'fcm_service.dart';

class AppNotifications {
  AppNotifications._();

  /// Increments whenever a notification is added (listen to refresh lists/badges).
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  static Future<void> notify(
    String title, {
    String body = '',
    bool showBanner = true,
  }) async {
    dlog('NOTIF', body.isEmpty ? title : '$title — $body');
    if (showBanner) FcmService.showBanner(title, body: body);

    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('wallet_notifications').insert({
        'user_id': uid,
        'title': title,
        'body': body,
        'read': false,
      });
      changes.value++;
    } catch (e, st) {
      dlogError('NOTIF', e, st);
    }
  }

  // ── The four TapSense notification types ──────────────────────────────────

  static Future<void> deviceTapped() => notify(
        'Device tapped by card activation',
        body: 'Your TapSense wallet detected a card tap.',
      );

  static Future<void> voiceLogRecorded(String summary) => notify(
        'Voice log recorded',
        body: summary,
      );

  /// BudgetService.checkAndNotify already shows its own banner, so this one
  /// only saves the notification unless [showBanner] is true.
  static Future<void> categoryOverBudget(
    String category, {
    required double spent,
    required double cap,
    bool showBanner = false,
  }) =>
      notify(
        'Category over budget',
        body: '$category: S\$${spent.toStringAsFixed(2)} of '
            'S\$${cap.toStringAsFixed(2)} used.',
        showBanner: showBanner,
      );

  static Future<void> qrScanned(String merchant) => notify(
        'QR scanned',
        body: merchant.isEmpty ? 'Payment QR scanned.' : 'Paying $merchant',
      );
}