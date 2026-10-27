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
import 'package:tapsense/config/env.dart';
import 'package:tapsense/services/debug_log.dart';

/// Result of parsing a voice log.
class VoiceSpend {
  VoiceSpend({
    required this.transcript,
    this.amount,
    this.merchant,
    this.categoryId = 'other',
    this.paymentMode,
    this.usedAi = false,
  });

  final String transcript;
  final double? amount;
  final String? merchant;
  final String categoryId;
  final String? paymentMode;
  final bool usedAi;

  /// Short text for the "Voice log recorded" notification.
  String get summary {
    final parts = <String>[
      if (amount != null) 'S\$${amount!.toStringAsFixed(2)}',
      if (merchant != null) 'at $merchant',
    ];
    return parts.isEmpty ? '"$transcript"' : parts.join(' ');
  }

  /// Built-in parser (no API key needed): first number = amount,
  /// words after "at" / "from" / "@" = merchant, category by name match.
  factory VoiceSpend.basic(String transcript) {
    final lower = transcript.toLowerCase();

    final m = RegExp(r'(\d+(?:[.,]\d{1,2})?)').firstMatch(lower);
    final amount =
        m == null ? null : double.tryParse(m.group(1)!.replaceAll(',', '.'));

    String? merchant;
    final mm = RegExp(r'\b(?:at|from|@)\s+([a-z0-9&\x27\- ]{2,40})')
        .firstMatch(lower);
    if (mm != null) {
      merchant = mm
          .group(1)!
          .replaceAll(RegExp(r'\b(for|with|using|by|paid|today|yesterday)\b.*$'), '')
          .trim();
      if (merchant.isEmpty) {
        merchant = null;
      } else {
        merchant = merchant
            .split(' ')
            .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
            .join(' ');
      }
    }

    var categoryId = 'other';
    for (final c in kCategories) {
      if (lower.contains(c.name.toLowerCase())) {
        categoryId = c.id;
        break;
      }
    }

    String? mode;
    if (lower.contains('cash')) {
      mode = 'cash';
    } else if (lower.contains('paynow') || lower.contains('qr')) {
      mode = 'sgqr';
    } else if (lower.contains('card')) {
      mode = 'card';
    }

    return VoiceSpend(
      transcript: transcript,
      amount: amount,
      merchant: merchant,
      categoryId: categoryId,
      paymentMode: mode,
    );
  }
}

class AiService {
  // ── API keys ─────────────────────────────────────────────────────────────────
  // Replace with real keys when available.
  // Keep these in a secrets file / env — don't commit real keys.
  // Gemini key comes from env.json → Env.geminiApiKey (used in _callGemini).
  static const _openaiKey  = '';   // e.g. 'sk-...'

