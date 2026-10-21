// lib/services/bluetooth_service.dart
//
// Fix #11: removed all BLE name/service filtering from scan() so ANY
// Bluetooth device name appears in the pairing screen, not just "TapSense".
// The firmware UUID filter (withServices) is also removed — it was preventing
// devices from appearing during discovery. UUID matching still happens in
// _discoverServices() after a successful connect.

import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WalletBluetooth {
  static const String SERVICE_UUID  = '12345678-1234-1234-1234-123456789abc';
  static const String EVENTS_UUID   = '12345678-1234-1234-1234-123456789ab1';
  static const String COMMANDS_UUID = '12345678-1234-1234-1234-123456789ab2';
  static const String STATUS_UUID   = '12345678-1234-1234-1234-123456789ab3';

  // ── Buzz level constants (firmware-compatible) ─────────────────────────────
  /// Normal single buzz — tap confirmed, within budget.
  static const int kBuzzNormal    = 0x01;
  /// Double buzz — approaching limit (>80% of category cap).
  static const int kBuzzNearLimit = 0x02;
  /// Long buzz — over limit, spend blocked / flagged.
  static const int kBuzzOverLimit = 0x03;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _commandsChar;
  final _eventController = StreamController<WalletEvent>.broadcast();

  Stream<WalletEvent> get events => _eventController.stream;
  bool get isConnected => _device?.isConnected == true;

  // ── Scan ───────────────────────────────────────────────────────────────────
  //
  // No withServices filter and no name filter here.
  // All nearby BLE devices will appear in the pairing screen so the user can
  // pick their TapSense wallet regardless of its advertised name.
  // UUID verification happens in _discoverServices() after pairing.

  Stream<List<ScanResult>> scan() {
    FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 10),
      // withServices: [],   // intentionally empty — show ALL devices
    );
    return FlutterBluePlus.scanResults;
  }

  void stopScan() => FlutterBluePlus.stopScan();

  // ── Connect ────────────────────────────────────────────────────────────────

  Future<bool> connect(BluetoothDevice device) async {
    try {
      await device.connect(timeout: const Duration(seconds: 10));
      _device = device;
      await _discoverServices();
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _commandsChar = null;
  }

  // ── Service discovery ──────────────────────────────────────────────────────
  //
  // UUID check lives here — only after connect. This means any BLE device
  // can be selected from the list, but buzz commands only work if the device
  // actually exposes our proprietary service UUIDs.

  Future<void> _discoverServices() async {
    final services = await _device!.discoverServices();
    for (final service in services) {
      if (service.uuid.toString().toLowerCase() ==
          SERVICE_UUID.toLowerCase()) {
        for (final char in service.characteristics) {
          final uuid = char.uuid.toString().toLowerCase();
          if (uuid == EVENTS_UUID.toLowerCase()) {
            await char.setNotifyValue(true);
            char.lastValueStream.listen((data) {
              if (data.isNotEmpty) {
                _eventController.add(WalletEvent.fromBytes(data));
              }
            });
          }
          if (uuid == COMMANDS_UUID.toLowerCase()) {
            _commandsChar = char;
          }
        }
      }
    }
  }

  // ── Commands ───────────────────────────────────────────────────────────────

  /// Send a raw buzz command: byte[0] = 0x01 (buzz opcode), byte[1] = pattern.
  Future<void> buzz(int pattern) async {
    await _commandsChar?.write([0x01, pattern]);
  }

  /// Quick test buzz — fires a single normal buzz.
  Future<void> testBuzz() => buzz(kBuzzNormal);

  // ── Buzz intensity API ─────────────────────────────────────────────────────

  /// Send buzz based on budget percentage.
  /// [spentFraction] is current spend / cap (e.g. 0.85 = 85% used).
  Future<void> sendBuzzForBudget(double spentFraction) async {
    if (!isConnected) return;
    if (spentFraction > 1.0) {
      await sendBuzzLevel(kBuzzOverLimit);
    } else if (spentFraction > 0.8) {
      await sendBuzzLevel(kBuzzNearLimit);
    } else {
      await sendBuzzLevel(kBuzzNormal);
    }
  }

  /// Send a specific buzz level directly.
  /// Use [kBuzzNormal], [kBuzzNearLimit], or [kBuzzOverLimit].
  Future<void> sendBuzzLevel(int level) async {
    if (!isConnected) return;
    assert(level >= 0x01 && level <= 0x03,
        'Buzz level must be 0x01, 0x02, or 0x03');
    await buzz(level);
  }

  void dispose() {
    _eventController.close();
  }
}

// ── Wallet events ──────────────────────────────────────────────────────────────

enum WalletEventType {
  cardRemoved,
  terminalTap,
  buttonPressed,
  buttonReleased,
  unknown,
}

class WalletEvent {
  final WalletEventType type;
  final DateTime timestamp;

  WalletEvent(this.type, this.timestamp);

  factory WalletEvent.fromBytes(List<int> data) {
    final type = switch (data[0]) {
      0x01 => WalletEventType.cardRemoved,
      0x02 => WalletEventType.terminalTap,
      0x03 => WalletEventType.buttonPressed,
      0x04 => WalletEventType.buttonReleased,
      _    => WalletEventType.unknown,
    };
    return WalletEvent(type, DateTime.now());
  }

  String get label => switch (type) {
    WalletEventType.cardRemoved    => 'Card removed',
    WalletEventType.terminalTap    => 'Terminal detected',
    WalletEventType.buttonPressed  => 'Button pressed',
    WalletEventType.buttonReleased => 'Button released',
    WalletEventType.unknown        => 'Unknown event',
  };
}

// Singleton instance
final walletBluetooth = WalletBluetooth();