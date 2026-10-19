import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

class WalletBluetooth {
  static const String SERVICE_UUID    = '12345678-1234-1234-1234-123456789abc';
  static const String EVENTS_UUID     = '12345678-1234-1234-1234-123456789ab1';
  static const String COMMANDS_UUID   = '12345678-1234-1234-1234-123456789ab2';
  static const String STATUS_UUID     = '12345678-1234-1234-1234-123456789ab3';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _commandsChar;
  final _eventController = StreamController<WalletEvent>.broadcast();

  Stream<WalletEvent> get events => _eventController.stream;
  bool get isConnected => _device?.isConnected == true;

  // Scan for TapSense wallet
  Stream<List<ScanResult>> scan() {
    FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
    return FlutterBluePlus.scanResults;
  }

  void stopScan() => FlutterBluePlus.stopScan();

  // Connect to wallet
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

  // Disconnect
  Future<void> disconnect() async {
    await _device?.disconnect();
    _device = null;
    _commandsChar = null;
  }

  // Discover services and subscribe to events
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

  // Send buzz command to wallet
  Future<void> buzz(int pattern) async {
    await _commandsChar?.write([0x01, pattern]);
  }

  // Send test buzz
  Future<void> testBuzz() => buzz(1);

  void dispose() {
    _eventController.close();
  }
}

// Wallet event types
enum WalletEventType { cardRemoved, terminalTap, buttonPressed, buttonReleased, unknown }

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