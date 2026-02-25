import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/transaction_model.dart';

class TransactionService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _userId => _auth.currentUser!.uid;

  /// Add a new transaction
  Future<void> addTransaction({
    required String title,
    required double amount,
    required TransactionType type,
    required String category,
    DateTime? date,
    String? note,
  }) async {
    final transaction = TransactionModel(
      id: '', // Firestore will generate this
      userId: _userId,
      title: title,
      amount: amount,
      date: date ?? DateTime.now(),
      type: type,
      category: category,
      note: note,
    );

    // Save to Firestore
    await _firestore
        .collection('users')
        .doc(_userId)
        .collection('transactions')
        .add(transaction.toMap());
        
    // Update total balance (optional: simpler to calc on fly for now, or cloud function)
  }

  /// Get a stream of recent transactions
  Stream<List<TransactionModel>> getRecentTransactions({int limit = 5}) {
    return _firestore
        .collection('users')
        .doc(_userId)
        .collection('transactions')
        .orderBy('date', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => TransactionModel.fromFirestore(doc))
          .toList();
    });
  }

  /// Get a stream of all transactions for a specific month
  Stream<List<TransactionModel>> getTransactionsByMonth(DateTime month) {
    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    return _firestore
        .collection('users')
        .doc(_userId)
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => TransactionModel.fromFirestore(doc))
          .toList();
    });
  }

  /// Get a stream of all transactions (for calculating balance)
  Stream<List<TransactionModel>> getBalanceStream() {
    return _firestore
        .collection('users')
        .doc(_userId)
        .collection('transactions')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => TransactionModel.fromFirestore(doc))
          .toList();
    });
  }

  /// Delete a transaction
  Future<void> deleteTransaction(String transactionId) async {
    await _firestore
        .collection('users')
        .doc(_userId)
        .collection('transactions')
        .doc(transactionId)
        .delete();
  }
}