  // ── Public entry point ────────────────────────────────────────────────────────
  /// Returns a 3-5 sentence natural-language digest of the past 7 days.
  static Future<String> weeklyDigest(List<Transaction> weekTxs) async {
    if (weekTxs.isEmpty) {
      return 'No transactions recorded in the past 7 days. '
          'Start logging your spending to get personalised insights!';
    }

    final prompt = _buildPrompt(weekTxs);

    if (Env.geminiApiKey.isNotEmpty) {
      final result = await _callGemini(prompt, maxTokens: 1024);
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

  // ── Gemini (free tier via Google AI Studio) ───────────────────────────────────
  //
  // Fixes vs the old version:
  //  - the key was written as '$Env.geminiApiKey', which inserts the text
  //    "Env.geminiApiKey" instead of the key → every call failed silently.
  //    The key now goes in the x-goog-api-key header.
  //  - 'gemini-1.5-flash' has been shut down; the model now comes from
  //    Env.geminiModel (change it in env.json if Google retires it).
  //  - failures are written to the Debug log instead of being swallowed.
  static Future<String?> _callGemini(
    String prompt, {
    bool jsonOutput = false,
    double temperature = 0.7,
    int maxTokens = 1024,
  }) async {
    if (Env.geminiApiKey.isEmpty) return null;
    try {
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          '${Env.geminiModel}:generateContent');
      final body = jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt}
            ]
          }
        ],
        'generationConfig': {
          'temperature': temperature,
          'maxOutputTokens': maxTokens,
          if (jsonOutput) 'responseMimeType': 'application/json',
        },
      });

      final res = await http
          .post(url,
              headers: {
                'Content-Type': 'application/json',
                'x-goog-api-key': Env.geminiApiKey,
              },
              body: body)
          .timeout(const Duration(seconds: 20));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final candidates = json['candidates'] as List?;
        final List? parts = (candidates?.isNotEmpty == true)
            ? (candidates!.first['content']?['parts'] as List?)
            : null;
        final text = parts
            ?.map((p) => (p as Map)['text']?.toString() ?? '')
            .join()
            .trim();
        if (text != null && text.isNotEmpty) return text;
        dlog('AI', 'Gemini returned no text: ${res.body}');
      } else {
        final snippet =
            res.body.length > 300 ? res.body.substring(0, 300) : res.body;
        dlog('AI', 'Gemini HTTP ${res.statusCode} (${Env.geminiModel}): $snippet');
      }
    } catch (e, st) {
      dlogError('AI', e, st);
    }
    return null;
  }

  // ── Voice log parsing ─────────────────────────────────────────────────────────

  /// Turns a spoken sentence like "six fifty for chicken rice at the hawker
  /// centre, paid cash" into amount / merchant / category / payment mode.
  /// Uses Gemini when a key is set, otherwise (or on failure) a simple
  /// built-in parser, so voice logging always works.
  static Future<VoiceSpend> parseSpend(String transcript) async {
    final fallback = VoiceSpend.basic(transcript);
    if (Env.geminiApiKey.isEmpty || transcript.trim().isEmpty) return fallback;

    final cats = kCategories.map((c) => '${c.id} (${c.name})').join(', ');
    final prompt = '''
Extract one spending entry from this voice note recorded in Singapore.
Voice note: "$transcript"

Reply with JSON only, using exactly these keys:
{"amount": number or null, "merchant": string or null, "category_id": string, "payment_mode": string or null}

Rules:
- amount: the price in Singapore dollars as a positive number ("six fifty" = 6.5). null if no amount was said.
- merchant: the shop, stall or person paid, if mentioned. null otherwise.
- category_id: one of these ids: $cats. Use "other" if unsure.
- payment_mode: one of manual, sgqr, nfc, card, cash, other — only if the user said how they paid
  (PayNow/QR = sgqr, tapped phone/watch = nfc, credit/debit card = card). null otherwise.
''';

    final text = await _callGemini(prompt, jsonOutput: true, temperature: 0.1);
    if (text == null) return fallback;
    try {
      final cleaned = text
          .replaceAll(RegExp(r'^```(json)?', multiLine: true), '')
          .replaceAll('```', '')
          .trim();
      final j = jsonDecode(cleaned) as Map<String, dynamic>;
      final amount = (j['amount'] as num?)?.toDouble().abs();
      final catId = j['category_id']?.toString();
      final mode = j['payment_mode']?.toString();
      return VoiceSpend(
        transcript: transcript,
        amount: amount ?? fallback.amount,
        merchant: (j['merchant']?.toString().trim().isNotEmpty == true)
            ? j['merchant'].toString().trim()
            : fallback.merchant,
        categoryId: kCategories.any((c) => c.id == catId)
            ? catId!
            : fallback.categoryId,
        paymentMode: _paymentModes.contains(mode) ? mode : null,
        usedAi: true,
      );
    } catch (e) {
      dlog('AI', 'Could not read Gemini JSON: $text');
      return fallback;
    }
  }

  static const _paymentModes = ['manual', 'sgqr', 'nfc', 'card', 'cash', 'other'];

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