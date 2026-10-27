import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../app/theme.dart';
import '../../services/debug_log.dart';

/// Shows the in-app debug log. Testers tap "Copy" and send you the text.
/// Route: /debug-log
class DebugLogScreen extends StatelessWidget {
  const DebugLogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = dark ? kBg : kBgLight;
    final border = dark ? kBorder : kBorderLight;
    final textP = dark ? kTextPrimary : kTextPrimaryLight;
    final textM = dark ? kTextMuted : kTextMutedLight;
    final errorColor = dark ? kError : kErrorLight;
    final timeFmt = DateFormat('HH:mm:ss.SSS');

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: textP,
        elevation: 0,
        title: const Text('Debug log'),
        actions: [
          IconButton(
            tooltip: 'Copy all',
            icon: const Icon(Icons.copy_rounded),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: DebugLog.instance.export()),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Log copied')),
                );
              }
            },
          ),
          IconButton(
            tooltip: 'Clear',
            icon: const Icon(Icons.delete_outline_rounded),
            onPressed: DebugLog.instance.clear,
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: DebugLog.instance,
        builder: (context, _) {
          final entries = DebugLog.instance.entries.reversed.toList();
          if (entries.isEmpty) {
            return Center(
              child: Text('No log entries yet',
                  style: TextStyle(color: textM)),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: entries.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: border),
            itemBuilder: (context, i) {
              final e = entries[i];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: SelectableText.rich(
                  TextSpan(
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontFamilyFallback: const ['Menlo', 'Courier'],
                      fontSize: 12,
                      color: e.isError ? errorColor : textP,
                    ),
                    children: [
                      TextSpan(
                        text: '${timeFmt.format(e.time)} ',
                        style: TextStyle(color: textM),
                      ),
                      TextSpan(
                        text: '[${e.tag}] ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: e.message),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}