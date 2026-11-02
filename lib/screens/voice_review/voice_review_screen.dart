// lib/screens/voice_review/voice_review_screen.dart
//
// Voice notes recorded on the wallet, waiting to be confirmed.
// Each draft: when it was recorded, what Gemini understood, a play button,
// Confirm (→ Log Spend, pre-filled, keeps the recorded time) and Discard.
//
// Route: /voice-review   (add to lib/app/router.dart)

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/config/env.dart';
import 'package:tapsense/models/category.dart';
import 'package:tapsense/services/ai_service.dart';
import 'package:tapsense/services/debug_log.dart';
import 'package:tapsense/services/voice_drafts.dart';
import 'package:tapsense/services/wallet_voice_sync.dart';

class VoiceReviewScreen extends StatefulWidget {
  const VoiceReviewScreen({super.key});

  @override
  State<VoiceReviewScreen> createState() => _VoiceReviewScreenState();
}

class _VoiceReviewScreenState extends State<VoiceReviewScreen> {
  final AudioPlayer _player = AudioPlayer();
  String? _playingId;
  final Set<String> _reparsing = {};
  StreamSubscription<PlayerState>? _playerSub;

  @override
  void initState() {
    super.initState();
    _playerSub = _player.playerStateStream.listen((s) {
      if (s.processingState == ProcessingState.completed && mounted) {
        setState(() => _playingId = null);
      }
    });
  }

