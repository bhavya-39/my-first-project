import 'dart:async';
import '../database/local_database.dart';
import '../models/expense_model.dart';

/// Unified data repository — SQLite is the source of truth.
/// Exposes reactive streams by polling on refresh calls.
class ExpenseRepository {
  ExpenseRepository._();
  static final ExpenseRepository instance = ExpenseRepository._();

  final _expensesController =
      StreamController<List<Expense>>.broadcast();
  final _categoryController =
      StreamController<Map<String, double>>.broadcast();
  final _totalController = StreamController<double>.broadcast();
  final _reviewController = StreamController<List<Expense>>.broadcast();

  Stream<List<Expense>> get expensesStream => _expensesController.stream;
  Stream<Map<String, double>> get categoryStream => _categoryController.stream;
  Stream<double> get totalStream => _totalController.stream;
  Stream<List<Expense>> get reviewStream => _reviewController.stream;

  final LocalDatabase _db = LocalDatabase.instance;

  /// Trigger a full reload from SQLite and push to all streams.
  Future<void> refresh() async {
    final now = DateTime.now();
    final expenses = await _db.getMonthlyExpenses(now);
    final breakdown = await _db.getCategoryBreakdown(now);
    final total = await _db.getMonthlyTotal(now);
    final review = await _db.getPendingReview();

    _expensesController.add(expenses);
    _categoryController.add(breakdown);
    _totalController.add(total);
    _reviewController.add(review);
  }

  // ── One-shot getters ───────────────────────────────────────────────────────

  Future<List<Expense>> getMonthlyExpenses() =>
      _db.getMonthlyExpenses(DateTime.now());

  Future<double> getTotalSpent() => _db.getMonthlyTotal(DateTime.now());

  Future<Map<String, double>> getCategoryBreakdown() =>
      _db.getCategoryBreakdown(DateTime.now());

  Future<List<Expense>> getPendingReview() => _db.getPendingReview();

  // ── Review workflow ────────────────────────────────────────────────────────

  Future<void> confirmExpense(int id) async {
    await _db.confirmExpense(id);
    await refresh();
  }

  Future<void> rejectExpense(int id) async {
    await _db.deleteExpense(id);
    await refresh();
  }

  void dispose() {
    _expensesController.close();
    _categoryController.close();
    _totalController.close();
    _reviewController.close();
  }
}
