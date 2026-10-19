import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/models/transaction.dart';
import 'package:tapsense/services/local_db.dart';

class TransactionService {
  static final _client = Supabase.instance.client;

  /// Save transaction — tries Supabase first, falls back to SQLite
  static Future<bool> save(Transaction tx) async {
    // Always save locally first
    await LocalDb.insertTransaction(tx);

    try {
      await _client.from('transactions').insert(tx.toMap());
      await LocalDb.markSynced(tx.createdAt.toIso8601String());
      return true;
    } catch (_) {
      return false; // saved locally, will sync later
    }
  }

  /// Sync any unsynced local transactions to Supabase
  static Future<void> syncPending() async {
    final unsynced = await LocalDb.getUnsynced();
    for (final tx in unsynced) {
      try {
        await _client.from('transactions').insert(tx.toMap());
        await LocalDb.markSynced(tx.createdAt.toIso8601String());
      } catch (_) {
        break; // no connection, try again later
      }
    }
  }

  /// Fetch recent transactions from Supabase (or local if offline)
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

  /// Today's total spend
  static Future<double> todayTotal(String userId) async {
    final today = DateTime.now();
    final start = DateTime(today.year, today.month, today.day)
        .toIso8601String();
    try {
      final data = await _client
          .from('transactions')
          .select('amount')
          .eq('user_id', userId)
          .gte('created_at', start);
      return (data as List)
          .fold(0.0, (sum, row) => sum + (row['amount'] as num).toDouble());
    } catch (_) {
      final local = await LocalDb.getAll(userId);
      return local
          .where((t) => t.createdAt.isAfter(
              DateTime(today.year, today.month, today.day)))
          .fold(0.0, (sum, t) => sum + t.amount);
    }
  }
}