  @override
  void dispose() {
    _playerSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

  Future<void> _togglePlay(VoiceDraft d) async {
    try {
      if (_playingId == d.id) {
        await _player.stop();
        setState(() => _playingId = null);
        return;
      }
      await _player.stop();
      await _player.setFilePath(d.filePath);
      setState(() => _playingId = d.id);
      unawaited(_player.play());
    } catch (e, st) {
      dlogError('VOICE_SYNC', e, st);
      if (mounted) {
        setState(() => _playingId = null);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not play this recording'),
          backgroundColor: kError,
        ));
      }
    }
  }

  Future<void> _confirm(VoiceDraft d) async {
    await _player.stop();
    setState(() => _playingId = null);
    final saved = await context.push<bool>('/confirm-log', extra: {
      'triggerType': 'voice',
      'merchantName': d.merchant,
      'merchantUen': null,
      'amount': d.amount,
      'rawQr': null,
      'voiceTranscript': d.transcript,
      'categoryId': d.categoryId,
      'paymentMode': d.paymentMode,
      'createdAt': d.recordedAt.toIso8601String(),
    });
    if (saved == true) {
      await VoiceDrafts.instance.remove(d.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Voice log saved'),
          backgroundColor: kAccent,
        ));
      }
    }
  }

  Future<void> _discard(VoiceDraft d, Color surface, Color textP, Color textS) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Discard voice log?', style: TextStyle(color: textP)),
        content: Text('The recording will be deleted from this phone.',
            style: TextStyle(color: textS)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(color: textS)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard', style: TextStyle(color: kError)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (_playingId == d.id) {
      await _player.stop();
      _playingId = null;
    }
    await VoiceDrafts.instance.remove(d.id);
  }

  /// Try Gemini again (e.g. it failed while offline).
  Future<void> _reparse(VoiceDraft d) async {
    setState(() => _reparsing.add(d.id));
    try {
      final spend = await AiService.parseSpendAudio(File(d.filePath));
      if (spend.usedAi) {
        await VoiceDrafts.instance.replace(VoiceDraft(
          id: d.id,
          filePath: d.filePath,
          recordedAt: d.recordedAt,
          transcript: spend.transcript,
          amount: spend.amount,
          merchant: spend.merchant,
          categoryId: spend.categoryId,
          paymentMode: spend.paymentMode,
          usedAi: true,
        ));
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Still could not read it — check the Debug log'),
          backgroundColor: kError,
        ));
      }
    } finally {
      if (mounted) setState(() => _reparsing.remove(d.id));
    }
  }

  // ── UI ──────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? kBg : kBgLight;
    final surface = dark ? kSurface : kSurfaceLight;
    final border = dark ? kBorder : kBorderLight;
    final textP = dark ? kTextPrimary : kTextPrimaryLight;
    final textS = dark ? kTextSecondary : kTextSecondaryLight;
    final textM = dark ? kTextMuted : kTextMutedLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        leading: BackButton(color: textP),
        title: Text('Wallet voice logs',
            style: TextStyle(
                color: textP, fontSize: 20, fontWeight: FontWeight.w700)),
        actions: [
          ValueListenableBuilder<bool>(
            valueListenable: WalletVoiceSync.instance.syncing,
            builder: (_, syncing, __) => syncing
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: kAccent)),
                  )
                : IconButton(
                    tooltip: 'Check wallet for new notes',
                    icon: Icon(Icons.sync, color: textS),
                    onPressed: WalletVoiceSync.instance.syncNow,
                  ),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<VoiceDraft>>(
        valueListenable: VoiceDrafts.instance.drafts,
        builder: (context, drafts, _) {
          if (drafts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.mic_none_rounded, color: textM, size: 52),
                  const SizedBox(height: 14),
                  Text('No voice logs to review',
                      style: TextStyle(color: textS, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text(
                      'Hold the button on your wallet and say what you spent. '
                      'It syncs here the next time the wallet connects.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: textM, fontSize: 12)),
                ]),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
            itemCount: drafts.length,
            itemBuilder: (_, i) =>
                _draftCard(drafts[i], dark, surface, border, textP, textS, textM),
          );
        },
      ),
    );
  }

  Widget _draftCard(VoiceDraft d, bool dark, Color surface, Color border,
      Color textP, Color textS, Color textM) {
    final cat = kCategories.firstWhere((c) => c.id == d.categoryId,
        orElse: () => kCategories.firstWhere((c) => c.id == 'other'));
    final playing = _playingId == d.id;
    final reparsing = _reparsing.contains(d.id);
    final unread = d.transcript == AiService.voicePlaceholder;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          // Play / stop
          GestureDetector(
            onTap: () => _togglePlay(d),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kOrange.withOpacity(playing ? 0.25 : 0.12),
                border: Border.all(color: kOrange),
              ),
              child: Icon(playing ? Icons.stop_rounded : Icons.play_arrow_rounded,
                  color: kOrange, size: 24),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                d.amount != null
                    ? 'S\$ ${d.amount!.toStringAsFixed(2)}'
                        '${d.merchant != null ? ' · ${d.merchant}' : ''}'
                    : (d.merchant ?? 'Amount not detected'),
                style: TextStyle(
                    color: textP, fontSize: 15, fontWeight: FontWeight.w700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(children: [
                Icon(cat.icon, color: cat.color, size: 12),
                const SizedBox(width: 4),
                Text(cat.name, style: TextStyle(color: textM, fontSize: 11)),
                const SizedBox(width: 8),
                Text(DateFormat('d MMM, h:mm a').format(d.recordedAt),
                    style: TextStyle(color: textM, fontSize: 11)),
              ]),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        Text(
          unread ? 'Not transcribed — play it and fill in the details.' : '"${d.transcript}"',
          style: TextStyle(
              color: textS,
              fontSize: 12,
              fontStyle: unread ? FontStyle.normal : FontStyle.italic),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 12),
        Row(children: [
          if (unread && Env.geminiApiKey.isNotEmpty)
            TextButton.icon(
              onPressed: reparsing ? null : () => _reparse(d),
              icon: reparsing
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: kAccent))
                  : const Icon(Icons.auto_awesome, size: 14, color: kAccent),
              label: const Text('Try AI again',
                  style: TextStyle(color: kAccent, fontSize: 12)),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => _discard(d, surface, textP, textS),
            child: Text('Discard', style: TextStyle(color: textM, fontSize: 13)),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () => _confirm(d),
            style: ElevatedButton.styleFrom(
              backgroundColor: kAccent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
            ),
            child: const Text('Confirm', style: TextStyle(fontSize: 13)),
          ),
        ]),
      ]),
    );
  }
}