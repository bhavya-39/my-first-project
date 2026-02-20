import 'dart:async';
import '../database/local_database.dart';
import '../models/expense_model.dart';

/// Manages micro-savings: a configurable percentage of each UPI expense
/// is automatically moved to a virtual "piggy bank".
class PiggyBankService {
  PiggyBankService._();
  static final PiggyBankService instance = PiggyBankService._();

  /// Default savings rate exposed as a constant for the background isolate.
  static const double defaultRate = 0.05; // 5%

  double _savingsRate = defaultRate;
  double get savingsRate => _savingsRate;

  final _savingsController = StreamController<double>.broadcast();
  Stream<double> get savingsStream => _savingsController.stream;

  /// Change the savings rate (0.0 – 0.50) and persist.
  void setSavingsRate(double rate) {
    _savingsRate = rate.clamp(0.0, 0.50);
  }

  /// Record a savings entry and push updated total to stream.
  Future<double> recordSavings({
    required double expenseAmount,
    required int expenseId,
  }) async {
    final saving = expenseAmount * _savingsRate;
    if (saving <= 0) return 0;

    await LocalDatabase.instance.insertSavings(PiggyBankEntry(
      amount: saving,
      date: DateTime.now(),
      expenseId: expenseId,
    ));

    final total = await LocalDatabase.instance.getTotalSavings();
    _savingsController.add(total);
    return saving;
  }

  /// Fetch total savings from SQLite.
  Future<double> getTotalSavings() =>
      LocalDatabase.instance.getTotalSavings();

  Future<int> getSavingsCount() =>
      LocalDatabase.instance.getSavingsCount();

  void dispose() => _savingsController.close();
}
