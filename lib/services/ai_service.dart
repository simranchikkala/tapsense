// lib/services/ai_service.dart
//
// Weekly digest AI service.
//
// Priority order:
//   1. Gemini Flash (free tier, university access)
//   2. OpenAI gpt-3.5-turbo (cheapest fallback)
//   3. Built-in rule-based summary (no API key needed)
//
// To enable Gemini: set GEMINI_API_KEY in your .env / app config.
// To enable OpenAI: set OPENAI_API_KEY in your .env / app config.
//
// For now both keys default to '' — the service falls through to the
// built-in summary so the app works without any API key.
// Drop in your key when you get stipend / uni access.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:tapsense/models/transaction.dart';
import 'package:tapsense/models/category.dart';

class AiService {
  // ── API keys ─────────────────────────────────────────────────────────────────
  // Replace with real keys when available.
  // Keep these in a secrets file / env — don't commit real keys.
  static const _geminiKey  = '';   // e.g. 'AIzaSy...'
  static const _openaiKey  = '';   // e.g. 'sk-...'

  // ── Public entry point ────────────────────────────────────────────────────────
  /// Returns a 3-5 sentence natural-language digest of the past 7 days.
  static Future<String> weeklyDigest(List<Transaction> weekTxs) async {
    if (weekTxs.isEmpty) {
      return 'No transactions recorded in the past 7 days. '
          'Start logging your spending to get personalised insights!';
    }

    final prompt = _buildPrompt(weekTxs);

    if (_geminiKey.isNotEmpty) {
      final result = await _callGemini(prompt);
      if (result != null) return result;
    }

    if (_openaiKey.isNotEmpty) {
      final result = await _callOpenAI(prompt);
      if (result != null) return result;
    }

    // Fallback — no API key needed
    return _builtInSummary(weekTxs);
  }

  // ── Prompt builder ────────────────────────────────────────────────────────────
  static String _buildPrompt(List<Transaction> txs) {
    final total = txs
        .where((t) => t.amount < 0)
        .fold(0.0, (s, t) => s + t.amount.abs());

    final byCategory = <String, double>{};
    for (final t in txs.where((t) => t.amount < 0)) {
      final cat = categoryById(t.categoryId);
      byCategory[cat.name] = (byCategory[cat.name] ?? 0) + t.amount.abs();
    }
    final sorted = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final catSummary = sorted
        .take(5)
        .map((e) => '${e.key}: S\$ ${e.value.toStringAsFixed(2)}')
        .join(', ');

    return '''
You are a personal finance assistant. Summarise the following week of spending
in 3-4 friendly, practical sentences. Mention the biggest category, any patterns,
and one actionable tip. Keep it under 120 words.

Total spent: S\$ ${total.toStringAsFixed(2)}
Transactions: ${txs.length}
By category: $catSummary
''';
  }

  // ── Gemini Flash (free via Google AI Studio) ──────────────────────────────────
  static Future<String?> _callGemini(String prompt) async {
    try {
      const model = 'gemini-1.5-flash';
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          '$model:generateContent?key=$_geminiKey');
      final body = jsonEncode({
        'contents': [
          {
            'parts': [{'text': prompt}]
          }
        ],
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 200,
        },
      });

      final res = await http
          .post(url,
              headers: {'Content-Type': 'application/json'}, body: body)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final candidates = json['candidates'] as List?;
        final text = candidates?.first?['content']?['parts']
                ?.first?['text'] as String?;
        if (text != null && text.isNotEmpty) return text.trim();
      }
    } catch (_) {}
    return null;
  }

  // ── OpenAI gpt-3.5-turbo (cheapest) ──────────────────────────────────────────
  static Future<String?> _callOpenAI(String prompt) async {
    try {
      final url = Uri.parse('https://api.openai.com/v1/chat/completions');
      final body = jsonEncode({
        'model': 'gpt-3.5-turbo',
        'messages': [
          {'role': 'user', 'content': prompt}
        ],
        'max_tokens': 200,
        'temperature': 0.7,
      });

      final res = await http
          .post(url, headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_openaiKey',
          }, body: body)
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final text = json['choices']?[0]?['message']?['content'] as String?;
        if (text != null && text.isNotEmpty) return text.trim();
      }
    } catch (_) {}
    return null;
  }

  // ── Built-in rule-based fallback ──────────────────────────────────────────────
  static String _builtInSummary(List<Transaction> txs) {
    final total = txs
        .where((t) => t.amount < 0)
        .fold(0.0, (s, t) => s + t.amount.abs());
    final income = txs
        .where((t) => t.amount > 0)
        .fold(0.0, (s, t) => s + t.amount);

    final byCategory = <String, double>{};
    for (final t in txs.where((t) => t.amount < 0)) {
      final cat = categoryById(t.categoryId);
      byCategory[cat.name] = (byCategory[cat.name] ?? 0) + t.amount.abs();
    }

    final sorted = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final top = sorted.isEmpty ? null : sorted.first;
    final txCount = txs.where((t) => t.amount < 0).length;

    final parts = <String>[];

    parts.add(
        'This week you made $txCount purchase${txCount == 1 ? '' : 's'}, '
        'spending a total of S\$ ${total.toStringAsFixed(2)}.');

    if (top != null) {
      final pct = total > 0 ? (top.value / total * 100).toStringAsFixed(0) : '0';
      parts.add('Your biggest category was ${top.key} at '
          'S\$ ${top.value.toStringAsFixed(2)} ($pct% of total spend).');
    }

    if (income > 0) {
      parts.add('You received S\$ ${income.toStringAsFixed(2)} in income '
          'this week.');
    }

    if (sorted.length >= 2) {
      final second = sorted[1];
      parts.add('${second.key} was your second-highest category '
          '(S\$ ${second.value.toStringAsFixed(2)}) — '
          'worth keeping an eye on.');
    } else {
      parts.add('Keep logging consistently to unlock deeper spending insights '
          'and weekly trends.');
    }

    return parts.join(' ');
  }
}