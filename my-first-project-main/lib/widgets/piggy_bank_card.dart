import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/piggy_bank_service.dart';

/// Displays the piggy bank savings with a mode selector.
/// Supports: Round-off, Fixed ₹10, and Percentage saving.
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
        return 'Spare change (round-up to ₹10) saved per UPI payment';
      case SavingMode.fixed:
        return '₹${fixedAmount.toStringAsFixed(0)} saved for every UPI payment';
      case SavingMode.percent:
        return '${percentage.toStringAsFixed(0)}% of each UPI payment saved';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF10B981), Color(0xFF059669)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF10B981).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text('🐷', style: TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 10),
              Text(
                'Piggy Bank',
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.4)),
                ),
                child: Text(
                  _modeLabel(currentMode),
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Savings Amount ──────────────────────────────────────────────
          Text(
            '₹${totalSaved.toStringAsFixed(0)}',
            style: GoogleFonts.poppins(
                fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Saved from $savingsCount transaction${savingsCount != 1 ? 's' : ''} this month',
            style: GoogleFonts.poppins(
                fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 14),

          // ── Info banner ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: Colors.white, size: 14),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _modeDescription(currentMode),
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Mode Selector ───────────────────────────────────────────────
          Text(
            'Saving Mode',
            style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 8),
          Row(
            children: SavingMode.values.map((mode) {
              final isActive = mode == currentMode;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onModeChanged(mode),
                  child: Container(
                    margin: EdgeInsets.only(
                        right: mode != SavingMode.percent ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: isActive
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActive
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          mode == SavingMode.roundoff
                              ? Icons.swap_vert_rounded
                              : mode == SavingMode.fixed
                                  ? Icons.savings_rounded
                                  : Icons.percent_rounded,
                          size: 18,
                          color:
                              isActive ? const Color(0xFF059669) : Colors.white,
                        ),
                        const SizedBox(height: 4),
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
                            color: isActive
                                ? const Color(0xFF059669)
                                : Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          // ── Percentage picker (only for percent mode) ───────────────────
          if (currentMode == SavingMode.percent) ...[
            const SizedBox(height: 14),
            Row(
              children: [5.0, 10.0, 15.0, 20.0].map((pct) {
                final isActive = pct == percentage;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => onPercentageChanged(pct),
                    child: Container(
                      margin: EdgeInsets.only(right: pct != 20.0 ? 6 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isActive
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '${pct.toStringAsFixed(0)}%',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isActive
                                ? const Color(0xFF059669)
                                : Colors.white,
                          ),
                        ),
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
