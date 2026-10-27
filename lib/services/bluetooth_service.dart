// lib/services/bluetooth_service.dart
//
// iOS-ready version (drop-in replacement — same public API as before:
// walletBluetooth.scan(), stopScan(), connect(), disconnect(), isConnected,
// events, buzz(), testBuzz(), sendBuzzForBudget(), sendBuzzLevel()).
//
// Fix #11 kept: no name/service filter in scan(), so ANY device appears.
// UUID matching still happens in _discoverServices() after connect.
//
// iOS changes:
//  - scan() waits for Bluetooth to be ready (iOS starts in "unknown") and
//    only requests permission_handler permissions on Android.
//  - startScan errors are caught + exposed via [scanError] instead of being
//    an unhandled async exception.
//  - Scanning is stopped before connecting (recommended on iOS).
//  - UUIDs compared as Guid (iOS reports uppercase UUIDs).
//  - Notifications use onValueReceived + cancelWhenDisconnected, so
//    reconnecting doesn't create duplicate event listeners.
//  - Writes pick with/without-response from the characteristic's properties
//    (iOS rejects the wrong write type).
//  - Every step is logged with dlog('BLE', ...) for the Debug log screen.
//  - displayName()/isLikelyWallet() help the pairing list on iOS, where many
//    devices have empty names.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'ble_platform.dart';
import 'debug_log.dart';

class WalletBluetooth {
  static const String SERVICE_UUID  = '12345678-1234-1234-1234-123456789abc';
  static const String EVENTS_UUID   = '12345678-1234-1234-1234-123456789ab1';
  static const String COMMANDS_UUID = '12345678-1234-1234-1234-123456789ab2';
  static const String STATUS_UUID   = '12345678-1234-1234-1234-123456789ab3';

  static final Guid _serviceGuid  = Guid(SERVICE_UUID);
  static final Guid _eventsGuid   = Guid(EVENTS_UUID);
  static final Guid _commandsGuid = Guid(COMMANDS_UUID);

  // ── Buzz level constants (firmware-compatible) ─────────────────────────────
  /// Normal single buzz — tap confirmed, within budget.
  static const int kBuzzNormal    = 0x01;
  /// Double buzz — approaching limit (>80% of category cap).
  static const int kBuzzNearLimit = 0x02;
  /// Long buzz — over limit, spend blocked / flagged.
  static const int kBuzzOverLimit = 0x03;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _commandsChar;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  final _eventController = StreamController<WalletEvent>.broadcast();

  /// Emits the buzz pattern (0x01–0x03) every time a buzz is sent to the wallet.
  /// WalletActivity listens to this to record buzzes in Wallet Activity.
  final _buzzController = StreamController<int>.broadcast();
  Stream<int> get buzzes => _buzzController.stream;

  /// Why the last scan couldn't start ('' when fine). Show it on the pairing
  /// screen with a ValueListenableBuilder.
  final ValueNotifier<String> scanError = ValueNotifier<String>('');

  Stream<WalletEvent> get events => _eventController.stream;
  bool get isConnected => _device?.isConnected == true;

  /// True once connected to a device exposing the TapSense service.
  bool get hasWalletService => _commandsChar != null;

  // ── Pairing-list helpers ───────────────────────────────────────────────────

  /// True if the device advertises the TapSense service UUID — use it to sort
  /// or highlight the wallet at the top of the pairing list.
  static bool isLikelyWallet(ScanResult r) =>
      r.advertisementData.serviceUuids.contains(_serviceGuid);

  /// Best available name. iOS often reports empty names for nearby devices.
  static String displayName(ScanResult r) {
    final adv = r.advertisementData.advName;
    if (adv.isNotEmpty) return adv;
    final platform = r.device.platformName;
    if (platform.isNotEmpty) return platform;
    final id = r.device.remoteId.str;
    return 'Unknown device (${id.length > 8 ? id.substring(0, 8) : id})';
  }

  // ── Scan ───────────────────────────────────────────────────────────────────
  //
  // No withServices filter and no name filter here (Fix #11).
  // Same signature as before, so existing callers keep working.

  Stream<List<ScanResult>> scan() {
    unawaited(_startScan());
    return FlutterBluePlus.scanResults;
  }

  Future<void> _startScan() async {
    scanError.value = '';

    if (!await requestBlePermissionsIfNeeded()) {
      scanError.value = 'Bluetooth permission denied.';
      dlog('BLE', 'scan not started: permission denied');
      return;
    }

    final ready = await ensureBluetoothReady();
    if (ready != BleReadiness.ready) {
      scanError.value = bleUserMessage(ready);
      dlog('BLE', 'scan not started: ${ready.name}');
      return;
    }

    try {
      dlog('BLE', 'scan start');
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    } catch (e, st) {
      scanError.value = 'Could not start scanning. Please try again.';
      dlogError('BLE', e, st);
    }
  }

