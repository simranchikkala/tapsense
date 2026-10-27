import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

/// One line in the in-app debug log.
class DebugLogEntry {
  DebugLogEntry(this.time, this.tag, this.message, {this.isError = false});

  final DateTime time;
  final String tag;
  final String message;
  final bool isError;

  @override
  String toString() =>
      '${time.toIso8601String()} [$tag]${isError ? ' ERROR' : ''} $message';
}

/// In-memory ring buffer of log lines, viewable on the Debug log screen.
///
/// Usage anywhere in the app:
///   dlog('BLE', 'connected to ${device.remoteId}');
///   dlogError('BLE', e, st);
///
/// Lets testers on iPhones (no Mac attached) copy the log and send it to you.
class DebugLog extends ChangeNotifier {
  DebugLog._();

  static final DebugLog instance = DebugLog._();

  static const int maxEntries = 500;

  final ListQueue<DebugLogEntry> _entries = ListQueue<DebugLogEntry>();
  bool _notifyScheduled = false;

  /// Optional extra sink, e.g. FirebaseCrashlytics.instance.log, so the last
  /// log lines are attached to crash reports. Set in main().
  void Function(String line)? onLine;

  List<DebugLogEntry> get entries => List.unmodifiable(_entries);

  void add(String tag, String message, {bool isError = false}) {
    final entry =
        DebugLogEntry(DateTime.now(), tag, message, isError: isError);
    _entries.addLast(entry);
    while (_entries.length > maxEntries) {
      _entries.removeFirst();
    }
    final line = entry.toString();
    debugPrint(line);
    try {
      onLine?.call(line);
    } catch (_) {
      // Never let logging crash the app.
    }
    _scheduleNotify();
  }

  void clear() {
    _entries.clear();
    _scheduleNotify();
  }

  /// Whole log as plain text (for copy / share).
  String export() => _entries.map((e) => e.toString()).join('\n');

  // Notify after the current frame/task so logging from inside build()
  // doesn't trigger "setState during build" errors.
  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      notifyListeners();
    });
  }
}

void dlog(String tag, String message) => DebugLog.instance.add(tag, message);

void dlogError(String tag, Object error, [StackTrace? stack]) =>
    DebugLog.instance.add(
      tag,
      stack == null ? '$error' : '$error\n$stack',
      isError: true,
    );