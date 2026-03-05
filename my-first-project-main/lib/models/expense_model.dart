/// Local expense model — stored in SQLite, not tied to Firestore.
class Expense {
  final int? id;
  final String hash;
  final double amount;
  final String merchant;
  final String category;
  final String? bank;
  final DateTime date;
  final String? note;
  final bool needsReview;
  final int confidence; // 0–100
  final bool synced;

  const Expense({
    this.id,
    required this.hash,
    required this.amount,
    required this.merchant,
    required this.category,
    this.bank,
    required this.date,
    this.note,
    this.needsReview = false,
    this.confidence = 100,
    this.synced = false,
  });

  Map<String, dynamic> toMap() => {
        'hash': hash,
        'amount': amount,
        'merchant': merchant,
        'category': category,
        'bank': bank,
        'date': date.millisecondsSinceEpoch,
        'note': note,
        'needs_review': needsReview ? 1 : 0,
        'confidence': confidence,
        'synced': synced ? 1 : 0,
      };

  factory Expense.fromMap(Map<String, dynamic> m) => Expense(
        id: m['id'] as int?,
        hash: m['hash'] as String,
        amount: (m['amount'] as num).toDouble(),
        merchant: m['merchant'] as String,
        category: m['category'] as String,
        bank: m['bank'] as String?,
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        note: m['note'] as String?,
        needsReview: (m['needs_review'] as int) == 1,
        confidence: m['confidence'] as int,
        synced: (m['synced'] as int) == 1,
      );

  Expense copyWith({bool? needsReview, bool? synced}) => Expense(
        id: id,
        hash: hash,
        amount: amount,
        merchant: merchant,
        category: category,
        bank: bank,
        date: date,
        note: note,
        needsReview: needsReview ?? this.needsReview,
        confidence: confidence,
        synced: synced ?? this.synced,
      );
}

class PiggyBankEntry {
  final int? id;
  final double amount;
  final DateTime date;
  final int? expenseId;

  const PiggyBankEntry({
    this.id,
    required this.amount,
    required this.date,
    this.expenseId,
  });

  Map<String, dynamic> toMap() => {
        'amount': amount,
        'date': date.millisecondsSinceEpoch,
        'expense_id': expenseId,
      };

  factory PiggyBankEntry.fromMap(Map<String, dynamic> m) => PiggyBankEntry(
        id: m['id'] as int?,
        amount: (m['amount'] as num).toDouble(),
        date: DateTime.fromMillisecondsSinceEpoch(m['date'] as int),
        expenseId: m['expense_id'] as int?,
      );
}

/// Monthly savings record — stored in SQLite `monthly_savings` table.
class MonthlySavings {
  final int? id;
  final String month; // 'YYYY-MM' format
  final double totalExpenses;
  final double budget;
  final double savings; // budget - totalExpenses

  const MonthlySavings({
    this.id,
    required this.month,
    required this.totalExpenses,
    required this.budget,
    required this.savings,
  });

  Map<String, dynamic> toMap() => {
        'month': month,
        'total_expenses': totalExpenses,
        'budget': budget,
        'savings': savings,
      };

  factory MonthlySavings.fromMap(Map<String, dynamic> m) => MonthlySavings(
        id: m['id'] as int?,
        month: m['month'] as String,
        totalExpenses: (m['total_expenses'] as num).toDouble(),
        budget: (m['budget'] as num).toDouble(),
        savings: (m['savings'] as num).toDouble(),
      );
}
