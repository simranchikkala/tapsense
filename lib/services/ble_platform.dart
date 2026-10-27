import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'debug_log.dart';
import 'platform_caps.dart';

/// Result of checking whether Bluetooth can be used right now.
enum BleReadiness { ready, off, unauthorized, unsupported, unknown }

/// Android: requests Nearby devices (scan + connect) permissions.
/// iOS: does nothing — the system Bluetooth prompt appears automatically, and
/// a refusal shows up as BleReadiness.unauthorized.
///
/// Route ALL Bluetooth permission requests through this. Calling
/// Permission.bluetoothScan / bluetoothConnect / location on iOS returns
/// "denied" and would block scanning.
Future<bool> requestBlePermissionsIfNeeded() async {
  if (!PlatformCaps.needsBlePermissionRequest) return true;
  final statuses = await [
    Permission.bluetoothScan,
    Permission.bluetoothConnect,
  ].request();
  statuses.forEach((p, s) => dlog('BLE', 'permission $p: ${s.name}'));
  return statuses.values.every((s) => s.isGranted || s.isLimited);
}

/// Call before scanning.
///
/// Why: on iOS the adapter state starts as `unknown` for a moment (longer on
/// first launch while the permission prompt is up), and
/// `FlutterBluePlus.turnOn()` is Android-only (throws on iOS).
Future<BleReadiness> ensureBluetoothReady({
  Duration timeout = const Duration(seconds: 10),
}) async {
  try {
    if (!await FlutterBluePlus.isSupported) {
      dlog('BLE', 'Bluetooth LE not supported on this device');
      return BleReadiness.unsupported;
    }

    final state = await FlutterBluePlus.adapterState
        .firstWhere((s) =>
            s != BluetoothAdapterState.unknown &&
            s != BluetoothAdapterState.turningOn &&
            s != BluetoothAdapterState.turningOff)
        .timeout(timeout, onTimeout: () => BluetoothAdapterState.unknown);

    dlog('BLE', 'adapter state: ${state.name}');

    if (state == BluetoothAdapterState.off &&
        PlatformCaps.canTurnOnBluetoothFromApp) {
      try {
        await FlutterBluePlus.turnOn();
        dlog('BLE', 'turned Bluetooth on (Android)');
        return BleReadiness.ready;
      } catch (e, st) {
        dlogError('BLE', e, st);
      }
    }

    switch (state) {
      case BluetoothAdapterState.on:
        return BleReadiness.ready;
      case BluetoothAdapterState.off:
        return BleReadiness.off;
      case BluetoothAdapterState.unauthorized:
        return BleReadiness.unauthorized;
      case BluetoothAdapterState.unavailable:
        return BleReadiness.unsupported;
      default:
        return BleReadiness.unknown;
    }
  } catch (e, st) {
    dlogError('BLE', e, st);
    return BleReadiness.unknown;
  }
}

/// Friendly message to show the user when Bluetooth isn't ready.
String bleUserMessage(BleReadiness r) {
  switch (r) {
    case BleReadiness.ready:
      return '';
    case BleReadiness.off:
      return PlatformCaps.isIOS
          ? 'Turn on Bluetooth in Control Centre to connect your wallet.'
          : 'Turn on Bluetooth to connect your wallet.';
    case BleReadiness.unauthorized:
      return PlatformCaps.isIOS
          ? 'Allow Bluetooth for TapSense in Settings → TapSense.'
          : 'Allow the Nearby devices permission for TapSense.';
    case BleReadiness.unsupported:
      return 'This device does not support Bluetooth LE.';
    case BleReadiness.unknown:
      return 'Bluetooth is not ready yet. Please try again.';
  }
}

/// MTU negotiation is Android-only; iOS handles it automatically.
Future<void> requestMtuIfSupported(BluetoothDevice device, int mtu) async {
  if (!PlatformCaps.canRequestMtu) return;
  try {
    final result = await device.requestMtu(mtu);
    dlog('BLE', 'MTU set to $result');
  } catch (e, st) {
    dlogError('BLE', e, st);
  }
}