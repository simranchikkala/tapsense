import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';
import 'package:tapsense/models/transaction.dart' as model;

class LocalDb {
  static Database? _db;

  static Future<Database> get db async {
    _db ??= await _open();
    return _db!;
  }

  static Future<Database> _open() async {
    final path = join(await getDatabasesPath(), 'tapsense.db');
    return openDatabase(path, version: 1, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE transactions (
          id TEXT,
          user_id TEXT NOT NULL,
          amount REAL NOT NULL,
          category_id TEXT NOT NULL,
          merchant_name TEXT,
          merchant_uen TEXT,
          note TEXT,
          trigger_type TEXT NOT NULL,
          raw_qr TEXT,
          created_at TEXT NOT NULL,
          synced INTEGER NOT NULL DEFAULT 0
        )
      ''');
    });
  }

  static Future<void> insertTransaction(model.Transaction tx) async {
    final d = await db;
    await d.insert('transactions', {
      ...tx.toMap(),
      'synced': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  static Future<List<model.Transaction>> getUnsynced() async {
    final d = await db;
    final rows = await d.query('transactions',
        where: 'synced = ?', whereArgs: [0]);
    return rows.map((r) => model.Transaction.fromMap(r)).toList();
  }

  static Future<List<model.Transaction>> getAll(String userId) async {
    final d = await db;
    final rows = await d.query('transactions',
        where: 'user_id = ?', whereArgs: [userId],
        orderBy: 'created_at DESC');
    return rows.map((r) => model.Transaction.fromMap(r)).toList();
  }

  static Future<void> markSynced(String createdAt) async {
    final d = await db;
    await d.update('transactions', {'synced': 1},
        where: 'created_at = ?', whereArgs: [createdAt]);
  }
}