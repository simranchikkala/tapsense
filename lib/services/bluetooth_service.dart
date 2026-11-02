// lib/services/bluetooth_service.dart
//
// TapSense wallet over Bluetooth LE.
// Public API used by screens (unchanged): walletBluetooth.scan(), stopScan(),
// connect(), disconnect(), isConnected, events, buzz(), testBuzz(),
// sendBuzzForBudget(), sendBuzzLevel(), buzzes, scanError.
//
// Added for the physical wallet (see APP_WALLET_CHANGES.md / HARDWARE_BUILD.md):
//   - status …ab3 (read + notify): byte 0 battery %, byte 1 notes waiting
//       → batteryPercent, pendingNotes
//   - audio …ab4 (notify): voice-note packets → audioPackets
//   - commands: time sync [0x02, epoch u32], request note [0x03],
//       delete note [0x04, id u16]   (all little-endian)
//   - connected (ValueNotifier) so screens can react to connect/disconnect
//   - debugSimulateVoiceNote() / debugSimulateBattery(): fake wallet for testing
//
// Rules kept: UUIDs compared as Guid, notifications via onValueReceived +
// cancelWhenDisconnected, write type picked from char.properties,
// requestMtuIfSupported for MTU, every step logged with dlog('BLE', …).

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_platform.dart';
import 'crc32.dart';
import 'debug_log.dart';
import 'platform_caps.dart';

class WalletBluetooth {
  static const String SERVICE_UUID  = '12345678-1234-1234-1234-123456789abc';
  static const String EVENTS_UUID   = '12345678-1234-1234-1234-123456789ab1';
  static const String COMMANDS_UUID = '12345678-1234-1234-1234-123456789ab2';
  static const String STATUS_UUID   = '12345678-1234-1234-1234-123456789ab3';
  static const String AUDIO_UUID    = '12345678-1234-1234-1234-123456789ab4';

  static final Guid _serviceGuid  = Guid(SERVICE_UUID);
  static final Guid _eventsGuid   = Guid(EVENTS_UUID);
  static final Guid _commandsGuid = Guid(COMMANDS_UUID);
  static final Guid _statusGuid   = Guid(STATUS_UUID);
  static final Guid _audioGuid    = Guid(AUDIO_UUID);

  // ── Buzz level constants (firmware-compatible) ─────────────────────────────
  /// Normal single buzz — tap confirmed, within budget.
  static const int kBuzzNormal    = 0x01;
  /// Double buzz — approaching limit (>80% of category cap).
  static const int kBuzzNearLimit = 0x02;
  /// Long buzz — over limit, spend blocked / flagged.
  static const int kBuzzOverLimit = 0x03;

  // ── Command opcodes ─────────────────────────────────────────────────────────
  static const int _opBuzz        = 0x01;
  static const int _opTimeSync    = 0x02;
  static const int _opRequestNote = 0x03;
  static const int _opDeleteNote  = 0x04;

  // ── Audio packet types ──────────────────────────────────────────────────────
  static const int pktHeader = 0x10;
  static const int pktData   = 0x11;
  static const int pktEnd    = 0x12;
  static const int noNotesId = 0xFFFF;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _commandsChar;
  BluetoothCharacteristic? _statusChar;
  BluetoothCharacteristic? _audioChar;
  StreamSubscription<BluetoothConnectionState>? _connSub;

  final _eventController = StreamController<WalletEvent>.broadcast();
  final _buzzController  = StreamController<int>.broadcast();
  final _audioController = StreamController<List<int>>.broadcast();

  /// Wallet events (card removed, terminal tap, button pressed/released).
  Stream<WalletEvent> get events => _eventController.stream;

  /// Emits the buzz pattern (0x01–0x03) every time a buzz is sent.
  Stream<int> get buzzes => _buzzController.stream;

  /// Raw audio packets from the wallet (header / data / end).
  /// WalletVoiceSync reads these.
  Stream<List<int>> get audioPackets => _audioController.stream;

  /// Why the last scan couldn't start ('' when fine).
  final ValueNotifier<String> scanError = ValueNotifier<String>('');

