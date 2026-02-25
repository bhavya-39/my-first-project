import 'package:cloud_firestore/cloud_firestore.dart';

enum TransactionType { expense, income }

class TransactionModel {
  final String id;
  final String userId;
  final String title;
  final double amount;
  final DateTime date;
  final TransactionType type;
  final String category;
  final String? note;

  const TransactionModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.amount,
    required this.date,
    required this.type,
    required this.category,
    this.note,
  });

  /// Create a TransactionModel from a Firestore document
  factory TransactionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TransactionModel(
      id: doc.id,
      userId: data['userId'] as String,
      title: data['title'] as String,
      amount: (data['amount'] as num).toDouble(),
      date: (data['date'] as Timestamp).toDate(),
      type: TransactionType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => TransactionType.expense,
      ),
      category: data['category'] as String,
      note: data['note'] as String?,
    );
  }

  /// Convert to a map for writing to Firestore
  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'title': title,
      'amount': amount,
      'date': Timestamp.fromDate(date),
      'type': type.name,
      'category': category,
      'note': note,
    };
  }
}
