import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_theme.dart';

/// Glassmorphism category breakdown card — light + dark fintech theme.
class CategoryBreakdownCard extends StatelessWidget {
  final Map<String, double> breakdown;
  final double totalSpent;

  const CategoryBreakdownCard({
    super.key,
    required this.breakdown,
    required this.totalSpent,
  });

  static const _categoryIcons = <String, IconData>{
    'Food': Icons.restaurant_rounded,
    'Shopping': Icons.shopping_bag_rounded,
    'Transport': Icons.directions_car_rounded,
    'Entertainment': Icons.movie_rounded,
    'Utilities': Icons.bolt_rounded,
    'Health': Icons.local_hospital_rounded,
    'Education': Icons.school_rounded,
    'Transfers': Icons.swap_horiz_rounded,
    'Travel': Icons.flight_rounded,
    'Bills': Icons.receipt_long_rounded,
    'Other': Icons.category_rounded,
  };

  static const _categoryColors = <String, Color>{
    'Food': Color(0xFFFF6B6B),
    'Shopping': Color(0xFF0EA5E9),
    'Transport': Color(0xFF0EA5E9),
    'Entertainment': Color(0xFFF59E0B),
    'Utilities': Color(0xFF10B981),
    'Health': Color(0xFFEC4899),
    'Education': Color(0xFF6366F1),
    'Transfers': Color(0xFF14B8A6),
    'Travel': Color(0xFF4ECDC4),
    'Bills': Color(0xFF0EA5E9),
    'Other': Color(0xFF94A3B8),
  };

  @override
  Widget build(BuildContext context) {
    if (breakdown.isEmpty) return const SizedBox.shrink();

    final textPrimary = AppTheme.textDark;
    final cardBg = AppTheme.cardWhite;
    final borderColor = Colors.grey.shade200;
    final shadowColor = Colors.black.withValues(alpha: 0.05);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppTheme.skyBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
              ),
              child: ShaderMask(
                shaderCallback: (bounds) =>
                    AppTheme.primaryGradient.createShader(bounds),
                child: const Icon(Icons.pie_chart_rounded,
                    color: Colors.white, size: 20),
              ),
            ),
            const SizedBox(width: 10),
            Text('Spending by Category',
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: textPrimary)),
          ]),
          const SizedBox(height: 18),
          ...breakdown.entries.map((entry) {
            final color = _categoryColors[entry.key] ?? const Color(0xFF94A3B8);
            final icon = _categoryIcons[entry.key] ?? Icons.category_rounded;
            final pct = totalSpent > 0 ? entry.value / totalSpent : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(children: [
                Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(entry.key,
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: textPrimary)),
                  ),
                  Text('₹${entry.value.toStringAsFixed(0)}',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: color)),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('${(pct * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: color)),
                  ),
                ]),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    minHeight: 7,
                    backgroundColor: color.withValues(alpha: 0.08),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ]),
            );
          }),
        ],
      ),
    );
  }
}