  /// True while connected to a wallet that exposes the TapSense service.
  final ValueNotifier<bool> connected = ValueNotifier<bool>(false);

  /// Wallet battery % (null = unknown / not connected).
  final ValueNotifier<int?> batteryPercent = ValueNotifier<int?>(null);

  /// Voice notes waiting on the wallet.
  final ValueNotifier<int> pendingNotes = ValueNotifier<int>(0);

  /// When the wallet clock was last set (used for notes with timestamp 0).
  DateTime? lastTimeSync;

  /// Audio payload bytes per data packet (MTU − 3 ATT − 5 header).
  int audioPayloadSize = 20 - 5;

  bool get isConnected => _device?.isConnected == true;

  /// True once connected to a device exposing the TapSense service.
  bool get hasWalletService => _commandsChar != null;

  // ── Pairing-list helpers ───────────────────────────────────────────────────

  /// True if the device advertises the TapSense service UUID.
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
  // No withServices filter and no name filter (Fix #11).

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
  //
  // Manual pairing (Pairing screen) calls connect(). Once a device turns out
  // to be a TapSense wallet, its id is remembered and auto-reconnect takes
  // over: whenever the connection drops, or the app starts, or Bluetooth is
  // switched back on, the phone reconnects by itself when the wallet is in
  // range (the OS keeps trying in the background — no scanning needed).

  static const _savedIdKey = 'tapsense_wallet_remote_id_v1';

  /// True while waiting for the remembered wallet to come back in range.
  final ValueNotifier<bool> reconnecting = ValueNotifier<bool>(false);

  /// Id of the remembered wallet (per phone: on iOS it isn't the MAC address).
  String? savedWalletId;

  bool _autoReconnect = true;
  bool _wasConnected = false;
  Future<bool>? _setupFuture;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  Future<bool> connect(BluetoothDevice device) async {
    try {
      // iOS: connecting while scanning is slower and less reliable.
      if (FlutterBluePlus.isScanningNow) {
        await FlutterBluePlus.stopScan();
      }
      // Switching to a different wallet: drop the old one first.
      final old = _device;
      if (old != null && old.remoteId != device.remoteId) {
        await disconnect();
      }

      _autoReconnect = true;
      _attach(device);
      dlog('BLE', 'connecting to ${device.remoteId.str}');
      await device.connect(timeout: const Duration(seconds: 10));
      return await _setup(device);
    } catch (e, st) {
      dlogError('BLE', e, st);
      return false;
    }
  }

  /// Disconnects. Auto-reconnect pauses until the next manual pairing or app
  /// restart. With [forget], the remembered wallet is also cleared.
  Future<void> disconnect({bool forget = false}) async {
    _autoReconnect = false;
    reconnecting.value = false;
    try {
      await _device?.disconnect();
    } catch (e, st) {
      dlogError('BLE', e, st);
    }
    await _connSub?.cancel();
    _connSub = null;
    _device = null;
    _wasConnected = false;
    _clearCharacteristics();
    if (forget) await _saveWalletId(null);
    dlog('BLE', forget ? 'disconnected and wallet forgotten' : 'disconnected');
  }

  /// Forget the paired wallet (Settings → Forget wallet).
  Future<void> forgetWallet() => disconnect(forget: true);

