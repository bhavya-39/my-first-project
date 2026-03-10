import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';
import '../services/piggy_bank_service.dart';

/// Glassmorphism Piggy Bank Card — light + dark fintech theme.
class PiggyBankCard extends StatelessWidget {
  final double totalSaved;
  final int savingsCount;
  final SavingMode currentMode;
  final double percentage;
  final double fixedAmount;
  final ValueChanged<SavingMode> onModeChanged;
  final ValueChanged<double> onPercentageChanged;

  const PiggyBankCard({
    super.key,
    required this.totalSaved,
    required this.savingsCount,
    required this.currentMode,
    required this.percentage,
    required this.fixedAmount,
    required this.onModeChanged,
    required this.onPercentageChanged,
  });

  String _modeLabel(SavingMode mode) {
    switch (mode) {
      case SavingMode.roundoff:
        return 'Round-off';
      case SavingMode.fixed:
        return 'Fixed ₹${fixedAmount.toStringAsFixed(0)}';
      case SavingMode.percent:
        return '${percentage.toStringAsFixed(0)}%';
    }
  }

  String _modeDescription(SavingMode mode) {
    switch (mode) {
      case SavingMode.roundoff:
        return 'Spare change saved by rounding each expense.';
      case SavingMode.fixed:
        return '₹${fixedAmount.toStringAsFixed(0)} saved for every expense.';
      case SavingMode.percent:
        return '${percentage.toStringAsFixed(0)}% saved from every expense.';
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Theme-aware colors ──────────────────────────────────────────────
    final textPrimary = AppTheme.textDark;
    final textSub = AppTheme.textMedium;
    final textDetail = AppTheme.skyBlueDark;
    final cardBg = AppTheme.cardWhite;
    final borderColor = Colors.grey.shade200;
    final shadowColor = Colors.black.withValues(alpha: 0.05);

    final infoBg = AppTheme.skyBlueDark.withValues(alpha: 0.08);
    final inactiveBg = AppTheme.backgroundLight;
    final inactiveBorder = Colors.grey.shade300;
    final inactiveText = AppTheme.textMedium;
    final inactiveIcon = AppTheme.textLight;

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
          // ── Header ──────────────────────────────────────────────
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
                  child: const Text('🐷', style: TextStyle(fontSize: 20)),
                ),
              ),
              const SizedBox(width: 12),
              Text('Piggy Bank',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: textPrimary)),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: AppTheme.skyBlue.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppTheme.skyBlue.withValues(alpha: 0.15)),
                ),
                child: Text(_modeLabel(currentMode),
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: textDetail,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 22),

          // ── Savings Amount ──────────────────────────────────────
          ShaderMask(
            shaderCallback: (bounds) =>
                AppTheme.primaryGradient.createShader(bounds),
            child: Text('₹${totalSaved.toStringAsFixed(0)}',
                style: GoogleFonts.poppins(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Colors.white)),
          ),
          const SizedBox(height: 4),
          Text('Saved from $savingsCount transactions this month',
              style: GoogleFonts.poppins(fontSize: 12, color: textSub)),
          const SizedBox(height: 16),

          // ── Info banner ────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: infoBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: AppTheme.skyBlueDark.withValues(alpha: 0.15)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded, color: textDetail, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(_modeDescription(currentMode),
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: textDetail, height: 1.3)),
              ),
            ]),
          ),
          const SizedBox(height: 18),

          // ── Mode Selector ──────────────────────────────────────
          Text('Saving Mode',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: textPrimary)),
          const SizedBox(height: 10),
          Row(
            children: SavingMode.values.map((mode) {
              final isActive = mode == currentMode;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onModeChanged(mode),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: EdgeInsets.only(
                        right: mode != SavingMode.percent ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: isActive ? AppTheme.primaryGradient : null,
                      color: isActive ? null : inactiveBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isActive ? Colors.transparent : inactiveBorder,
                        width: isActive ? 0 : 1.5,
                      ),
                      boxShadow: isActive
                          ? [
                              BoxShadow(
                                color: AppTheme.skyBlue
                                    .withValues(alpha: 0.25),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              )
                            ]
                          : null,
                    ),
                    child: Column(children: [
                      Icon(
                        mode == SavingMode.roundoff
                            ? Icons.swap_vert_rounded
                            : mode == SavingMode.fixed
                                ? Icons.savings_rounded
                                : Icons.percent_rounded,
                        size: 22,
                        color: isActive ? Colors.white : inactiveIcon,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        mode == SavingMode.roundoff
                            ? 'Round-off'
                            : mode == SavingMode.fixed
                                ? 'Fixed'
                                : 'Percent',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight:
                              isActive ? FontWeight.w600 : FontWeight.w500,
                          color: isActive ? Colors.white : inactiveText,
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),

          // ── Percentage picker ──────────────────────────────────
          if (currentMode == SavingMode.percent) ...[
            const SizedBox(height: 14),
            Row(
              children: [5.0, 10.0, 15.0, 20.0].map((pct) {
                final isActive = pct == percentage;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onPercentageChanged(pct),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: EdgeInsets.only(right: pct != 20.0 ? 6 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        gradient: isActive ? AppTheme.primaryGradient : null,
                        color: isActive ? null : inactiveBg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                            color:
                                isActive ? Colors.transparent : inactiveBorder),
                      ),
                      child: Center(
                        child: Text('${pct.toStringAsFixed(0)}%',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isActive ? Colors.white : inactiveText)),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
