import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// One place for "does this platform support X?" checks, so iOS/Android
/// differences don't get scattered across screens.
class PlatformCaps {
  PlatformCaps._();

  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  /// Only Android lets an app switch Bluetooth on. iOS: ask the user to use
  /// Control Centre / Settings.
  static bool get canTurnOnBluetoothFromApp => isAndroid;

  /// Android needs runtime BLE permissions via permission_handler
  /// (bluetoothScan / bluetoothConnect). On iOS the system Bluetooth prompt
  /// appears by itself the first time the app uses Bluetooth.
  static bool get needsBlePermissionRequest => isAndroid;

  /// Android BLE remoteId is the MAC address; iOS gives a per-phone random
  /// UUID. Don't store remoteId in Supabase and expect it to match across phones.
  static bool get bleRemoteIdIsMac => isAndroid;

  /// MTU negotiation is Android-only; iOS negotiates automatically.
  static bool get canRequestMtu => isAndroid;
}