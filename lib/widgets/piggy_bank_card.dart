import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Displays the virtual piggy bank balance and savings rate.
class PiggyBankCard extends StatelessWidget {
  final double totalSaved;
  final int savingsCount;
  final double savingsRate; // 0.0 – 0.50
  final ValueChanged<double> onRateChanged;

  const PiggyBankCard({
    super.key,
    required this.totalSaved,
    required this.savingsCount,
    required this.savingsRate,
    required this.onRateChanged,
  });

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
                'Piggy Bank Savings',
                style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => _showRateDialog(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    '${(savingsRate * 100).toStringAsFixed(0)}% / txn',
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            '₹${totalSaved.toStringAsFixed(2)}',
            style: GoogleFonts.poppins(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            'Saved from $savingsCount UPI transaction${savingsCount != 1 ? 's' : ''}',
            style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 12),
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
                    '${(savingsRate * 100).toStringAsFixed(0)}% of each UPI payment is auto-saved here',
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.9)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRateDialog(BuildContext context) async {
    double selectedRate = savingsRate;
    final rates = [0.01, 0.02, 0.05, 0.10, 0.15, 0.20];

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Savings Rate per Transaction',
                  style: GoogleFonts.poppins(
                      fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              Text(
                  'Choose what % of each UPI payment to save automatically',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: rates.map((r) {
                  final selected = (r - selectedRate).abs() < 0.001;
                  return GestureDetector(
                    onTap: () => setModalState(() => selectedRate = r),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF10B981)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${(r * 100).toStringAsFixed(0)}%',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : Colors.black87),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    onRateChanged(selectedRate);
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('Save',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
