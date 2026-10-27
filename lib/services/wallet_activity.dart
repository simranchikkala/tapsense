// lib/services/wallet_activity.dart
//
// Records what the TapSense wallet does — card taps, card removed, button
// presses, and every buzz the app sends — into Supabase `wallet_events`.
// The Wallet Activity → Events tab shows these.
//
// Start once in main():  WalletActivity.instance.start();

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'app_notifications.dart';
import 'bluetooth_service.dart';
import 'debug_log.dart';

class ActivityItem {
  ActivityItem({required this.type, required this.label, required this.at});

  /// terminalTap | cardRemoved | buttonPressed | buttonReleased | unknown | buzz
  final String type;
  final String label;
  final DateTime at;

  factory ActivityItem.fromRow(Map<String, dynamic> r) => ActivityItem(
        type: r['type']?.toString() ?? 'unknown',
        label: r['label']?.toString() ?? '',
        at: DateTime.tryParse(r['created_at']?.toString() ?? '')?.toLocal() ??
            DateTime.now(),
      );
}

class WalletActivity {
  WalletActivity._();
  static final WalletActivity instance = WalletActivity._();

  /// Increments whenever a new item is recorded (Events tab listens to this).
  final ValueNotifier<int> changes = ValueNotifier<int>(0);

  StreamSubscription<WalletEvent>? _eventSub;
  StreamSubscription<int>? _buzzSub;

  void start() {
    _eventSub ??= walletBluetooth.events.listen(_onEvent);
    _buzzSub ??= walletBluetooth.buzzes.listen(_onBuzz);
  }

  void _onEvent(WalletEvent e) {
    record(type: e.type.name, label: e.label);
    if (e.type == WalletEventType.terminalTap) {
      AppNotifications.deviceTapped();
    }
  }

  void _onBuzz(int pattern) {
    final label = switch (pattern) {
      WalletBluetooth.kBuzzNormal => 'Buzz sent — within budget',
      WalletBluetooth.kBuzzNearLimit => 'Buzz sent — near limit',
      WalletBluetooth.kBuzzOverLimit => 'Buzz sent — over limit',
      _ => 'Buzz sent',
    };
    record(type: 'buzz', label: label);
  }

  Future<void> record({required String type, required String label}) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await Supabase.instance.client.from('wallet_events').insert({
        'user_id': uid,
        'type': type,
        'label': label,
      });
      changes.value++;
    } catch (e, st) {
      dlogError('ACTIVITY', e, st);
    }
  }

  /// Activity from the last [hours] hours, newest first.
  Future<List<ActivityItem>> load({int hours = 24}) async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return [];
    final since =
        DateTime.now().toUtc().subtract(Duration(hours: hours)).toIso8601String();
    final rows = await Supabase.instance.client
        .from('wallet_events')
        .select()
        .eq('user_id', uid)
        .gte('created_at', since)
        .order('created_at', ascending: false)
        .limit(200);
    return (rows as List)
        .map((r) => ActivityItem.fromRow(Map<String, dynamic>.from(r)))
        .toList();
  }
}