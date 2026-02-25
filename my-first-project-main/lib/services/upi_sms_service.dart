import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/transaction_model.dart';

/// Rule-based UPI transaction SMS parser.
/// Reads device SMS inbox, filters UPI-related messages,
/// extracts transaction details and stores them in Firestore.
class UpiSmsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String get _userId => _auth.currentUser!.uid;

  // ── Regex patterns ──────────────────────────────────────────────────────────
  static final _upiKeywords = RegExp(
    r'\b(UPI|IMPS|NEFT|RTGS|PhonePe|GPay|Google Pay|Paytm|BharatPe|Razorpay|'
    r'debited|credited|sent|received|transferred|payment|txn|transaction)\b',
    caseSensitive: false,
  );

  static final _amountRegex = RegExp(
    r'(?:Rs\.?|INR|₹)\s*(\d+(?:[,\d]*)?(?:\.\d{1,2})?)',
    caseSensitive: false,
  );

  static final _debitKeywords = RegExp(
    r'\b(debited|sent|paid|deducted|withdrawn|payment of|transferred to)\b',
    caseSensitive: false,
  );

  static final _creditKeywords = RegExp(
    r'\b(credited|received|added|deposited|refunded|cashback)\b',
    caseSensitive: false,
  );

  // Merchant extraction patterns
  static final _merchantPatterns = [
    RegExp(r'to\s+([A-Za-z0-9 &@._-]{2,40}?)(?:\s+(?:on|via|at|UPI|Ref|VPA|-)|\.|$)', caseSensitive: false),
    RegExp(r'at\s+([A-Za-z0-9 &@._-]{2,40}?)(?:\s+(?:on|via|at|using)|\.|$)', caseSensitive: false),
    RegExp(r'from\s+([A-Za-z0-9 &@._-]{2,40}?)(?:\s+(?:on|via|credited|to)|\.|$)', caseSensitive: false),
    RegExp(r'by\s+([A-Za-z0-9 &]{2,30})', caseSensitive: false),
  ];

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Request READ_SMS permission. Returns true if granted.
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  /// Fetch SMS inbox, parse UPI messages, store new transactions in Firestore.
  /// Returns the number of new transactions stored.
  Future<int> fetchAndStoreUpiTransactions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return 0;

    final granted = await Permission.sms.isGranted;
    if (!granted) return 0;

    try {
      final SmsQuery query = SmsQuery();
      final messages = await query.querySms(kinds: [SmsQueryKind.inbox]);

      int count = 0;
      for (final msg in messages) {
        final body = msg.body ?? '';
        if (!_isUpiMessage(body)) continue;

        final hash = _messageHash(body, msg.dateSent ?? DateTime.now());
        final exists = await _hashExists(hash);
        if (exists) continue;

        final parsed = _parseMessage(body, msg.dateSent ?? DateTime.now());
        if (parsed == null) continue;

        await _saveTransaction(parsed, hash);
        count++;
      }
      return count;
    } catch (e) {
      debugPrint('UpiSmsService error: $e');
      return 0;
    }
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  bool _isUpiMessage(String body) => _upiKeywords.hasMatch(body);

  String _messageHash(String body, DateTime date) {
    final raw = '${body.trim()}|${date.millisecondsSinceEpoch}';
    return md5.convert(utf8.encode(raw)).toString();
  }

  Future<bool> _hashExists(String hash) async {
    final query = await _firestore
        .collection('users')
        .doc(_userId)
        .collection('transactions')
        .where('sourceMessageHash', isEqualTo: hash)
        .limit(1)
        .get();
    return query.docs.isNotEmpty;
  }

  _ParsedTransaction? _parseMessage(String body, DateTime date) {
    // Amount
    final amountMatch = _amountRegex.firstMatch(body);
    if (amountMatch == null) return null;
    final amountStr = amountMatch.group(1)!.replaceAll(',', '');
    final amount = double.tryParse(amountStr);
    if (amount == null || amount <= 0) return null;

    // Transaction type
    final isDebit = _debitKeywords.hasMatch(body);
    final isCredit = _creditKeywords.hasMatch(body);
    if (!isDebit && !isCredit) return null;
    final type = isDebit ? TransactionType.expense : TransactionType.income;

    // Merchant / title
    String title = 'UPI Transaction';
    for (final pattern in _merchantPatterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final candidate = match.group(1)?.trim() ?? '';
        if (candidate.length > 2 && candidate.length <= 40) {
          title = _cleanMerchant(candidate);
          break;
        }
      }
    }

    // Category
    final category = _inferCategory(body, type);

    return _ParsedTransaction(
      title: title,
      amount: amount,
      date: date,
      type: type,
      category: category,
    );
  }

  String _cleanMerchant(String raw) {
    // Remove trailing noise words
    return raw
        .replaceAll(RegExp(r'\s+(UPI|VPA|Ref|A/C|AC|using|via).*', caseSensitive: false), '')
        .trim();
  }

  String _inferCategory(String body, TransactionType type) {
    final lower = body.toLowerCase();
    if (lower.contains('zomato') || lower.contains('swiggy') || lower.contains('food')) {
      return 'Food';
    }
    if (lower.contains('amazon') || lower.contains('flipkart') || lower.contains('myntra') || lower.contains('shopping')) {
      return 'Shopping';
    }
    if (lower.contains('uber') || lower.contains('ola') || lower.contains('metro') || lower.contains('bus')) {
      return 'Transport';
    }
    if (lower.contains('electricity') || lower.contains('water') || lower.contains('gas') || lower.contains('broadband')) {
      return 'Utilities';
    }
    if (lower.contains('netflix') || lower.contains('spotify') || lower.contains('prime') || lower.contains('hotstar')) {
      return 'Entertainment';
    }
    if (lower.contains('hospital') || lower.contains('pharmacy') || lower.contains('medical') || lower.contains('doctor')) {
      return 'Health';
    }
    if (lower.contains('rent') || lower.contains('loan') || lower.contains('emi')) {
      return 'Housing';
    }
    if (lower.contains('salary') || lower.contains('stipend')) {
      return 'Salary';
    }
    return type == TransactionType.expense ? 'UPI Expense' : 'UPI Income';
  }

  Future<void> _saveTransaction(_ParsedTransaction parsed, String hash) async {
    await _firestore
        .collection('users')
        .doc(_userId)
        .collection('transactions')
        .add({
      'userId': _userId,
      'title': parsed.title,
      'amount': parsed.amount,
      'date': Timestamp.fromDate(parsed.date),
      'type': parsed.type.name,
      'category': parsed.category,
      'note': 'Auto-imported from UPI SMS',
      'sourceMessageHash': hash,
    });
  }
}

class _ParsedTransaction {
  final String title;
  final double amount;
  final DateTime date;
  final TransactionType type;
  final String category;

  const _ParsedTransaction({
    required this.title,
    required this.amount,
    required this.date,
    required this.type,
    required this.category,
  });
}
