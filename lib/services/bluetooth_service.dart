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

  Stream<List<ScanResult>> scan() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
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

  Future<void> _discoverServices() async {
    final services = await _device!.discoverServices();
    for (final service in services) {
      if (service.uuid.toString() == SERVICE_UUID) {
        for (final char in service.characteristics) {
          final uuid = char.uuid.toString();
          if (uuid == EVENTS_UUID) {
            await char.setNotifyValue(true);
            char.lastValueStream.listen((data) {
              if (data.isNotEmpty) {
                _eventController.add(WalletEvent.fromBytes(data));
              }
            });
          }
          if (uuid == COMMANDS_UUID) {
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
  //
  // Called by budget_service after every transaction save.
  // The firmware maps byte[1] to vibration intensity:
  //   0x01 → single short buzz   (normal confirm)
  //   0x02 → double buzz         (approaching cap, >80%)
  //   0x03 → long continuous     (over cap — spend flagged)
  //
  // Stub: silently no-ops when wallet is not connected so callers
  // don't need to check connection state.

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