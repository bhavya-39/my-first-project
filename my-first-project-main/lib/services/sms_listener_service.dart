import 'package:flutter/foundation.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import '../database/local_database.dart';
import 'sms_parser_service.dart';
import 'piggy_bank_service.dart';
import 'expense_repository.dart';

/// Manages SMS inbox synchronization.
///
/// Reads SMS → extracts UPI expenses → saves expense → triggers piggy saving
class SmsListenerService {
  SmsListenerService._();
  static final SmsListenerService instance = SmsListenerService._();

  final _parser = const SmsParserService();
  ExpenseRepository? _repository;

  void init(ExpenseRepository repository) => _repository = repository;

  // ── Permissions ─────────────────────────────────────────

  Future<bool> requestPermissions() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;

    final smsStatus = await Permission.sms.request();
    if (smsStatus.isGranted) {
      await Permission.notification.request();
    }
    return smsStatus.isGranted;
  }

  // ── Inbox Sync ──────────────────────────────────────────

  /// Reads SMS inbox and saves new UPI expenses + piggy savings
  Future<int> syncInbox() async {
    if (defaultTargetPlatform != TargetPlatform.android) return 0;

    final granted = await Permission.sms.isGranted;
    if (!granted) return 0;

    try {
      final query = SmsQuery();
      final messages = await query.querySms(
        kinds: [SmsQueryKind.inbox],
      );

      final db = LocalDatabase.instance;
      int count = 0;

      for (final msg in messages) {
        final body = msg.body ?? '';
        final sender = msg.sender ?? '';
        final ts = msg.dateSent ?? DateTime.now();

        final parsed = _parser.parse(body, sender, ts);
        if (parsed == null) continue;

        // Skip if already saved
        if (await db.hashExists(parsed.hash)) continue;

        // ✅ STEP 1: Save expense
        final id = await db.insertExpense(parsed.toExpense());

        if (id > 0) {
          // ✅ STEP 2: Calculate & save piggy bank amount (based on user's mode)
          await PiggyBankService.instance.recordSaving(
            expenseAmount: parsed.amount,
            expenseId: id,
          );
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
