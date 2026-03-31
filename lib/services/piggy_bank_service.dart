import 'dart:async';
import '../database/local_database.dart';
import '../models/expense_model.dart';
import '../models/goal_model.dart';

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

  // Keep savingsRate for backward compat (percent as 0–1 fraction)
  double get savingsRate => _percentage / 100.0;

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

  /// Change savings rate as a fraction (0.0–0.50). Kept for compatibility.
  void setSavingsRate(double rate) {
    _percentage = (rate.clamp(0.0, 0.50) * 100);
  }

  /// Calculate and record saving for a new expense transaction.
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

    // Auto-fund active goals
    final activeGoals = await LocalDatabase.instance.getAllGoals();
    double remaining = saved;
    for (var goal in activeGoals) {
      if (goal.status == 'Active' && remaining > 0) {
        double needed = goal.targetAmount - goal.savedAmount;
        double allocate = 0;
        
        if (remaining >= needed) {
          allocate = needed;
          goal.savedAmount = goal.targetAmount;
          goal.status = 'Completed';
          remaining -= needed;
        } else {
          allocate = remaining;
          goal.savedAmount += remaining;
          remaining = 0;
        }
        
        await LocalDatabase.instance.updateGoal(goal);
        
        // Deduct from Piggy Bank the allocated amount
        if (allocate > 0) {
          await LocalDatabase.instance.insertSavings(PiggyBankEntry(
            amount: -allocate,
            date: DateTime.now(),
          ));
        }
      }
    }

    final total = await getTotalSavings();
    _savingsController.add(total);
    return saved;
  }

  /// Alias kept for backward compatibility.
  Future<double> recordSavings({
    required double expenseAmount,
    required int expenseId,
  }) => recordSaving(expenseAmount: expenseAmount, expenseId: expenseId);

  /// Calculate saving based on current mode.
  double _calculateSaving(double amount) {
    switch (_mode) {
      case SavingMode.roundoff:
        double roundoff = (amount / 10).ceil() * 10 - amount;
        return roundoff <= 0 ? 10.0 : double.parse(roundoff.toStringAsFixed(2));
      case SavingMode.fixed:
        return _fixedAmount;
      case SavingMode.percent:
        return amount * _percentage / 100;
    }
  }

  /// Recalculate all piggy bank entries for the current month.
  Future<void> recalculateCurrentMonth() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 1);
    final db = LocalDatabase.instance;

    await db.deleteSavingsBetween(startOfMonth, endOfMonth);
    final expenses = await db.getMonthlyExpenses(now);

    for (final expense in expenses) {
      final saved = _calculateSaving(expense.amount);
      if (saved <= 0) continue;
      await db.insertSavings(PiggyBankEntry(
        amount: saved,
        date: expense.date,
        expenseId: expense.id ?? 0,
      ));
    }

    final total = await getMonthlySavings();
    _savingsController.add(total);
  }

  Future<double> getTotalSavings() => LocalDatabase.instance.getTotalSavings();
  Future<int> getSavingsCount() => LocalDatabase.instance.getSavingsCount();

  /// Get savings for the current month only.
  Future<double> getMonthlySavings() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    return LocalDatabase.instance.getSavingsBetween(start, end);
  }

  /// Get savings count for the current month.
  Future<int> getMonthlySavingsCount() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    return LocalDatabase.instance.getSavingsCountBetween(start, end);
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
