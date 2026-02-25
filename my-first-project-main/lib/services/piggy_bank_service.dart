import 'dart:async';
import '../database/local_database.dart';
import '../models/expense_model.dart';

/// Saving mode enum
enum SavingMode { roundoff, fixed, percent }

/// Multi-mode Piggy Bank Service
/// Supports: Round-off, Fixed amount, and Percentage saving per transaction.
class PiggyBankService {
  PiggyBankService._();
  static final PiggyBankService instance = PiggyBankService._();

  final _savingsController = StreamController<double>.broadcast();
  Stream<double> get savingsStream => _savingsController.stream;

  /// Current settings (loaded from DB)
  SavingMode _mode = SavingMode.roundoff;
  double _percentage = 5.0;
  double _fixedAmount = 10.0;

  SavingMode get mode => _mode;
  double get percentage => _percentage;
  double get fixedAmount => _fixedAmount;

  /// Load settings from database. Call once at startup.
  Future<void> loadSettings() async {
    final settings = await LocalDatabase.instance.getPiggySettings();
    _mode = _parseMode(settings['mode'] as String? ?? 'roundoff');
    _percentage = (settings['percentage'] as num?)?.toDouble() ?? 5.0;
    _fixedAmount = (settings['fixed_amount'] as num?)?.toDouble() ?? 10.0;
  }

  /// Update saving mode and persist to database.
  Future<void> updateSettings({
    required SavingMode mode,
    double? percentage,
    double? fixedAmount,
  }) async {
    _mode = mode;
    if (percentage != null) _percentage = percentage;
    if (fixedAmount != null) _fixedAmount = fixedAmount;

    await LocalDatabase.instance.updatePiggySettings(
      mode: _modeToString(mode),
      percentage: _percentage,
      fixedAmount: _fixedAmount,
    );
  }

  /// Calculate and record saving for a new expense transaction.
  /// Called automatically from SMS listener when a new UPI debit is detected.
  Future<double> recordSaving({
    required double expenseAmount,
    required int expenseId,
  }) async {
    final saved = _calculateSaving(expenseAmount);
    if (saved <= 0) return 0;

    await LocalDatabase.instance.insertSavings(PiggyBankEntry(
      amount: saved,
      date: DateTime.now(),
      expenseId: expenseId,
    ));

    final total = await getTotalSavings();
    _savingsController.add(total);
    return saved;
  }

  /// Calculate saving based on current mode.
  double _calculateSaving(double amount) {
    switch (_mode) {
      case SavingMode.roundoff:
        // Round up to nearest ₹10 and save the difference
        return (amount / 10).ceil() * 10 - amount;
      case SavingMode.fixed:
        // Fixed amount per transaction
        return _fixedAmount;
      case SavingMode.percent:
        // Percentage of transaction (rounded to nearest rupee)
        return (amount * _percentage / 100).roundToDouble();
    }
  }

  /// Recalculate all piggy bank entries for the current month
  /// using the active saving mode. Call after mode/percentage changes.
  Future<void> recalculateCurrentMonth() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1);
    final db = LocalDatabase.instance;

    // 1. Delete all piggy_bank entries for this month
    await db.deleteSavingsBetween(startOfMonth, endOfMonth);

    // 2. Fetch all expenses for this month
    final expenses = await db.getMonthlyExpenses(now);

    // 3. Recompute and insert savings for each expense
    for (final expense in expenses) {
      final saved = _calculateSaving(expense.amount);
      if (saved <= 0) continue;
      await db.insertSavings(PiggyBankEntry(
        amount: saved,
        date: expense.date,
        expenseId: expense.id ?? 0,
      ));
    }

    // 4. Notify listeners
    final total = await getMonthlySavings();
    _savingsController.add(total);
  }

  /// Get total piggy bank savings (all time).
  Future<double> getTotalSavings() => LocalDatabase.instance.getTotalSavings();

  /// Get total number of savings entries.
  Future<int> getSavingsCount() => LocalDatabase.instance.getSavingsCount();

  /// Get savings for the current month only.
  Future<double> getMonthlySavings() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1);
    return LocalDatabase.instance.getSavingsBetween(startOfMonth, endOfMonth);
  }

  /// Get savings count for the current month.
  Future<int> getMonthlySavingsCount() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1);
    return LocalDatabase.instance
        .getSavingsCountBetween(startOfMonth, endOfMonth);
  }

  SavingMode _parseMode(String mode) {
    switch (mode) {
      case 'fixed':
        return SavingMode.fixed;
      case 'percent':
        return SavingMode.percent;
      default:
        return SavingMode.roundoff;
    }
  }

  String _modeToString(SavingMode mode) {
    switch (mode) {
      case SavingMode.roundoff:
        return 'roundoff';
      case SavingMode.fixed:
        return 'fixed';
      case SavingMode.percent:
        return 'percent';
    }
  }

  void dispose() => _savingsController.close();
}
