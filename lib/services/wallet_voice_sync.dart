// lib/services/wallet_voice_sync.dart
//
// Downloads voice notes the wallet recorded on its own, then turns each one
// into a draft for the user to review.
//
// Runs when the wallet connects with notes waiting, and again whenever the
// wallet's "notes waiting" count goes up.
//
// Per note:
//   request [0x03] → header / data… / end packets → check length + CRC-32
//   → save voice_<timestamp>_<id>.wav → delete on wallet [0x04, id]
//   → parse with Gemini (in the background) → draft + notification
// A bad note is NOT deleted: it's retried once, then sync stops until the
// next connect (logged as VOICE_SYNC in the Debug log).
//
// Start once in main():  WalletVoiceSync.instance.start();

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'ai_service.dart';
import 'app_notifications.dart';
import 'bluetooth_service.dart';
import 'crc32.dart';
import 'debug_log.dart';
import 'voice_drafts.dart';
import 'wallet_activity.dart';

enum _NoteStatus { ok, none, failed, notSent }

class _NoteResult {
  _NoteResult(this.status, {this.id = 0, this.timestamp = 0, this.bytes, this.reason = ''});
  final _NoteStatus status;
  final int id;
  final int timestamp;
  final Uint8List? bytes;
  final String reason;
}

class WalletVoiceSync {
  WalletVoiceSync._();
  static final WalletVoiceSync instance = WalletVoiceSync._();

  /// True while notes are being downloaded (screens can show a spinner).
  final ValueNotifier<bool> syncing = ValueNotifier<bool>(false);

  bool _started = false;
  int _lastPending = 0;

  void start() {
    if (_started) return;
    _started = true;
    walletBluetooth.pendingNotes.addListener(_onPendingChanged);
    walletBluetooth.connected.addListener(_onConnectedChanged);
  }

  void _onConnectedChanged() {
    if (walletBluetooth.connected.value &&
        walletBluetooth.pendingNotes.value > 0) {
      syncNow();
    }
  }

  void _onPendingChanged() {
    final p = walletBluetooth.pendingNotes.value;
    if (p > _lastPending && p > 0) syncNow();
    _lastPending = p;
  }

  Future<void> syncNow() async {
    if (syncing.value) return;
    syncing.value = true;
    dlog('VOICE_SYNC', 'sync start (${walletBluetooth.pendingNotes.value} waiting)');
    var synced = 0;
    try {
      var failuresInRow = 0;
      for (var guard = 0; guard < 60; guard++) {
        final r = await _receiveOne();
        if (r.status == _NoteStatus.none) break;
        if (r.status == _NoteStatus.notSent) {
          dlog('VOICE_SYNC', 'could not send request — wallet not connected');
          break;
        }
        if (r.status == _NoteStatus.failed) {
          failuresInRow++;
          dlog('VOICE_SYNC', 'note ${r.id} failed: ${r.reason}'
              '${failuresInRow == 1 ? ' — retrying once' : ' — giving up for now'}');
          if (failuresInRow >= 2) break;
          continue;
        }
        failuresInRow = 0;
        await _handleNote(r);
        synced++;
      }
    } catch (e, st) {
      dlogError('VOICE_SYNC', e, st);
    } finally {
      syncing.value = false;
      dlog('VOICE_SYNC', 'sync finished — $synced note(s) downloaded');
    }
  }

  // ── One note ────────────────────────────────────────────────────────────────

  Future<_NoteResult> _receiveOne() async {
    final done = Completer<_NoteResult>();
    int? noteId;
    var timestamp = 0;
    var totalLen = 0;
    final chunks = <int, List<int>>{};
    int? firstSeq;
    Timer? idle;

    void finish(_NoteResult r) {
      if (!done.isCompleted) done.complete(r);
    }

    void resetIdle() {
      idle?.cancel();
      idle = Timer(const Duration(seconds: 8), () {
        finish(_NoteResult(_NoteStatus.failed,
            id: noteId ?? 0,
            reason: 'timed out waiting for audio '
                '(${chunks.length} packet(s), ${_bytesSoFar(chunks)}/$totalLen bytes)'));
      });
    }

    final sub = walletBluetooth.audioPackets.listen((p) {
      if (p.isEmpty) return;
      resetIdle();
      switch (p[0]) {
        case WalletBluetooth.pktHeader:
          if (p.length < 11) return;
          final id = _u16(p, 1);
          if (id == WalletBluetooth.noNotesId) {
            finish(_NoteResult(_NoteStatus.none));
            return;
          }
          noteId = id;
          timestamp = _u32(p, 3);
          totalLen = _u32(p, 7);
          chunks.clear();
          firstSeq = null;
        case WalletBluetooth.pktData:
          if (p.length < 5 || noteId == null || _u16(p, 1) != noteId) return;
          final seq = _u16(p, 3);
          firstSeq ??= seq; // firmware may count from 0 or 1
          chunks[seq] = p.sublist(5);
        case WalletBluetooth.pktEnd:
          if (p.length < 7 || noteId == null || _u16(p, 1) != noteId) return;
          final expectedCrc = _u32(p, 3);
          finish(_assemble(noteId!, timestamp, totalLen, chunks, firstSeq,
              expectedCrc));
      }
    });

    resetIdle();
    final sent = await walletBluetooth.requestNextNote();
    if (!sent) finish(_NoteResult(_NoteStatus.notSent));

    final result = await done.future;
    idle?.cancel();
    await sub.cancel();
    return result;
  }