  /// Call once at app start (main.dart). Reconnects to the remembered wallet
  /// now and whenever Bluetooth is switched back on. Never shows a permission
  /// prompt by itself.
  Future<void> initAutoReconnect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      savedWalletId = prefs.getString(_savedIdKey);
      if (savedWalletId == null) {
        dlog('BLE', 'auto-reconnect: no wallet paired yet');
        return;
      }
      dlog('BLE', 'auto-reconnect: remembered wallet $savedWalletId');
      await _adapterSub?.cancel();
      _adapterSub = FlutterBluePlus.adapterState.listen((s) {
        if (s == BluetoothAdapterState.on) {
          _reconnectToSaved();
        } else if (s == BluetoothAdapterState.off) {
          reconnecting.value = false;
        }
      });
    } catch (e, st) {
      dlogError('BLE', e, st);
    }
  }

  Future<void> _reconnectToSaved() async {
    final id = savedWalletId;
    if (id == null || !_autoReconnect || connected.value) return;
    // Android 12+: needs the Nearby devices permission, which was granted
    // when the wallet was first paired. Don't prompt from the background.
    if (PlatformCaps.needsBlePermissionRequest &&
        !await Permission.bluetoothConnect.isGranted) {
      dlog('BLE', 'auto-reconnect skipped: Bluetooth permission not granted');
      return;
    }
    try {
      final device = _device?.remoteId.str == id
          ? _device!
          : BluetoothDevice.fromId(id);
      _attach(device);
      reconnecting.value = true;
      dlog('BLE', 'auto-reconnect: waiting for wallet $id');
      // autoConnect: the OS connects whenever the wallet is in range and
      // keeps doing so after every drop. Returns without waiting.
      await device.connect(autoConnect: true, mtu: null);
    } catch (e, st) {
      reconnecting.value = false;
      dlogError('BLE', e, st);
    }
  }

  /// Listen to one device's connection state (only one listener at a time).
  void _attach(BluetoothDevice device) {
    if (_device?.remoteId == device.remoteId && _connSub != null) return;
    _connSub?.cancel();
    _device = device;
    _wasConnected = false;
    _connSub = device.connectionState.listen((s) {
      dlog('BLE', 'connection: ${s.name}');
      if (s == BluetoothConnectionState.connected) {
        _wasConnected = true;
        // Covers auto-reconnects (manual connect() runs setup itself; the
        // shared future stops it running twice).
        unawaited(_setup(device));
      } else if (s == BluetoothConnectionState.disconnected) {
        _clearCharacteristics();
        if (_wasConnected) {
          _wasConnected = false;
          final willRetry = _autoReconnect && savedWalletId == device.remoteId.str;
          reconnecting.value = willRetry;
          if (willRetry) {
            dlog('BLE', 'connection lost — will reconnect when the wallet is back in range');
            unawaited(_reconnectToSaved());
          }
        }
      }
    });
  }

  /// Discovery + MTU + time sync + status. Safe to call twice at once.
  Future<bool> _setup(BluetoothDevice device) {
    return _setupFuture ??= _doSetup(device).whenComplete(() => _setupFuture = null);
  }

  Future<bool> _doSetup(BluetoothDevice device) async {
    if (connected.value) return true;
    try {
      final found = await _discoverServices();
      if (!found) {
        dlog('BLE', 'connected, but TapSense service not found on this device');
        return true; // still "connected" for the pairing screen's purposes
      }

      // Bigger packets for audio (Android only; iOS negotiates by itself).
      await requestMtuIfSupported(device, 247);
      audioPayloadSize = (device.mtuNow - 3 - 5).clamp(15, 512).toInt();
      dlog('BLE', 'MTU ${device.mtuNow} → audio payload $audioPayloadSize bytes');

      await sendTimeSync();
      await _readStatusOnce();

      await _saveWalletId(device.remoteId.str);
      reconnecting.value = false;
      connected.value = true;
      return true;
    } catch (e, st) {
      dlogError('BLE', e, st);
      return false;
    }
  }

  Future<void> _saveWalletId(String? id) async {
    savedWalletId = id;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id == null) {
        await prefs.remove(_savedIdKey);
      } else {
        await prefs.setString(_savedIdKey, id);
      }
    } catch (e, st) {
      dlogError('BLE', e, st);
    }
  }

  void _clearCharacteristics() {
    _commandsChar = null;
    _statusChar = null;
    _audioChar = null;
    connected.value = false;
    batteryPercent.value = null;
  }

  // ── Service discovery ──────────────────────────────────────────────────────

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
          await _subscribe(device, char, (data) {
            if (data.isEmpty) return;
            final event = WalletEvent.fromBytes(data);
            dlog('BLE', 'event: ${event.label}');
            _eventController.add(event);
          });
          dlog('BLE', 'events notifications on');
        } else if (char.uuid == _commandsGuid) {
          _commandsChar = char;
          dlog('BLE',
              'commands char found (write=${char.properties.write}, '
              'writeNoResp=${char.properties.writeWithoutResponse})');
        } else if (char.uuid == _statusGuid) {
          _statusChar = char;
          if (char.properties.notify || char.properties.indicate) {
            await _subscribe(device, char, _onStatus);
            dlog('BLE', 'status notifications on');
          }
        } else if (char.uuid == _audioGuid) {
          _audioChar = char;
          await _subscribe(device, char, (data) {
            if (data.isNotEmpty) _audioController.add(data);
          });
          dlog('BLE', 'audio notifications on');
        }
      }
    }
    if (found && _audioChar == null) {
      dlog('BLE', 'no audio characteristic (older firmware?) — voice sync off');
    }
    return found;
  }

  /// onValueReceived = real notifications only; auto-cancel on disconnect so
  /// reconnects don't double-listen.
  Future<void> _subscribe(BluetoothDevice device, BluetoothCharacteristic char,
      void Function(List<int>) onData) async {
    final sub = char.onValueReceived.listen(onData);
    device.cancelWhenDisconnected(sub);
    await char.setNotifyValue(true);
  }

  // ── Status (battery + notes waiting) ───────────────────────────────────────

  Future<void> _readStatusOnce() async {
    final char = _statusChar;
    if (char == null || !char.properties.read) return;
    try {
      _onStatus(await char.read());
    } catch (e, st) {
      dlogError('BLE', e, st);
    }
  }

  void _onStatus(List<int> data) {
    if (data.isEmpty) return;
    final int battery = data[0].clamp(0, 100).toInt();
    final waiting = data.length > 1 ? data[1] : pendingNotes.value;
    if (battery != batteryPercent.value || waiting != pendingNotes.value) {
      dlog('BLE', 'status: battery $battery%, notes waiting $waiting');
    }
    batteryPercent.value = battery;
    pendingNotes.value = waiting;
  }

  // ── Commands ───────────────────────────────────────────────────────────────

  /// Writes a command to the wallet. Returns false if it couldn't be sent.
  Future<bool> _writeCommand(List<int> bytes, String what) async {
    final char = _commandsChar;
    if (char == null) {
      dlog('BLE', '$what skipped: no commands characteristic');
      return false;
    }
    // iOS refuses a write type the characteristic doesn't declare.
    final withoutResponse =
        !char.properties.write && char.properties.writeWithoutResponse;
    try {
      await char.write(bytes, withoutResponse: withoutResponse);
      return true;
    } catch (e, st) {
      dlogError('BLE', e, st);
      return false;
    }
  }

  /// Send a raw buzz command: [0x01, pattern].
  Future<void> buzz(int pattern) async {
    if (await _writeCommand([_opBuzz, pattern], 'buzz')) {
      dlog('BLE', 'buzz 0x${pattern.toRadixString(16).padLeft(2, '0')} sent');
      _buzzController.add(pattern);
    }
  }

  /// Quick test buzz — fires a single normal buzz.
  Future<void> testBuzz() => buzz(kBuzzNormal);

  /// Set the wallet clock: [0x02, epoch u32] (Unix seconds, UTC).
  Future<void> sendTimeSync() async {
    final now = DateTime.now();
    final epoch = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    if (await _writeCommand([_opTimeSync, ..._u32le(epoch)], 'time sync')) {
      lastTimeSync = now;
      dlog('BLE', 'time sync sent ($epoch)');
    }
  }

  /// Ask the wallet for its oldest stored note: [0x03].
  /// Returns false if the request couldn't be sent.
  Future<bool> requestNextNote() async {
    if (_simNotes.isNotEmpty || !isConnected) return _simRequestNext();
    final ok = await _writeCommand([_opRequestNote], 'request note');
    if (ok) dlog('BLE', 'request note sent');
    return ok;
  }

  /// Delete a note on the wallet after it arrived and checked out: [0x04, id u16].
  Future<bool> deleteNote(int id) async {
    if (_simNotes.any((n) => n.id == id)) return _simDelete(id);
    final ok = await _writeCommand([_opDeleteNote, ..._u16le(id)], 'delete note');
    if (ok) dlog('BLE', 'delete note $id sent');
    return ok;
  }

  // ── Buzz intensity API ─────────────────────────────────────────────────────

  /// Send buzz based on budget percentage (spent / cap).
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
  Future<void> sendBuzzLevel(int level) async {
    if (!isConnected) return;
    assert(level >= 0x01 && level <= 0x03,
        'Buzz level must be 0x01, 0x02, or 0x03');
    await buzz(level);
  }

  // ── Testing without firmware (debug menu only) ─────────────────────────────
  //
  // A small fake wallet: it answers requestNextNote()/deleteNote() with the
  // same packets the real firmware sends, so the whole voice-sync flow can be
  // tested on a phone with no wallet connected.

  final List<_SimNote> _simNotes = [];
  int _simNextId = 1;

  /// Pretend the wallet sent an event byte (0x01–0x04).
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

  /// Pretend the wallet recorded [wav] (a complete WAV file) and is holding it.
  /// pendingNotes goes up, which makes WalletVoiceSync download it.
  void debugSimulateVoiceNote(Uint8List wav, {DateTime? recordedAt}) {
    final ts = recordedAt == null
        ? DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000
        : recordedAt.toUtc().millisecondsSinceEpoch ~/ 1000;
    _simNotes.add(_SimNote(_simNextId++, ts, wav));
    dlog('BLE', 'SIMULATED wallet voice note (${wav.length} bytes)');
    pendingNotes.value = _simNotes.length;
  }

  /// Pretend the wallet reported this battery level.
  void debugSimulateBattery(int pct) {
    dlog('BLE', 'SIMULATED battery $pct%');
    _onStatus([pct, pendingNotes.value]);
  }

  Future<bool> _simRequestNext() async {
    // Let the caller start listening before packets arrive.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (_simNotes.isEmpty) {
      _audioController.add([pktHeader, ..._u16le(noNotesId), ..._u32le(0), ..._u32le(0)]);
      return true;
    }
    final n = _simNotes.first;
    _audioController.add(
        [pktHeader, ..._u16le(n.id), ..._u32le(n.ts), ..._u32le(n.bytes.length)]);
    final size = audioPayloadSize < 100 ? 239 : audioPayloadSize;
    var seq = 0;
    for (var off = 0; off < n.bytes.length; off += size) {
      final end = (off + size).clamp(0, n.bytes.length).toInt();
      _audioController.add(
          [pktData, ..._u16le(n.id), ..._u16le(seq), ...n.bytes.sublist(off, end)]);
      seq++;
      if (seq % 25 == 0) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
    }
    _audioController.add([pktEnd, ..._u16le(n.id), ..._u32le(crc32(n.bytes))]);
    return true;
  }

  bool _simDelete(int id) {
    _simNotes.removeWhere((n) => n.id == id);
    dlog('BLE', 'SIMULATED delete note $id');
    pendingNotes.value = _simNotes.length;
    return true;
  }

  // ── Little-endian helpers ───────────────────────────────────────────────────

  static List<int> _u16le(int v) => [v & 0xFF, (v >> 8) & 0xFF];
  static List<int> _u32le(int v) =>
      [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF];

  void dispose() {
    _connSub?.cancel();
    scanError.dispose();
    _eventController.close();
    _buzzController.close();
    _audioController.close();
  }
}

class _SimNote {
  _SimNote(this.id, this.ts, this.bytes);
  final int id;
  final int ts;
  final Uint8List bytes;
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
    WalletEventType.buttonPressed  => 'Wallet button pressed (recording)',
    WalletEventType.buttonReleased => 'Wallet button released',
    WalletEventType.unknown        => 'Unknown event',
  };
}

// Singleton instance
final walletBluetooth = WalletBluetooth();