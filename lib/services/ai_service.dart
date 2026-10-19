import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:tapsense/models/transaction.dart';
import 'package:tapsense/models/category.dart';

class AiService {
  // Replace with your key — use OpenAI or Anthropic
  static const _apiKey = 'YOUR_OPENAI_API_KEY';

  static Future<String> weeklyDigest(List<Transaction> txs) async {
    if (txs.isEmpty) return 'No transactions this week yet.';

    // Build summary for prompt
    final total = txs.fold(0.0, (s, t) => s + t.amount);
    final byCat = <String, double>{};
    for (final t in txs) {
      byCat[t.categoryId] = (byCat[t.categoryId] ?? 0) + t.amount;
    }
    final catLines = byCat.entries
        .map((e) => '${categoryById(e.key).name}: S\$${e.value.toStringAsFixed(2)}')
        .join(', ');

    final prompt = '''
You are a friendly personal finance assistant. 
Here is my spending for this week:
Total: S\$${total.toStringAsFixed(2)}
Breakdown: $catLines
Number of transactions: ${txs.length}

Write a short (3-4 sentence) friendly weekly spending summary. 
Note what I spent most on, whether it seems reasonable, 
and give one practical tip. Be warm and conversational, not preachy.
''';

    try {
      final response = await http.post(
        Uri.parse('https://api.openai.com/v1/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'gpt-4o-mini',
          'messages': [
            {'role': 'user', 'content': prompt}
          ],
          'max_tokens': 200,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['choices'][0]['message']['content'].trim();
      }
      return 'Could not load digest right now.';
    } catch (_) {
      return 'Could not load digest right now.';
    }
  }
}