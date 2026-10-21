import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:tapsense/models/transaction.dart';
import 'package:tapsense/services/local_db.dart';

class TransactionService {
  static final _client = Supabase.instance.client;

  static Future<bool> save(Transaction tx) async {
    try {
      await _client
          .from('transactions')
          .insert(tx.toMap())
          .timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      // ignore: avoid_print
      print('SUPABASE SAVE ERROR: $e');
      try {
        await LocalDb.insertTransaction(tx)
            .timeout(const Duration(seconds: 5));
      } catch (e2) {
        // ignore: avoid_print
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

  /// Returns total spend for today as a positive number (absolute value of debits).
  /// Amounts are stored as negative for debits, positive for credits.
  /// Use [includedCredits] to get net balance instead.
  static Future<double> todayTotal(String userId,
      {bool includeCredits = false}) async {
    final now = DateTime.now();
    final startLocal = DateTime(now.year, now.month, now.day);
    final startUtc = startLocal.toUtc().toIso8601String();
    try {
      final data = await _client
          .from('transactions')
          .select('amount')
          .eq('user_id', userId)
          .gte('created_at', startUtc);

      double spendTotal = 0;
      double creditTotal = 0;
      for (final row in (data as List)) {
        final amt = (row['amount'] as num).toDouble();
        if (amt < 0) {
          spendTotal += amt.abs(); // accumulate spend as positive
        } else {
          creditTotal += amt;
        }
      }
      // Return spend (positive) or net (spend - credits)
      return includeCredits ? (spendTotal - creditTotal) : spendTotal;
    } catch (_) {
      final local = await LocalDb.getAll(userId);
      double spendTotal = 0;
      for (final t in local) {
        if (t.createdAt.isAfter(startLocal) && t.amount < 0) {
          spendTotal += t.amount.abs();
        }
      }
      return spendTotal;
    }
  }

  /// Returns total spend for the current calendar month as a positive number.
  static Future<double> monthTotal(String userId) async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startUtc = startOfMonth.toUtc().toIso8601String();
    try {
      final data = await _client
          .from('transactions')
          .select('amount')
          .eq('user_id', userId)
          .gte('created_at', startUtc);

      double total = 0;
      for (final row in (data as List)) {
        final amt = (row['amount'] as num).toDouble();
        if (amt < 0) total += amt.abs();
      }
      return total;
    } catch (_) {
      return 0;
    }
  }

  /// Returns total spend for the current month broken down by category_id.
  static Future<Map<String, double>> monthTotalByCategory(
      String userId) async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final startUtc = startOfMonth.toUtc().toIso8601String();
    try {
      final data = await _client
          .from('transactions')
          .select('amount, category_id')
          .eq('user_id', userId)
          .gte('created_at', startUtc);

      final Map<String, double> totals = {};
      for (final row in (data as List)) {
        final amt = (row['amount'] as num).toDouble();
        if (amt >= 0) continue; // skip credits
        final cat = (row['category_id'] as String?) ?? 'other';
        totals[cat] = (totals[cat] ?? 0) + amt.abs();
      }
      return totals;
    } catch (_) {
      return {};
    }
  }
}