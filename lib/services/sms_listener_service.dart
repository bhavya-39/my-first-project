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
/// messages through [SmsParserService]. Real-time detection is handled
/// by a [workmanager] periodic task (every 15 min) via [NotificationService].
class SmsListenerService {
  SmsListenerService._();
  static final SmsListenerService instance = SmsListenerService._();

  final _parser = const SmsParserService();
  ExpenseRepository? _repository;

  void init(ExpenseRepository repository) => _repository = repository;

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

        final parsed = _parser.parse(body, sender, ts);
        if (parsed == null) continue;
        if (await db.hashExists(parsed.hash)) continue;

        final id = await db.insertExpense(parsed.toExpense());
        if (id > 0) {
          final savings =
              PiggyBankService.instance.savingsRate * parsed.amount;
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
}