  _NoteResult _assemble(int id, int ts, int totalLen, Map<int, List<int>> chunks,
      int? firstSeq, int expectedCrc) {
    if (chunks.isEmpty || firstSeq == null) {
      return _NoteResult(_NoteStatus.failed, id: id, reason: 'no data packets');
    }
    final seqs = chunks.keys.toList()..sort();
    for (var i = 0; i < seqs.length; i++) {
      if (seqs[i] != firstSeq + i) {
        return _NoteResult(_NoteStatus.failed,
            id: id, reason: 'missing packet ${firstSeq + i}');
      }
    }
    final all = <int>[];
    for (final s in seqs) {
      all.addAll(chunks[s]!);
    }
    final bytes = Uint8List.fromList(all);
    if (bytes.length != totalLen) {
      return _NoteResult(_NoteStatus.failed,
          id: id, reason: 'length ${bytes.length} ≠ expected $totalLen');
    }
    final crc = crc32(bytes);
    if (crc != expectedCrc) {
      return _NoteResult(_NoteStatus.failed,
          id: id,
          reason: 'CRC mismatch (got ${crc.toRadixString(16)}, '
              'wallet sent ${expectedCrc.toRadixString(16)})');
    }
    return _NoteResult(_NoteStatus.ok, id: id, timestamp: ts, bytes: bytes);
  }

  Future<void> _handleNote(_NoteResult r) async {
    // Timestamp 0 = wallet clock wasn't set yet → use the time we synced it.
    final recordedAt = r.timestamp == 0
        ? (walletBluetooth.lastTimeSync ?? DateTime.now())
        : DateTime.fromMillisecondsSinceEpoch(r.timestamp * 1000, isUtc: true)
            .toLocal();
    final tsForName = recordedAt.toUtc().millisecondsSinceEpoch ~/ 1000;

    final dir = Directory('${(await getApplicationDocumentsDirectory()).path}/voice_notes');
    if (!await dir.exists()) await dir.create(recursive: true);
    final file = File('${dir.path}/voice_${tsForName}_${r.id}.wav');
    await file.writeAsBytes(r.bytes!, flush: true);
    dlog('VOICE_SYNC', 'note ${r.id} saved (${r.bytes!.length} bytes) → ${file.path}');

    // Safe on the phone now → remove it from the wallet.
    await walletBluetooth.deleteNote(r.id);
    WalletActivity.instance
        .record(type: 'voiceNote', label: 'Voice note synced from wallet');

    // Parse in the background so the next note downloads straight away.
    unawaited(_parseIntoDraft(file, recordedAt, '${tsForName}_${r.id}'));
  }

  Future<void> _parseIntoDraft(File file, DateTime recordedAt, String id) async {
    VoiceSpend spend;
    try {
      spend = await AiService.parseSpendAudio(file);
    } catch (e, st) {
      dlogError('VOICE_SYNC', e, st);
      spend = VoiceSpend(transcript: AiService.voicePlaceholder);
    }
    await VoiceDrafts.instance.add(VoiceDraft(
      id: id,
      filePath: file.path,
      recordedAt: recordedAt,
      transcript: spend.transcript,
      amount: spend.amount,
      merchant: spend.merchant,
      categoryId: spend.categoryId,
      paymentMode: spend.paymentMode,
      usedAi: spend.usedAi,
    ));
    await AppNotifications.voiceLogRecorded(
        'Voice log from wallet: ${spend.usedAi ? spend.summary : 'tap to review'}');
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  static int _u16(List<int> b, int o) => b[o] | (b[o + 1] << 8);
  static int _u32(List<int> b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
  static int _bytesSoFar(Map<int, List<int>> c) =>
      c.values.fold(0, (s, x) => s + x.length);
}