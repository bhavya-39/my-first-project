import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import '../database/local_database.dart';
import '../models/expense_model.dart';
import 'sms_parser_service.dart';
import 'piggy_bank_service.dart';
import 'expense_repository.dart';

/// Manages SMS inbox synchronization.
///
/// On Android, reads the SMS inbox via [flutter_sms_inbox] and processes
/// only debit / UPI payment messages through [SmsParserService].
/// Real-time detection is handled by a [workmanager] periodic task (every
/// 15 min) via [NotificationService].
class SmsListenerService {
  SmsListenerService._();
  static final SmsListenerService instance = SmsListenerService._();

  final _parser = const SmsParserService();
  ExpenseRepository? _repository;

  void init(ExpenseRepository repository) => _repository = repository;

  // ── Debit-only pre-filter ───────────────────────────────────────────────────
  // Must contain at least one debit keyword (credit keywords excluded).
  static final _quickFilter = RegExp(
    r'\b(debit(?:ed)?|spent|paid|payment|purchase(?:d)?|charged|'
    r'withdrawn|deducted|sent|pos|mandate|auto.?pay|emi|'
    r'neft|imps|rtgs|upi|txn|transaction)\b',
    caseSensitive: false,
  );

  // ── Credit-reject filter ──────────────────────────────────────────────
  // Blocks credit, OTP, promo, loan, and reward messages.
  static final _creditRejectFilter = RegExp(
    r'\b(credit(?:ed)?|received|refund(?:ed)?|cashback|cash\s*back|'
    r'salary|income|reward|interest\s+credited|neft\s+cr|imps\s+cr|'
    r'reversed?\s+to|deposited|otp|one.?time\s+password|never\s+share|'
    r'loan\s+offer|insurance|promo|offer|discount|earn\s+rewards|'
    r'win|congratul|click\s+here|failed|declined|blocked|'
    r'insufficient\s+funds|kyc|lucky\s+draw|pre.?approv)\b',
    caseSensitive: false,
  );

  // ── Permissions ────────────────────────────────────────────────────────────

  Future<bool> requestPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    final smsStatus = await Permission.sms.request();
    if (smsStatus.isGranted) await Permission.notification.request();
    return smsStatus.isGranted;
  }

  Future<bool> hasPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return Permission.sms.isGranted;
  }

  // ── Inbox sync ─────────────────────────────────────────────────────────────

  /// Reads the full SMS inbox, filters UPI debits, inserts new entries.
  /// Returns the count of newly added transactions.
  Future<int> syncInbox() async {
    if (defaultTargetPlatform != TargetPlatform.android) return 0;
    final granted = await Permission.sms.isGranted;
    if (!granted) return 0;

    try {
      final query = SmsQuery();
      final messages = await query.querySms(kinds: [SmsQueryKind.inbox]);
      final db = LocalDatabase.instance;
      int count = 0;

      for (final msg in messages) {
        final body = msg.body ?? '';
        final sender = msg.sender ?? '';
        final ts = msg.dateSent ?? DateTime.now();

        // ── Pre-filter 1: debit keyword required ────────────────────────
        if (!_quickFilter.hasMatch(body)) continue;

        // ── Pre-filter 2: reject credit / promo messages ────────────────
        if (_creditRejectFilter.hasMatch(body)) continue;

        // ── Raw SMS dedup: skip if this exact SMS was already processed ───
        // Uses body+timestamp hash, independent of the parsed expense hash.
        final bodyHash = _computeBodyHash(body, ts);
        if (await db.smsHashExists(bodyHash)) continue;

        // ── Full parse ──────────────────────────────────────────────
        final parsed = _parser.parse(body, sender, ts);
        if (parsed == null) continue;

        // ── Expense-level dedup (exact hash AND fuzzy duplicates) ───────
        if (await db.hashExists(parsed.hash) ||
            await db.isDuplicateExpense(amount: parsed.amount, date: ts)) {
          // Still record the raw SMS hash so we skip it next time.
          await db.insertSmsHash(bodyHash, ts);
          continue;
        }

        final id = await db.insertExpense(parsed.toExpense());
        if (id > 0) {
          // Record raw SMS hash to prevent reprocessing.
          await db.insertSmsHash(bodyHash, ts);

          final savings = PiggyBankService.instance.savingsRate * parsed.amount;
          if (savings > 0) {
            await db.insertSavings(PiggyBankEntry(
              amount: savings,
              date: DateTime.now(),
              expenseId: id,
            ));
          }
          count++;
        }
      }

      if (count > 0) _repository?.refresh();
      return count;
    } catch (e) {
      debugPrint('SmsListenerService.syncInbox error: $e');
      return 0;
    }
  }

  // ── Raw SMS body hash ─────────────────────────────────────────────────
  String _computeBodyHash(String body, DateTime date) {
    final raw = '${body.trim()}|${date.millisecondsSinceEpoch}';
    return md5.convert(utf8.encode(raw)).toString();
  }
}
