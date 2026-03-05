import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Visual breakdown of monthly expenses by category.
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
    'Other': Icons.category_rounded,
  };

  static const _categoryColors = <String, Color>{
    'Food': Color(0xFFFF6B6B),
    'Shopping': Color(0xFF8B5CF6),
    'Transport': Color(0xFF0EA5E9),
    'Entertainment': Color(0xFFF59E0B),
    'Utilities': Color(0xFF10B981),
    'Health': Color(0xFFEC4899),
    'Education': Color(0xFF6366F1),
    'Transfers': Color(0xFF14B8A6),
    'Other': Color(0xFF94A3B8),
  };

  @override
  Widget build(BuildContext context) {
    if (breakdown.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.pie_chart_rounded,
                    color: Color(0xFF8B5CF6), size: 18),
              ),
              const SizedBox(width: 8),
              Text(
                'Spending by Category',
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1A1A2E)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...breakdown.entries.map((entry) {
            final color = _categoryColors[entry.key] ?? const Color(0xFF94A3B8);
            final icon = _categoryIcons[entry.key] ?? Icons.category_rounded;
            final pct = totalSpent > 0 ? entry.value / totalSpent : 0.0;

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: color, size: 16),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          entry.key,
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF1A1A2E)),
                        ),
                      ),
                      Text(
                        '₹${entry.value.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: color),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${(pct * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.poppins(
                            fontSize: 10, color: const Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: color.withValues(alpha: 0.12),
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
