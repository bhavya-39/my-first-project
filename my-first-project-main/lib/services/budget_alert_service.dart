import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'notification_service.dart';

/// Tracks and shows budget threshold alerts — both in-app dialogs AND push notifications.
class BudgetAlertService {
  /// Which alert levels have already been shown this session (70, 90, 100)
  final Set<int> _shownAlerts = {};

  void resetAlerts() => _shownAlerts.clear();

  /// Call whenever monthly expense or budget changes.
  Future<void> checkAndAlert({
    required BuildContext context,
    required double spent,
    required double budget,
  }) async {
    if (budget <= 0) return;
    final percent = (spent / budget) * 100;

    if (percent >= 100 && !_shownAlerts.contains(100)) {
      _shownAlerts.add(100);
      await NotificationService.sendBudgetAlert(level: 100, spent: spent, budget: budget);
      if (!context.mounted) return;
      await _showDialog(context, level: 100, spent: spent, budget: budget, percent: percent);
    } else if (percent >= 90 && !_shownAlerts.contains(90)) {
      _shownAlerts.add(90);
      await NotificationService.sendBudgetAlert(level: 90, spent: spent, budget: budget);
      if (!context.mounted) return;
      await _showDialog(context, level: 90, spent: spent, budget: budget, percent: percent);
    } else if (percent >= 70 && !_shownAlerts.contains(70)) {
      _shownAlerts.add(70);
      await NotificationService.sendBudgetAlert(level: 70, spent: spent, budget: budget);
      if (!context.mounted) return;
      await _showDialog(context, level: 70, spent: spent, budget: budget, percent: percent);
    }
  }

  Future<void> _showDialog(
    BuildContext context, {
    required int level,
    required double spent,
    required double budget,
    required double percent,
  }) async {
    if (!context.mounted) return;
    final cfg = _config(level);

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: cfg.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(cfg.icon, color: cfg.color, size: 36),
              ),
              const SizedBox(height: 16),
              Text(
                cfg.title,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 18, fontWeight: FontWeight.w700, color: cfg.color),
              ),
              const SizedBox(height: 10),
              Text(
                cfg.message,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: const Color(0xFF6B7280), height: 1.5),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('₹${spent.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700, fontSize: 15, color: cfg.color)),
                  Text(' / ₹${budget.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(
                          fontSize: 15, color: const Color(0xFF6B7280))),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: (percent / 100).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: cfg.color.withValues(alpha: 0.15),
                  valueColor: AlwaysStoppedAnimation<Color>(cfg.color),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cfg.color,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Got it',
                      style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _AlertConfig _config(int level) {
    switch (level) {
      case 100:
        return _AlertConfig(
          title: '🚨 Budget Exceeded!',
          message:
              'You have exceeded your monthly budget limit. Consider reviewing your UPI expenses.',
          color: const Color(0xFFEF4444),
          icon: Icons.money_off_rounded,
        );
      case 90:
        return _AlertConfig(
          title: '⚠️ 90% Limit Reached',
          message:
              'Only 10% of your budget remains. Time to slow down on spending!',
          color: const Color(0xFFF97316),
          icon: Icons.warning_amber_rounded,
        );
      default:
        return _AlertConfig(
          title: '💡 70% Budget Used',
          message:
              'You have used 70% of your monthly budget. Keep an eye on your spending.',
          color: const Color(0xFFF59E0B),
          icon: Icons.notifications_active_rounded,
        );
    }
  }
}

class _AlertConfig {
  final String title;
  final String message;
  final Color color;
  final IconData icon;
  const _AlertConfig(
      {required this.title,
      required this.message,
      required this.color,
      required this.icon});
}
