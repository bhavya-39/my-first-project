import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/expense_model.dart';

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
      version: 3,
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

    await db.execute('''
      CREATE TABLE monthly_savings (
        id              INTEGER PRIMARY KEY AUTOINCREMENT,
        month           TEXT    UNIQUE NOT NULL,
        total_expenses  REAL    NOT NULL,
        budget          REAL    NOT NULL,
        savings         REAL    NOT NULL
      )
    ''');

    // Indexes for fast monthly queries
    await db.execute('CREATE INDEX idx_expenses_date ON expenses(date)');
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

  /// Check if a transaction hash already exists (deduplication).
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

  /// Get all expenses for the current month, newest first.
  Future<List<Expense>> getMonthlyExpenses(DateTime month) async {
    final db = await database;
    final start = DateTime(month.year, month.month, 1).millisecondsSinceEpoch;
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

  /// Get all expenses marked as needing user review.
  Future<List<Expense>> getPendingReview() async {
    final db = await database;
    final rows = await db.query(
      'expenses',
      where: 'needs_review = 1',
      orderBy: 'date DESC',
    );
    return rows.map(Expense.fromMap).toList();
  }

  /// Confirm a "Needs Review" transaction (sets needs_review = 0).
  Future<void> confirmExpense(int id) async {
    final db = await database;
    await db.update(
      'expenses',
      {'needs_review': 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Delete a "Needs Review" transaction (user rejected it).
  Future<void> deleteExpense(int id) async {
    final db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: [id]);
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
    final start = DateTime(month.year, month.month, 1).millisecondsSinceEpoch;
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59)
        .millisecondsSinceEpoch;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM expenses WHERE date >= ? AND date <= ? AND needs_review = 0',
      [start, end],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  /// Category breakdown for the current month.
  Future<Map<String, double>> getCategoryBreakdown(DateTime month) async {
    final db = await database;
    final start = DateTime(month.year, month.month, 1).millisecondsSinceEpoch;
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59)
        .millisecondsSinceEpoch;
    final rows = await db.rawQuery(
      'SELECT category, SUM(amount) as total FROM expenses WHERE date >= ? AND date <= ? AND needs_review = 0 GROUP BY category ORDER BY total DESC',
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

  /// Delete all piggy_bank entries in a date range (for recalculation).
  Future<int> deleteSavingsBetween(DateTime start, DateTime end) async {
    final db = await database;
    return db.delete(
      'piggy_bank',
      where: 'date >= ? AND date < ?',
      whereArgs: [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
  }

  Future<double> getTotalSavings() async {
    final db = await database;
    final result =
        await db.rawQuery('SELECT SUM(amount) as total FROM piggy_bank');
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<int> getSavingsCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM piggy_bank');
    return (result.first['cnt'] as int?) ?? 0;
  }

  Future<double> getSavingsBetween(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(amount) as total FROM piggy_bank WHERE date >= ? AND date < ?',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return (result.first['total'] as num?)?.toDouble() ?? 0.0;
  }

  Future<int> getSavingsCountBetween(
    DateTime start,
    DateTime end,
  ) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as cnt FROM piggy_bank WHERE date >= ? AND date < ?',
      [start.millisecondsSinceEpoch, end.millisecondsSinceEpoch],
    );
    return (result.first['cnt'] as int?) ?? 0;
  }

  // ── Monthly Savings ─────────────────────────────────────────────────────────

  /// Insert or update the monthly savings record for the given month key.
  Future<void> insertOrUpdateMonthlySavings(MonthlySavings entry) async {
    final db = await database;
    await db.insert(
      'monthly_savings',
      entry.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Get the monthly savings record for a specific month ('YYYY-MM').
  Future<MonthlySavings?> getMonthlySavingsForMonth(String monthKey) async {
    final db = await database;
    final rows = await db.query(
      'monthly_savings',
      where: 'month = ?',
      whereArgs: [monthKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return MonthlySavings.fromMap(rows.first);
  }

  /// Get all monthly savings history, newest first.
  Future<List<MonthlySavings>> getMonthlySavingsHistory() async {
    final db = await database;
    final rows = await db.query(
      'monthly_savings',
      orderBy: 'month DESC',
    );
    return rows.map(MonthlySavings.fromMap).toList();
  }

  // ── Piggy Settings ──────────────────────────────────────────────────────────

  /// Get the current piggy bank saving settings.
  Future<Map<String, dynamic>> getPiggySettings() async {
    final db = await database;
    final rows = await db.query('piggy_settings', where: 'id = 1');
    if (rows.isEmpty) {
      return {'mode': 'roundoff', 'percentage': 5.0, 'fixed_amount': 10.0};
    }
    return rows.first;
  }

  /// Update piggy bank saving settings.
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
}
