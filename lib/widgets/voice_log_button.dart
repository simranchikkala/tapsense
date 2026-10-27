// lib/widgets/voice_log_button.dart
//
// Voice log: tap → speak ("six fifty chicken rice at Maxwell, paid cash")
// → tap Done → the sentence is parsed (Gemini, or a built-in parser if no key)
// → "Voice log recorded" notification → Log Spend screen opens pre-filled,
// so the user can check it before saving.
//
// Requires: speech_to_text (flutter pub add speech_to_text)
// Android: RECORD_AUDIO permission + RecognitionService <queries> in
//          AndroidManifest.xml. iOS: mic + speech strings in Info.plist.

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:tapsense/app/theme.dart';
import 'package:tapsense/services/ai_service.dart';
import 'package:tapsense/services/app_notifications.dart';
import 'package:tapsense/services/debug_log.dart';

class VoiceLogButton extends StatelessWidget {
  const VoiceLogButton({super.key});

  Future<void> _start(BuildContext context) async {
    final transcript = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _VoiceSheet(),
    );
    if (transcript == null || transcript.trim().isEmpty) return;
    if (!context.mounted) return;

    // Parse (shows a small spinner while Gemini thinks)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: CircularProgressIndicator(color: kOrange),
      ),
    );
    final spend = await AiService.parseSpend(transcript);
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // close spinner

    dlog('VOICE',
        '"$transcript" → amount=${spend.amount} merchant=${spend.merchant} '
        'cat=${spend.categoryId} mode=${spend.paymentMode} ai=${spend.usedAi}');
    AppNotifications.voiceLogRecorded(spend.summary);

    context.push('/confirm-log', extra: {
      'triggerType': 'voice',
      'merchantName': spend.merchant,
      'merchantUen': null,
      'amount': spend.amount,
      'rawQr': null,
      'voiceTranscript': transcript,
      'categoryId': spend.categoryId,
      'paymentMode': spend.paymentMode,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () => _start(context),
        icon: const Icon(Icons.mic_none_rounded, size: 14),
        label: const Text('Voice Log', style: TextStyle(fontSize: 12)),
        style: OutlinedButton.styleFrom(
          foregroundColor: kOrange,
          side: BorderSide(color: kOrange),
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }
}

// ── Listening sheet ───────────────────────────────────────────────────────────

class _VoiceSheet extends StatefulWidget {
  const _VoiceSheet();

  @override
  State<_VoiceSheet> createState() => _VoiceSheetState();
}

class _VoiceSheetState extends State<_VoiceSheet> {
  final SpeechToText _speech = SpeechToText();
  String _words = '';
  String? _error;
  bool _ready = false;
  bool _listening = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final ok = await _speech.initialize(
        onError: _onError,
        onStatus: (s) {
          dlog('VOICE', 'status: $s');
          if (!mounted) return;
          setState(() => _listening = _speech.isListening);
        },
      );
      if (!mounted) return;
      if (!ok) {
        setState(() => _error =
            'Speech recognition is not available. Allow microphone access '
            'for TapSense in Settings, and check Google speech services '
            'are installed.');
        return;
      }
      setState(() => _ready = true);
      _listen();
    } catch (e, st) {
      dlogError('VOICE', e, st);
      if (mounted) setState(() => _error = 'Could not start voice input.');
    }
  }

  void _onError(SpeechRecognitionError e) {
    dlog('VOICE', 'error: ${e.errorMsg} (permanent=${e.permanent})');
    if (!mounted) return;
    setState(() {
      _listening = false;
      if (_words.isEmpty) {
        _error = e.errorMsg == 'error_no_match' ||
                e.errorMsg == 'error_speech_timeout'
            ? "Didn't catch that — tap the mic and try again."
            : 'Voice input error: ${e.errorMsg}';
      }
    });
  }

  Future<void> _listen() async {
    setState(() {
      _error = null;
      _listening = true;
    });
    await _speech.listen(
      onResult: _onResult,
      listenOptions: SpeechListenOptions(
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 4),
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: true,
      ),
    );
  }

  void _onResult(SpeechRecognitionResult r) {
    if (!mounted) return;
    setState(() => _words = r.recognizedWords);
  }

  Future<void> _done() async {
    await _speech.stop();
    if (mounted) Navigator.pop(context, _words);
  }

  @override
  void dispose() {
    _speech.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final surface = dark ? kSurface : kSurfaceLight;
    final border = dark ? kBorder : kBorderLight;
    final textP = dark ? kTextPrimary : kTextPrimaryLight;
    final textM = dark ? kTextMuted : kTextMutedLight;

    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, 32 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: border, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Text(
            _error != null
                ? 'Voice log'
                : _listening
                    ? 'Listening…'
                    : (_ready ? 'Tap the mic to speak' : 'Starting…'),
            style: TextStyle(
                color: textP, fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text('e.g. "Six fifty chicken rice at Maxwell, paid cash"',
              textAlign: TextAlign.center,
              style: TextStyle(color: textM, fontSize: 12)),
          const SizedBox(height: 24),

          // Mic button
          GestureDetector(
            onTap: !_ready
                ? null
                : (_listening ? () => _speech.stop() : _listen),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: _listening ? 92 : 80,
              height: _listening ? 92 : 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: kOrange.withOpacity(_listening ? 0.25 : 0.12),
                border: Border.all(color: kOrange, width: 2),
              ),
              child: Icon(
                  _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: kOrange,
                  size: 36),
            ),
          ),
          const SizedBox(height: 20),

          // Live transcript / error
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: dark ? kBg : kBgLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Text(
              _error ?? (_words.isEmpty ? '…' : '"$_words"'),
              style: TextStyle(
                  color: _error != null
                      ? (dark ? kError : kErrorLight)
                      : textP,
                  fontSize: 14,
                  fontStyle:
                      _words.isEmpty ? FontStyle.normal : FontStyle.italic),
            ),
          ),
          const SizedBox(height: 20),

          Row(children: [
            Expanded(
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Cancel', style: TextStyle(color: textM)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: _words.trim().isEmpty ? null : _done,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Done'),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}