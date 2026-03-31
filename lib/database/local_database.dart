import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/expense_model.dart';
import '../models/goal_model.dart';
/// Singleton SQLite database for offline-first expense storage.
class LocalDatabase {
  LocalDatabase._();
  static final LocalDatabase instance = LocalDatabase._();

  static Database? _db;

  Future<Database> get database async {
    _db ??= await _initDb();
    return _db!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'fintrack.db');
    return openDatabase(
      path,
      version: 6,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE expenses (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        hash        TEXT    UNIQUE NOT NULL,
        amount      REAL    NOT NULL,
        merchant    TEXT    NOT NULL,
        category    TEXT    NOT NULL,
        bank        TEXT,
        date        INTEGER NOT NULL,
        note        TEXT,
        payment_method TEXT DEFAULT 'UPI',
        needs_review INTEGER DEFAULT 0,
        confidence  INTEGER DEFAULT 100,
        synced      INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE piggy_bank (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        amount     REAL    NOT NULL,
        date       INTEGER NOT NULL,
        expense_id INTEGER
      )
    ''');

    // Raw SMS deduplication — tracks the body+timestamp hash of every SMS
    // that has been processed, so the same message is never inserted twice
    // even if the inbox is scanned multiple times.
    await db.execute('''
      CREATE TABLE sms_hashes (
        hash TEXT PRIMARY KEY,
        date INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE goals (
        id TEXT PRIMARY KEY,
        goalName TEXT NOT NULL,
        targetAmount REAL NOT NULL,
        savedAmount REAL NOT NULL,
        status TEXT NOT NULL
      )
    ''');

    // Index for fast monthly queries
    await db.execute(
        'CREATE INDEX idx_expenses_date ON expenses(date)');
    await db.execute(
        'CREATE INDEX idx_expenses_needs_review ON expenses(needs_review)');

    await db.execute('''
      CREATE TABLE piggy_settings (
        id             INTEGER PRIMARY KEY CHECK (id = 1),
        mode           TEXT    NOT NULL DEFAULT 'roundoff',
        percentage     REAL    NOT NULL DEFAULT 5.0,
        fixed_amount   REAL    NOT NULL DEFAULT 10.0
      )
    ''');
    await db.insert('piggy_settings', {
      'id': 1,
      'mode': 'roundoff',
      'percentage': 5.0,
      'fixed_amount': 10.0,
    });
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE monthly_savings (
          id              INTEGER PRIMARY KEY AUTOINCREMENT,
          month           TEXT    UNIQUE NOT NULL,
          total_expenses  REAL    NOT NULL,
          budget          REAL    NOT NULL,
          savings         REAL    NOT NULL
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE piggy_settings (
          id             INTEGER PRIMARY KEY CHECK (id = 1),
          mode           TEXT    NOT NULL DEFAULT 'roundoff',
          percentage     REAL    NOT NULL DEFAULT 5.0,
          fixed_amount   REAL    NOT NULL DEFAULT 10.0
        )
      ''');
      await db.insert('piggy_settings', {
        'id': 1,
        'mode': 'roundoff',
        'percentage': 5.0,
        'fixed_amount': 10.0,
      });
    }
    if (oldVersion < 4) {
      await db.execute(
        "ALTER TABLE expenses ADD COLUMN payment_method TEXT DEFAULT 'UPI'",
      );
    }
    if (oldVersion < 5) {
      // Add raw SMS hash table for deduplication across multiple syncs.
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sms_hashes (
          hash TEXT PRIMARY KEY,
          date INTEGER NOT NULL
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE goals (
          id TEXT PRIMARY KEY,
          goalName TEXT NOT NULL,
          targetAmount REAL NOT NULL,
          savedAmount REAL NOT NULL,
          status TEXT NOT NULL
        )
      ''');
    }
  }

  // ── Expenses ────────────────────────────────────────────────────────────────

  /// Insert a new expense. Returns inserted id, or -1 if duplicate hash.
  Future<int> insertExpense(Expense expense) async {
    final db = await database;
    try {
      return await db.insert(
        'expenses',
        expense.toMap(),
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (_) {
      return -1;
    }
  }

  /// One-time cleanup script to fix historical data.
  Future<void> runHistoricalCleanup() async {
    final db = await database;
    
    // 1. Delete 'Income' (was never meant for expense tracking)
    await db.execute("DELETE FROM expenses WHERE category = 'Income'");
    
    // 2. Map legacy categories to definitive 8 categories
    await db.execute("UPDATE expenses SET category = 'Others' WHERE category = 'Transfers'");
    await db.execute("UPDATE expenses SET category = 'Others' WHERE category = 'Other'");
    await db.execute("UPDATE expenses SET category = 'Others' WHERE category = 'Miscellaneous'");
    await db.execute("UPDATE expenses SET category = 'Travel' WHERE category = 'Transport'");
    await db.execute("UPDATE expenses SET category = 'Food' WHERE category = 'Food & Dining'");
    await db.execute("UPDATE expenses SET category = 'Food' WHERE category = 'Food & Groceries'");
    await db.execute("UPDATE expenses SET category = 'Bills' WHERE category = 'Utilities'");    
    // 3. Clear any existing 'needs_review' flags to auto-confirm all past expenses
    await db.execute("UPDATE expenses SET needs_review = 0");
    
    // 4. Remove fuzzy duplicates that slipped into the DB before we fixed the deduplicator.
    // 20 minutes = 1200000 milliseconds
    await db.execute('''
      DELETE FROM expenses 
      WHERE id IN (
        SELECT e2.id 
        FROM expenses e1
        JOIN expenses e2 ON e1.id < e2.id 
          AND e1.amount = e2.amount 
          AND abs(e1.date - e2.date) <= 1200000
      )
    ''');
  }

  /// Check if an exact transaction hash already exists (strict deduplication).
  Future<bool> hashExists(String hash) async {
    final db = await database;
    final result = await db.query(
      'expenses',
      where: 'hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Check if a duplicate transaction exists based on amount and time window.
  /// (e.g. catches delayed duplicate SMS or Push vs SMS with different timestamps)
  Future<bool> isDuplicateExpense({
    required double amount,
    required DateTime date,
    int timeWindowMinutes = 20,
  }) async {
    final db = await database;
    // Window: +/- timeWindowMinutes
    final start = date.subtract(Duration(minutes: timeWindowMinutes)).millisecondsSinceEpoch;
    final end = date.add(Duration(minutes: timeWindowMinutes)).millisecondsSinceEpoch;

    // Fast numeric lookup for exact same amount in the time window
    final result = await db.query(
      'expenses',
      where: 'date >= ? AND date <= ? AND (amount > ? AND amount < ?)',
      whereArgs: [start, end, amount - 0.01, amount + 0.01],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  // ── SMS Hash Table ───────────────────────────────────────────────────────────

  /// Check if a raw SMS body hash has already been processed.
  Future<bool> smsHashExists(String hash) async {
    final db = await database;
    final result = await db.query(
      'sms_hashes',
      where: 'hash = ?',
      whereArgs: [hash],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  /// Record a raw SMS body hash so it is never reprocessed.
  Future<void> insertSmsHash(String hash, DateTime date) async {
    final db = await database;
    await db.insert(
      'sms_hashes',
      {'hash': hash, 'date': date.millisecondsSinceEpoch},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// Get all expenses for the current month, newest first.
  Future<List<Expense>> getMonthlyExpenses(DateTime month) async {
    final db = await database;
    final start = DateTime(month.year, month.month, 1)
        .millisecondsSinceEpoch;
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59)
        .millisecondsSinceEpoch;
    final rows = await db.query(
      'expenses',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start, end],
      orderBy: 'date DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  /// Get distinct expenses for ALL months (full history).
  Future<List<Expense>> getAllExpenses() async {
    final db = await database;
    final rows = await db.query('expenses', orderBy: 'date DESC');
    return rows.map(Expense.fromMap).toList();
  }

  /// Sum of all expense amounts in the given month (excluding pending review).
  Future<double> getMonthlyTotal(DateTime month) async {
    final db = await database;
    final start = DateTime(month.year, month.month, 1)
        .millisecondsSinceEpoch;
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59)
        .millisecondsSinceEpoch;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM expenses WHERE date >= ? AND date <= ?',
      [start, end],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Category breakdown for the current month.
  Future<Map<String, double>> getCategoryBreakdown(DateTime month) async {
    final db = await database;
    final start = DateTime(month.year, month.month, 1)
        .millisecondsSinceEpoch;
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59)
        .millisecondsSinceEpoch;
    final rows = await db.rawQuery(
      'SELECT category, SUM(amount) as total FROM expenses WHERE date >= ? AND date <= ? GROUP BY category ORDER BY total DESC',
      [start, end],
    );
    return {
      for (final r in rows)
        r['category'] as String: (r['total'] as num).toDouble()
    };
  }

  // ── Piggy Bank ───────────────────────────────────────────────────────────────

  Future<int> insertSavings(PiggyBankEntry entry) async {
    final db = await database;
    return db.insert('piggy_bank', entry.toMap());
  }

  Future<double> getTotalSavings() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT SUM(amount) as total FROM piggy_bank');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<int> getSavingsCount() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM piggy_bank');
    return (result.first['cnt'] as int?) ?? 0;
  }

  /// Delete piggy_bank entries whose date falls in [start, end].
  Future<void> deleteSavingsBetween(DateTime start, DateTime end) async {
    final db = await database;
    await db.delete(
      'piggy_bank',
      where: 'date >= ? AND date <= ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
  }

  /// Sum of savings between two dates.
  Future<double> getSavingsBetween(DateTime start, DateTime end) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM piggy_bank WHERE date >= ? AND date <= ?',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Count of savings entries between two dates.
  Future<int> getSavingsCountBetween(DateTime start, DateTime end) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM piggy_bank WHERE date >= ? AND date <= ?',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  // ── Piggy Settings ────────────────────────────────────────────────────────────

  /// Read the single piggy_settings row (id = 1).
  Future<Map<String, Object?>> getPiggySettings() async {
    final db = await database;
    final rows = await db.query('piggy_settings', where: 'id = 1', limit: 1);
    if (rows.isNotEmpty) return rows.first;
    return {'mode': 'roundoff', 'percentage': 5.0, 'fixed_amount': 10.0};
  }

  /// Update piggy_settings row (upsert).
  Future<void> updatePiggySettings({
    required String mode,
    required double percentage,
    required double fixedAmount,
  }) async {
    final db = await database;
    await db.update(
      'piggy_settings',
      {'mode': mode, 'percentage': percentage, 'fixed_amount': fixedAmount},
      where: 'id = 1',
    );
  }

  // ── Goals ────────────────────────────────────────────────────────────────────

  Future<int> insertGoal(Goal goal) async {
    final db = await database;
    return await db.insert(
      'goals',
      goal.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Goal>> getAllGoals() async {
    final db = await database;
    final rows = await db.query('goals');
    return rows.map((e) => Goal.fromMap(e)).toList();
  }

  Future<int> updateGoal(Goal goal) async {
    final db = await database;
    return await db.update(
      'goals',
      goal.toMap(),
      where: 'id = ?',
      whereArgs: [goal.id],
    );
  }

  Future<int> deleteGoal(String id) async {
    final db = await database;
    return await db.delete(
      'goals',
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}
