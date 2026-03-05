import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:notification_listener_service/notification_listener_service.dart';
import 'package:notification_listener_service/notification_event.dart';

import '../database/local_database.dart';
import '../models/expense_model.dart';
import 'expense_repository.dart';
import 'piggy_bank_service.dart';
import 'sms_parser_service.dart';

/// Real-time UPI expense detector via Android NotificationListenerService.
///
/// Listens to push notifications from known UPI apps, parses the notification
/// body using the same [SmsParserService] rules used for SMS, deduplicates
/// via [LocalDatabase.hashExists], and stores the result.
///
/// **Permission note**: Android requires the user to grant "Notification Access"
/// in Settings → Apps → Special App Access → Notification Access.
/// Call [requestPermission] to open that settings page.
class UpiNotificationListener {
  UpiNotificationListener._();

  static StreamSubscription<ServiceNotificationEvent>? _subscription;
  static ExpenseRepository? _repository;
  static final _parser = const SmsParserService();

  // ── Known UPI / bank app package names ─────────────────────────────────────
  static const _upiPackages = {
    // Google Pay
    'com.google.android.apps.nbu.paisa.user',
    // PhonePe
    'com.phonepe.app',
    // Paytm
    'net.one97.paytm',
    // Amazon Pay
    'in.amazon.mShop.android.shopping',
    // BHIM (NPCI official)
    'in.org.npci.upiapp',
    // Cred
    'com.dreamplug.androidapp',
    // MobiKwik
    'com.mobikwik_new',
    // FreeCharge
    'com.freecharge.android',
    // WhatsApp Pay (notifications from WA)
    'com.whatsapp',
    // SBI YONO
    'com.sbi.lotusintouch',
    // HDFC MobileBanking
    'com.snapwork.hdfc',
    // ICICI iMobile
    'com.csam.icici.bank.imobile',
    // Axis Mobile
    'com.axis.mobile',
    // Kotak Mobile Banking
    'com.msf.kash',
    // BOB World
    'com.baroda.mpassbook',
    // Slice
    'com.sliceit.app',
    // Jupiter
    'money.jupiter.app',
    // LazyPay
    'com.lazypay.lazypay',
  };

  // ── Public API ──────────────────────────────────────────────────────────────

  /// Check if notification-listener permission is already granted.
  static Future<bool> isPermissionGranted() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return NotificationListenerService.isPermissionGranted();
  }

  /// Open Android's Notification Access settings page.
  /// Returns true once permission is granted (polls until granted or 60s).
  static Future<bool> requestPermission() async {
    if (defaultTargetPlatform != TargetPlatform.android) return false;
    return NotificationListenerService.requestPermission();
  }

  /// Start listening to incoming UPI notifications.
  ///
  /// [repository] is used to trigger a dashboard refresh after each new entry.
  /// Safe to call multiple times — subsequent calls are no-ops.
  static Future<void> startListening(ExpenseRepository repository) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_subscription != null) return; // already listening

    final granted = await isPermissionGranted();
    if (!granted) return; // user hasn't granted access yet — do nothing silently

    _repository = repository;

    _subscription =
        NotificationListenerService.notificationsStream.listen(_onNotification);
    debugPrint('UpiNotificationListener: started');
  }

  /// Stop listening and release resources.
  static void stopListening() {
    _subscription?.cancel();
    _subscription = null;
    _repository = null;
    debugPrint('UpiNotificationListener: stopped');
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  static void _onNotification(ServiceNotificationEvent event) async {
    try {
      // 1. Only process known UPI app packages
      final pkg = event.packageName ?? '';
      if (!_upiPackages.contains(pkg)) return;

      // 2. Build the text body to parse (title + content for maximum signal)
      final title = event.title ?? '';
      final content = event.content ?? '';
      if (content.isEmpty) return;

      final fullText = title.isNotEmpty ? '$title. $content' : content;

      // 3. Parse using the same rule-based parser as SMS
      final parsed = _parser.parse(fullText, null, DateTime.now());
      if (parsed == null) return;

      // 4. Build a stable hash: merchant + amount + minute-level timestamp
      //    (identical to SmsParserService hash so cross-source dedup works)
      final minuteKey =
          '${parsed.timestamp.year}${parsed.timestamp.month}${parsed.timestamp.day}'
          '${parsed.timestamp.hour}${parsed.timestamp.minute}';
      final rawHash = '${parsed.merchant}|${parsed.amount.toStringAsFixed(2)}|$minuteKey';
      final hash = md5.convert(utf8.encode(rawHash)).toString();

      // 5. Deduplicate
      final db = LocalDatabase.instance;
      if (await db.hashExists(hash)) return;

      // 6. Determine bank from package name if parser didn't find one
      final bank = parsed.bank ?? _bankFromPackage(pkg);

      // 7. Store the expense
      final expense = Expense(
        hash: hash,
        amount: parsed.amount,
        merchant: parsed.merchant,
        category: parsed.category,
        bank: bank,
        date: parsed.timestamp,
        note: 'Auto-imported from UPI notification',
        needsReview: parsed.needsReview,
        confidence: parsed.confidence,
      );

      final id = await db.insertExpense(expense);
      if (id <= 0) return; // duplicate or error

      // 8. Piggy bank micro-saving
      final savings =
          PiggyBankService.instance.savingsRate * parsed.amount;
      if (savings > 0) {
        await db.insertSavings(PiggyBankEntry(
          amount: savings,
          date: DateTime.now(),
          expenseId: id,
        ));
      }

      // 9. Refresh the dashboard
      _repository?.refresh();

      debugPrint(
          'UpiNotificationListener: saved ₹${parsed.amount} at ${parsed.merchant} from $pkg');
    } catch (e) {
      debugPrint('UpiNotificationListener._onNotification error: $e');
    }
  }

  /// Map known package names to human-readable bank/app names.
  static String? _bankFromPackage(String pkg) {
    const map = {
      'com.google.android.apps.nbu.paisa.user': 'Google Pay',
      'com.phonepe.app': 'PhonePe',
      'net.one97.paytm': 'Paytm',
      'in.amazon.mShop.android.shopping': 'Amazon Pay',
      'in.org.npci.upiapp': 'BHIM',
      'com.dreamplug.androidapp': 'Cred',
      'com.mobikwik_new': 'MobiKwik',
      'com.freecharge.android': 'FreeCharge',
      'com.sbi.lotusintouch': 'SBI YONO',
      'com.snapwork.hdfc': 'HDFC Bank',
      'com.csam.icici.bank.imobile': 'ICICI Bank',
      'com.axis.mobile': 'Axis Bank',
      'com.msf.kash': 'Kotak Bank',
      'com.baroda.mpassbook': 'Bank of Baroda',
      'com.sliceit.app': 'Slice',
      'money.jupiter.app': 'Jupiter',
      'com.lazypay.lazypay': 'LazyPay',
    };
    return map[pkg];
  }
}