  void stopScan() {
    FlutterBluePlus.stopScan().catchError((Object e) {
      dlog('BLE', 'stopScan: $e');
    });
  }

  // ── Connect ────────────────────────────────────────────────────────────────

  Future<bool> connect(BluetoothDevice device) async {
    try {
      // iOS: connecting while scanning is slower and less reliable.
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }

      dlog('BLE', 'connecting to ${device.remoteId.str}');
      await device.connect(timeout: const Duration(seconds: 10));
      _device = device;

      await _connSub?.cancel();
      _connSub = device.connectionState.listen((s) {
        dlog('BLE', 'connection: ${s.name}');
        if (s == BluetoothConnectionState.disconnected) {
          _commandsChar = null;
        }
      });

      final found = await _discoverServices();
      if (!found) {
        dlog('BLE', 'connected, but TapSense service not found on this device');
      }
      return true;
    } catch (e, st) {
      dlogError('BLE', e, st);
      return false;
    }
  }

  Future<void> disconnect() async {
    try {
      await _device?.disconnect();
    } catch (e, st) {
      dlogError('BLE', e, st);
    }
    await _connSub?.cancel();
    _connSub = null;
    _device = null;
    _commandsChar = null;
    dlog('BLE', 'disconnected');
  }

  // ── Service discovery ──────────────────────────────────────────────────────
  //
  // UUID check lives here — only after connect. Any BLE device can be picked
  // from the list, but buzz commands only work if it exposes our service.

  Future<bool> _discoverServices() async {
    final device = _device;
    if (device == null) return false;

    final services = await device.discoverServices();
    dlog('BLE',
        'services: ${services.map((s) => s.uuid.toString()).join(', ')}');

    var found = false;
    for (final service in services) {
      if (service.uuid != _serviceGuid) continue;
      found = true;

      for (final char in service.characteristics) {
        if (char.uuid == _eventsGuid) {
          // onValueReceived = real notifications only (lastValueStream also
          // replays the last value on subscribe → duplicate events).
          final sub = char.onValueReceived.listen((data) {
            if (data.isEmpty) return;
            final event = WalletEvent.fromBytes(data);
            dlog('BLE', 'event: ${event.label}');
            _eventController.add(event);
          });
          // Auto-cancel on disconnect so reconnects don't double-listen.
          device.cancelWhenDisconnected(sub);
          await char.setNotifyValue(true);
          dlog('BLE', 'events notifications on');
        } else if (char.uuid == _commandsGuid) {
          _commandsChar = char;
          dlog('BLE',
              'commands char found (write=${char.properties.write}, '
              'writeNoResp=${char.properties.writeWithoutResponse})');
        }
      }
    }
    return found;
  }

  // ── Commands ───────────────────────────────────────────────────────────────

  /// Send a raw buzz command: byte[0] = 0x01 (buzz opcode), byte[1] = pattern.
  Future<void> buzz(int pattern) async {
    final char = _commandsChar;
    if (char == null) {
      dlog('BLE', 'buzz skipped: no commands characteristic');
      return;
    }
    // iOS refuses a write type the characteristic doesn't declare.
    final withoutResponse =
        !char.properties.write && char.properties.writeWithoutResponse;
    try {
      await char.write([0x01, pattern], withoutResponse: withoutResponse);
      dlog('BLE', 'buzz 0x${pattern.toRadixString(16).padLeft(2, '0')} sent');
      _buzzController.add(pattern);
    } catch (e, st) {
      dlogError('BLE', e, st);
    }
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

  // ── Testing without firmware (debug menu only) ─────────────────────────────
  //
  // These fake what the firmware would send, so Wallet Activity and
  // notifications can be tested without the physical wallet. They do NOT
  // talk to any Bluetooth device.

  /// Pretend the wallet sent an event byte (0x01 card removed, 0x02 terminal
  /// tap, 0x03 button pressed, 0x04 button released).
  void debugSimulateEvent(int eventByte) {
    final event = WalletEvent.fromBytes([eventByte]);
    dlog('BLE', 'SIMULATED event: ${event.label}');
    _eventController.add(event);
  }

  /// Pretend a buzz was sent (records it in Wallet Activity).
  void debugSimulateBuzz(int pattern) {
    dlog('BLE', 'SIMULATED buzz 0x${pattern.toRadixString(16).padLeft(2, '0')}');
    _buzzController.add(pattern);
  }

  void dispose() {
    _connSub?.cancel();
    scanError.dispose();
    _eventController.close();
    _buzzController.close();
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