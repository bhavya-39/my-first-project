import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Glassmorphism BudgetCard — light + dark fintech theme.
class BudgetCard extends StatelessWidget {
  final double? budget;
  final double spent;
  final VoidCallback onSetBudget;

  const BudgetCard({
    super.key,
    required this.budget,
    required this.spent,
    required this.onSetBudget,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasBudget = budget != null && budget! > 0;
    final percent = hasBudget ? (spent / budget!).clamp(0.0, 1.0) : 0.0;
    final remaining = hasBudget ? (budget! - spent) : 0.0;

    // ── Theme-aware colors ──────────────────────────────────────────────
    final textPrimary = AppTheme.textDark;
    final textSub = AppTheme.textMedium;
    final cardBg = AppTheme.cardWhite;
    final borderColor = Colors.grey.shade200;
    final shadowColor = Colors.black.withValues(alpha: 0.05);
    final chipBg = AppTheme.skyBlue.withValues(alpha: 0.08);
    final accentColor = AppTheme.skyBlue;

    Color progressColor;
    if (percent >= 1.0) {
      progressColor = const Color(0xFFEF4444);
    } else if (percent >= 0.9) {
      progressColor = const Color(0xFFF97316);
    } else if (percent >= 0.7) {
      progressColor = const Color(0xFFF59E0B);
    } else {
      progressColor = const Color(0xFF10B981);
    }

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
              color: shadowColor, blurRadius: 20, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.skyBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ShaderMask(
                  shaderCallback: (bounds) =>
                      AppTheme.primaryGradient.createShader(bounds),
                  child: const Icon(Icons.pie_chart_outline_rounded,
                      color: Colors.white, size: 22),
                ),
              ),
              const SizedBox(width: 12),
              Text('Monthly Budget',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textPrimary)),
              const Spacer(),
              GestureDetector(
                onTap: onSetBudget,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: accentColor.withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(hasBudget ? Icons.edit_rounded : Icons.add_rounded,
                        color: accentColor, size: 15),
                    const SizedBox(width: 4),
                    Text(hasBudget ? 'Edit' : 'Set Budget',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: accentColor)),
                  ]),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          if (!hasBudget) ...[
            Center(
              child: Column(children: [
                Icon(Icons.account_balance_wallet_outlined,
                    color: accentColor.withValues(alpha: 0.4), size: 44),
                const SizedBox(height: 10),
                Text('No budget set for this month',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: textSub)),
                const SizedBox(height: 4),
                Text('Tap "Set Budget" to get started',
                    style: GoogleFonts.poppins(fontSize: 11, color: textSub)),
              ]),
            ),
          ] else ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Spent',
                      style: GoogleFonts.poppins(fontSize: 11, color: textSub)),
                  Text('₹${spent.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: progressColor)),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('Budget',
                      style: GoogleFonts.poppins(fontSize: 11, color: textSub)),
                  Text('₹${budget!.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: textPrimary)),
                ]),
              ],
            ),
            const SizedBox(height: 16),
            Stack(children: [
              Container(
                height: 12,
                decoration: BoxDecoration(
                  color: progressColor.withValues(alpha: isDark ? 0.20 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              LayoutBuilder(builder: (context, constraints) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.easeOutCubic,
                  height: 12,
                  width: constraints.maxWidth * percent,
                  decoration: BoxDecoration(
                    gradient: AppTheme.progressGradient,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.skyBlueLighter.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                );
              }),
            ]),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        progressColor.withValues(alpha: isDark ? 0.20 : 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${(percent * 100).toStringAsFixed(0)}% used',
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: progressColor,
                          fontWeight: FontWeight.w600)),
                ),
                Text(
                  remaining >= 0
                      ? '₹${remaining.toStringAsFixed(0)} remaining'
                      : '₹${remaining.abs().toStringAsFixed(0)} over limit',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: remaining >= 0 ? textSub : const Color(0xFFEF4444),
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
