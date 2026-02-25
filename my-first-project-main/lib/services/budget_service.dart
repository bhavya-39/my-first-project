import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BudgetService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _userId => _auth.currentUser!.uid;

  DocumentReference get _budgetDoc =>
      _firestore.collection('users').doc(_userId).collection('settings').doc('budget');

  /// Save or update the monthly budget limit
  Future<void> setBudget(double amount) async {
    await _budgetDoc.set({
      'amount': amount,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream of the current monthly budget (null if not set)
  Stream<double?> getBudgetStream() {
    return _budgetDoc.snapshots().map((doc) {
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return null;
      return (data['amount'] as num?)?.toDouble();
    });
  }

  /// One-time fetch of current budget
  Future<double?> getBudget() async {
    final doc = await _budgetDoc.get();
    if (!doc.exists) return null;
    final data = doc.data() as Map<String, dynamic>?;
    return (data?['amount'] as num?)?.toDouble();
  }
}
