import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/models/transaction.dart';
import 'package:tapsense/services/local_db.dart';

class TransactionService {
  static final _client = Supabase.instance.client;

  static Future<bool> save(Transaction tx) async {
  // Try Supabase directly first, skip local DB for now
  try {
    await _client
        .from('transactions')
        .insert(tx.toMap())
        .timeout(const Duration(seconds: 10));
    return true;
  } catch (e) {
    print('SUPABASE SAVE ERROR: $e');
    // Fall back to local
    try {
      await LocalDb.insertTransaction(tx)
          .timeout(const Duration(seconds: 5));
    } catch (e2) {
      print('LOCAL SAVE ERROR: $e2');
    }
    return false;
  }
}

  static Future<void> syncPending() async {
    final unsynced = await LocalDb.getUnsynced();
    for (final tx in unsynced) {
      try {
        await _client.from('transactions').insert(tx.toMap());
        await LocalDb.markSynced(tx.createdAt.toIso8601String());
      } catch (_) {
        break;
      }
    }
  }

  static Future<List<Transaction>> fetchRecent(String userId,
      {int limit = 20}) async {
    try {
      final data = await _client
          .from('transactions')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (data as List).map((m) => Transaction.fromMap(m)).toList();
    } catch (_) {
      return LocalDb.getAll(userId);
    }
  }

  static Future<double> todayTotal(String userId) async {
    final now = DateTime.now();
    final startLocal = DateTime(now.year, now.month, now.day);
    final startUtc = startLocal.toUtc().toIso8601String();
    try {
      final data = await _client
          .from('transactions')
          .select('amount')
          .eq('user_id', userId)
          .gte('created_at', startUtc);
      double total = 0;
      for (final row in (data as List)) {
        total += (row['amount'] as num).toDouble();
      }
      return total;
    } catch (_) {
      final local = await LocalDb.getAll(userId);
      double total = 0;
      for (final t in local) {
        if (t.createdAt.isAfter(startLocal)) {
          total += t.amount;
        }
      }
      return total;
    }
  }
}