// lib/services/voice_drafts.dart
//
// Voice notes synced from the wallet wait here as DRAFTS until the user
// confirms (→ transaction) or discards them. Stored on the phone only
// (shared_preferences JSON + the WAV file); nothing is uploaded.
//
// Load once in main():  await VoiceDrafts.instance.load();

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'debug_log.dart';

class VoiceDraft {
  VoiceDraft({
    required this.id,
    required this.filePath,
    required this.recordedAt,
    required this.transcript,
    this.amount,
    this.merchant,
    this.categoryId = 'other',
    this.paymentMode,
    this.usedAi = false,
  });

  final String id;
  final String filePath;
  final DateTime recordedAt;
  final String transcript;
  final double? amount;
  final String? merchant;
  final String categoryId;
  final String? paymentMode;
  final bool usedAi;

  Map<String, dynamic> toJson() => {
        'id': id,
        'filePath': filePath,
        'recordedAt': recordedAt.toIso8601String(),
        'transcript': transcript,
        'amount': amount,
        'merchant': merchant,
        'categoryId': categoryId,
        'paymentMode': paymentMode,
        'usedAi': usedAi,
      };

  factory VoiceDraft.fromJson(Map<String, dynamic> j) => VoiceDraft(
        id: j['id'] as String,
        filePath: j['filePath'] as String,
        recordedAt: DateTime.tryParse(j['recordedAt']?.toString() ?? '') ??
            DateTime.now(),
        transcript: j['transcript']?.toString() ?? '',
        amount: (j['amount'] as num?)?.toDouble(),
        merchant: j['merchant'] as String?,
        categoryId: j['categoryId']?.toString() ?? 'other',
        paymentMode: j['paymentMode'] as String?,
        usedAi: j['usedAi'] == true,
      );
}

class VoiceDrafts {
  VoiceDrafts._();
  static final VoiceDrafts instance = VoiceDrafts._();

  static const _prefsKey = 'wallet_voice_drafts_v1';

  /// Newest first. Listen to this to show counts / lists.
  final ValueNotifier<List<VoiceDraft>> drafts =
      ValueNotifier<List<VoiceDraft>>(const []);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final list = (jsonDecode(raw) as List)
          .map((e) => VoiceDraft.fromJson(Map<String, dynamic>.from(e)))
          // Drop drafts whose audio file has gone (e.g. app data cleared)
          .where((d) => File(d.filePath).existsSync())
          .toList()
        ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      drafts.value = list;
      dlog('VOICE_SYNC', '${list.length} voice draft(s) waiting for review');
    } catch (e, st) {
      dlogError('VOICE_SYNC', e, st);
    }
  }

  Future<void> add(VoiceDraft d) async {
    final list = [d, ...drafts.value.where((x) => x.id != d.id)]
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    drafts.value = list;
    await _save();
  }

  Future<void> replace(VoiceDraft d) => add(d);

  /// Removes the draft and (by default) its WAV file.
  Future<void> remove(String id, {bool deleteFile = true}) async {
    final d = drafts.value.where((x) => x.id == id).firstOrNull;
    drafts.value = drafts.value.where((x) => x.id != id).toList();
    await _save();
    if (d != null && deleteFile) {
      try {
        final f = File(d.filePath);
        if (await f.exists()) await f.delete();
      } catch (e, st) {
        dlogError('VOICE_SYNC', e, st);
      }
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _prefsKey, jsonEncode(drafts.value.map((d) => d.toJson()).toList()));
    } catch (e, st) {
      dlogError('VOICE_SYNC', e, st);
    }
  }
}