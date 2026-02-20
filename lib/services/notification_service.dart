import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:workmanager/workmanager.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';

// ── Workmanager callback (top-level function, required by workmanager) ────────
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task == NotificationService.budgetCheckTask) {
      await _runBudgetCheck();
    }
    return Future.value(true);
  });
}

/// Runs a background budget check and fires a local notification if needed.
Future<void> _runBudgetCheck() async {
  try {
    // Initialize Firebase in background isolate
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    final auth = FirebaseAuth.instance;
    final user = auth.currentUser;
    if (user == null) return;

    final uid = user.uid;
    final firestore = FirebaseFirestore.instance;

    // Fetch budget
    final budgetDoc = await firestore
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('budget')
        .get();
    if (!budgetDoc.exists) return;
    final budget = (budgetDoc.data()?['amount'] as num?)?.toDouble();
    if (budget == null || budget <= 0) return;

    // Fetch current month expenses
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, 1);
    final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);

    final txSnapshot = await firestore
        .collection('users')
        .doc(uid)
        .collection('transactions')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(end))
        .where('type', isEqualTo: 'expense')
        .get();

    double spent = 0;
    for (final doc in txSnapshot.docs) {
      spent += (doc.data()['amount'] as num?)?.toDouble() ?? 0;
    }

    final percent = (spent / budget) * 100;

    // Determine which notification to fire
    if (percent >= 100) {
      await NotificationService._sendNotification(
        id: 3,
        title: '🚨 Budget Exceeded!',
        body:
            'You\'ve spent ₹${spent.toStringAsFixed(0)} of your ₹${budget.toStringAsFixed(0)} budget. Limit crossed!',
      );
    } else if (percent >= 90) {
      await NotificationService._sendNotification(
        id: 2,
        title: '⚠️ 90% Budget Used',
        body:
            'Only ₹${(budget - spent).toStringAsFixed(0)} left in your monthly budget. Slow down!',
      );
    } else if (percent >= 70) {
      await NotificationService._sendNotification(
        id: 1,
        title: '💡 70% Budget Used',
        body:
            'You\'ve used ₹${spent.toStringAsFixed(0)} of ₹${budget.toStringAsFixed(0)} this month.',
      );
    }
  } catch (e) {
    // Silently fail in background
  }
}

// ── NotificationService ──────────────────────────────────────────────────────
class NotificationService {
  static const budgetCheckTask = 'budgetCheckTask';
  static const _channelId = 'fintrack_budget_alerts';
  static const _channelName = 'Budget Alerts';

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Call once from main() before runApp
  static Future<void> init() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    // Request notification permission on Android 13+
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    // Register background task with Workmanager (every 15 minutes)
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      'fintrack_budget_check',
      budgetCheckTask,
      frequency: const Duration(minutes: 15),
      constraints: Constraints(networkType: NetworkType.connected),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    );
  }

  /// Send a local notification immediately (used from background + foreground)
  static Future<void> _sendNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: 'Alerts when you approach or exceed your monthly budget',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
      styleInformation: BigTextStyleInformation(''),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    await _plugin.show(
      id,
      title,
      body,
      const NotificationDetails(android: androidDetails, iOS: iosDetails),
    );
  }

  /// Called from foreground code when threshold is crossed
  static Future<void> sendBudgetAlert({
    required int level,
    required double spent,
    required double budget,
  }) async {
    final remaining = budget - spent;
    switch (level) {
      case 100:
        await _sendNotification(
          id: 3,
          title: '🚨 Budget Exceeded!',
          body:
              'You\'ve spent ₹${spent.toStringAsFixed(0)} of your ₹${budget.toStringAsFixed(0)} limit!',
        );
        break;
      case 90:
        await _sendNotification(
          id: 2,
          title: '⚠️ 90% Budget Used',
          body:
              'Only ₹${remaining.toStringAsFixed(0)} remaining of your ₹${budget.toStringAsFixed(0)} budget.',
        );
        break;
      case 70:
        await _sendNotification(
          id: 1,
          title: '💡 70% Budget Used',
          body:
              'You\'ve used ₹${spent.toStringAsFixed(0)} of ₹${budget.toStringAsFixed(0)} this month.',
        );
        break;
    }
  }
}
