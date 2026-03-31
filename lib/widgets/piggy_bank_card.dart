import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/piggy_bank_service.dart';

/// Displays the virtual piggy bank balance and saving mode.
/// Tapping the mode chip opens a bottom sheet to change the mode/amount.
class PiggyBankCard extends StatelessWidget {
  final double totalSaved;
  final int savingsCount;
  /// Called after the user confirms a new mode/value.
  /// The callback receives no arguments; the caller should re-read
  /// [PiggyBankService.instance] for the updated values.
  final VoidCallback onSettingsChanged;

  // Keep old param for compat — ignored if onSettingsChanged is provided
  final ValueChanged<double>? onRateChanged;

  const PiggyBankCard({
    super.key,
    required this.totalSaved,
    required this.savingsCount,
    required this.onSettingsChanged,
    @Deprecated('Use onSettingsChanged') this.onRateChanged,
  });

  @override
  Widget build(BuildContext context) {
    final piggy = PiggyBankService.instance;
    final modeLabel = _modeLabel(piggy);

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
                onTap: () => _showModeDialog(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        modeLabel,
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.white,
                            fontWeight: FontWeight.w500),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_rounded,
                          size: 11, color: Colors.white),
                    ],
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
            'Saved from $savingsCount UPI transaction${savingsCount != 1 ? 's' : ''} this month',
            style: GoogleFonts.poppins(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                    _modeDescription(piggy),
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

  String _modeLabel(PiggyBankService piggy) {
    switch (piggy.mode) {
      case SavingMode.roundoff:
        return 'Round-off';
      case SavingMode.fixed:
        return '₹${piggy.fixedAmount.toStringAsFixed(0)} / txn';
      case SavingMode.percent:
        return '${piggy.percentage.toStringAsFixed(0)}% / txn';
    }
  }

  String _modeDescription(PiggyBankService piggy) {
    switch (piggy.mode) {
      case SavingMode.roundoff:
        return 'Rounds up each UPI payment to the next ₹10 and saves the difference';
      case SavingMode.fixed:
        return '₹${piggy.fixedAmount.toStringAsFixed(0)} is auto-saved for every UPI transaction';
      case SavingMode.percent:
        return '${piggy.percentage.toStringAsFixed(0)}% of each UPI payment is auto-saved here';
    }
  }

  Future<void> _showModeDialog(BuildContext context) async {
    final piggy = PiggyBankService.instance;
    SavingMode selectedMode = piggy.mode;
    double selectedPercent = piggy.percentage;
    double selectedFixed = piggy.fixedAmount;

    final percentOptions = [1.0, 2.0, 5.0, 10.0, 15.0, 20.0];
    final fixedOptions = [5.0, 10.0, 20.0, 50.0, 100.0];

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 28,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                Text('Micro-Savings Mode',
                    style: GoogleFonts.poppins(
                        fontSize: 17, fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                    'Choose how savings are calculated per UPI transaction.\nChanging this recalculates your balance for this month.',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: Colors.grey.shade600)),
                const SizedBox(height: 20),

                // ── Mode selector ──────────────────────────────────────────
                _ModeOption(
                  icon: '🔄',
                  title: 'Round-off',
                  subtitle: 'Save the difference to the next ₹10',
                  selected: selectedMode == SavingMode.roundoff,
                  onTap: () =>
                      setModalState(() => selectedMode = SavingMode.roundoff),
                ),
                const SizedBox(height: 10),
                _ModeOption(
                  icon: '💰',
                  title: 'Fixed Amount',
                  subtitle: 'Save a fixed ₹ amount per transaction',
                  selected: selectedMode == SavingMode.fixed,
                  onTap: () =>
                      setModalState(() => selectedMode = SavingMode.fixed),
                ),
                const SizedBox(height: 10),
                _ModeOption(
                  icon: '📊',
                  title: 'Percentage',
                  subtitle: 'Save a % of each transaction',
                  selected: selectedMode == SavingMode.percent,
                  onTap: () =>
                      setModalState(() => selectedMode = SavingMode.percent),
                ),
                const SizedBox(height: 18),

                // ── Value picker (context-sensitive) ───────────────────────
                if (selectedMode == SavingMode.percent) ...[
                  Text('Savings Percentage',
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: percentOptions.map((p) {
                      final sel = (p - selectedPercent).abs() < 0.01;
                      return GestureDetector(
                        onTap: () =>
                            setModalState(() => selectedPercent = p),
                        child: _Chip(
                          label: '${p.toStringAsFixed(0)}%',
                          selected: sel,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  // Custom input
                  _CustomValueField(
                    hint: 'Custom %',
                    suffix: '%',
                    initialValue: selectedPercent.toStringAsFixed(0),
                    onChanged: (v) {
                      final d = double.tryParse(v);
                      if (d != null && d > 0 && d <= 50) {
                        setModalState(() => selectedPercent = d);
                      }
                    },
                  ),
                ] else if (selectedMode == SavingMode.fixed) ...[
                  Text('Fixed Amount per Transaction',
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: fixedOptions.map((f) {
                      final sel = (f - selectedFixed).abs() < 0.01;
                      return GestureDetector(
                        onTap: () =>
                            setModalState(() => selectedFixed = f),
                        child: _Chip(
                          label: '₹${f.toStringAsFixed(0)}',
                          selected: sel,
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),
                  _CustomValueField(
                    hint: 'Custom ₹',
                    suffix: '₹',
                    prefix: true,
                    initialValue: selectedFixed.toStringAsFixed(0),
                    onChanged: (v) {
                      final d = double.tryParse(v);
                      if (d != null && d > 0) {
                        setModalState(() => selectedFixed = d);
                      }
                    },
                  ),
                ],

                const SizedBox(height: 24),

                // ── Save ───────────────────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await PiggyBankService.instance.updateSettings(
                        mode: selectedMode,
                        percentage: selectedPercent,
                        fixedAmount: selectedFixed,
                      );
                      await PiggyBankService.instance
                          .recalculateCurrentMonth();
                      onSettingsChanged();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Save & Recalculate',
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Small helper widgets ──────────────────────────────────────────────────────

class _ModeOption extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF10B981).withValues(alpha: 0.1)
              : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? const Color(0xFF10B981)
                : Colors.grey.shade200,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected
                              ? const Color(0xFF059669)
                              : Colors.black87)),
                  Text(subtitle,
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: Colors.grey.shade500)),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle_rounded,
                  color: Color(0xFF10B981), size: 20),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final bool selected;

  const _Chip({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFF10B981) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: selected ? const Color(0xFF10B981) : Colors.grey.shade300,
        ),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : Colors.black87,
            fontSize: 13),
      ),
    );
  }
}

class _CustomValueField extends StatefulWidget {
  final String hint;
  final String suffix;
  final bool prefix;
  final String initialValue;
  final ValueChanged<String> onChanged;

  const _CustomValueField({
    required this.hint,
    required this.suffix,
    required this.initialValue,
    required this.onChanged,
    this.prefix = false,
  });

  @override
  State<_CustomValueField> createState() => _CustomValueFieldState();
}

class _CustomValueFieldState extends State<_CustomValueField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
      ],
      style: GoogleFonts.poppins(fontSize: 14),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle: GoogleFonts.poppins(color: Colors.grey.shade400),
        prefixText: widget.prefix ? '₹ ' : null,
        suffixText: widget.prefix ? null : widget.suffix,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: Color(0xFF10B981), width: 2),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}
