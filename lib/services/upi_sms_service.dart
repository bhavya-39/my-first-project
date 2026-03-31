import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'sms_parser_service.dart';

/// Reads the device SMS inbox, delegates parsing to [SmsParserService], and
/// stores transactions (both debit expenses and credit income) in Firestore.
class UpiSmsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final _parser = const SmsParserService();

  String get _userId => _auth.currentUser!.uid;

  // ── Pre-filter: debit keyword check — only student-relevant debit messages ────
  // Accept a message only when it contains a debit-related keyword.
  // Credit/refund/promotional keywords are intentionally excluded here so those
  // messages are discarded before the full parser is even invoked.
  static final _quickFilter = RegExp(
    r'\b(debit(?:ed)?|spent|paid|payment|purchase(?:d)?|charged|'
    r'withdrawn|deducted|sent|pos|mandate|auto.?pay|emi|'
    r'neft|imps|rtgs|upi|txn|transaction)\b',
    caseSensitive: false,
  );

  // ── Credit-reject filter — blocks messages even if a debit word slips through ─
  // Catches reversal confirmations, salary credits, cashback, rewards, etc.
  static final _creditRejectFilter = RegExp(
    r'\b(credit(?:ed)?|received|refund(?:ed)?|cashback|cash\s*back|'
    r'salary|income|reward|interest\s+credited|neft\s+cr|imps\s+cr|'
    r'reversed?\s+to|deposited|otp|one.?time\s+password|never\s+share|'
    r'loan\s+offer|insurance|promo|offer|discount|earn\s+rewards|'
    r'win|congratul|click\s+here|failed|declined|blocked|'
    r'insufficient\s+funds|kyc|lucky\s+draw|pre.?approv)\b',
    caseSensitive: false,
  );

  // ── Trusted sender pre-check (DLT headers used by Indian banks/fintechs) ─────
  static final _trustedSenderPattern = RegExp(
    r'HDFC|ICICI|SBI|AXIS|KOTAK|YESBNK|PNB|CANARA|BOI|BOB|IOB|UNION|'
    r'INDIAN|IDBI|UCO|CBI|IDFC|FEDERAL|RBL|KVB|PAYTM|GPAY|PHONE|AMAZON|'
    r'BHARATPE|BHIM|CRED|MOBIKWIK|FREECHARGE|JUPITER|NIYO|SLICE|'
    r'STATE\s*BANK|OVERSEAS|PUNJAB|BANK\s*OF',
    caseSensitive: false,
  );

  // ── Public API ───────────────────────────────────────────────────────────────

  /// Request READ_SMS permission. Returns true if granted.
  Future<bool> requestPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final status = await Permission.sms.request();
    return status.isGranted;
  }

  /// Fetch SMS inbox, parse UPI/bank messages, store new transactions.
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
        final sender = msg.sender ?? '';
        final ts = msg.dateSent ?? DateTime.now();

        // ── Pre-filter 1: sender whitelist ─────────────────────────────
        // Skip if sender is clearly not a bank/fintech AND the body has no
        // debit keyword — avoids parsing every OTP / spam message.
        final senderTrusted =
            _trustedSenderPattern.hasMatch(sender.replaceAll('-', ''));
        if (!senderTrusted && !_quickFilter.hasMatch(body)) continue;

        // ── Pre-filter 2: must have a debit keyword ─────────────────────
        if (!_quickFilter.hasMatch(body)) continue;

        // ── Pre-filter 3: reject credit / promo messages immediately ─────
        // This is a safety net on top of SmsParserService's own checks.
        if (_creditRejectFilter.hasMatch(body)) continue;

        // ── Full parse ──────────────────────────────────────────────────
        final parsed = _parser.parse(body, sender, ts);
        if (parsed == null) continue;

        final hash = _messageHash(body, ts);
        final exists = await _hashExists(hash);
        if (exists) continue;

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

  String _messageHash(String body, DateTime date) {
    final raw = '${body.trim()}|${date.millisecondsSinceEpoch}';
    return md5.convert(utf8.encode(raw)).toString();
  }

  Future<bool> _hashExists(String hash) async {
    final q = await _firestore
        .collection('users')
        .doc(_userId)
        .collection('transactions')
        .where('sourceMessageHash', isEqualTo: hash)
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  Future<void> _saveTransaction(ParsedExpense parsed, String hash) async {
    await _firestore
        .collection('users')
        .doc(_userId)
        .collection('transactions')
        .add({
      'userId': _userId,
      'title': parsed.merchant,
      'amount': parsed.amount,
      'date': DateTime.now(),
      'type': 'expense',
      'category': parsed.category,
      'bank': parsed.bank,
      'confidence': parsed.confidence,
      'note': 'Auto-imported from SMS',
      'sourceMessageHash': hash,
    });
  }
}
