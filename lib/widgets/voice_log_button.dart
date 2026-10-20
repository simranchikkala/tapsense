// lib/widgets/voice_log_button.dart
//
// Voice log button — speech_to_text integration.
// Requires: speech_to_text: ^6.6.0 in pubspec.yaml
//
// NOTE: speech_to_text 6.x uses jcenter() which is incompatible with
// Gradle 9+. Until resolved, this widget is disabled (shows a greyed-out
// mic). Re-enable by upgrading to speech_to_text ^7.0.0 when available
// and compatible with your Flutter/Gradle setup.

import 'package:flutter/material.dart';
import 'package:tapsense/app/theme.dart';

class VoiceLogButton extends StatelessWidget {
  const VoiceLogButton({super.key});

  @override
  Widget build(BuildContext context) {
    const color = kTextMuted;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.06),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mic_off_outlined, color: color, size: 18),
            SizedBox(height: 4),
            Text(
              'Voice Log',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}