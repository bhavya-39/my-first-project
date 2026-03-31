import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_theme.dart';
import '../models/expense_model.dart';
import '../database/local_database.dart';
import '../services/expense_repository.dart';
import '../services/piggy_bank_service.dart';
import '../widgets/gradient_button.dart';

/// ─────────────────────────────────────────────────────────────────────────────
/// Add Expense Screen
/// Manual expense entry with SQLite + Firestore dual storage.
/// ─────────────────────────────────────────────────────────────────────────────
class AddExpenseScreen extends StatefulWidget {
  const AddExpenseScreen({super.key});

  @override
  State<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends State<AddExpenseScreen>
    with SingleTickerProviderStateMixin {
  // ── Form ─────────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  String? _selectedCategory;
  String _paymentMethod = 'UPI';
  DateTime _selectedDate = DateTime.now();
  bool _saving = false;

  // ── Categories ────────────────────────────────────────────────────────────
  static const _categories = <_CategoryItem>[
    _CategoryItem('Food', Icons.restaurant_rounded, Color(0xFFFF6B6B)),
    _CategoryItem('Travel', Icons.directions_bus_rounded, Color(0xFF4ECDC4)),
    _CategoryItem('Shopping', Icons.shopping_bag_rounded, Color(0xFFFFD93D)),
    _CategoryItem('Bills', Icons.receipt_long_rounded, Color(0xFF0EA5E9)),
    _CategoryItem('Entertainment', Icons.movie_rounded, Color(0xFF6C5CE7)),
    _CategoryItem('Education', Icons.school_rounded, Color(0xFF0984E3)),
    _CategoryItem('Health', Icons.local_hospital_rounded, Color(0xFFEC4899)),
    _CategoryItem('Others', Icons.more_horiz_rounded, Color(0xFFB2BEC3)),
  ];

  // ── Animation ─────────────────────────────────────────────────────────────
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  // ── Date Picker ───────────────────────────────────────────────────────────
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (ctx, child) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx).colorScheme.copyWith(
                  primary: AppTheme.skyBlue,
                ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) setState(() => _selectedDate = picked);
  }

  // ── Save ───────────────────────────────────────────────────────────────────
  Future<void> _saveExpense() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      _showSnack('Please select a category', AppTheme.errorRed);
      return;
    }

    setState(() => _saving = true);

    try {
      final amount = double.parse(_amountController.text.trim());
      final note = _noteController.text.trim();
      final now = DateTime.now();

      // ── Hash for deduplication ──────────────────────────────────────────
      final minuteKey =
          '${_selectedDate.year}${_selectedDate.month}${_selectedDate.day}${now.hour}${now.minute}';
      final rawHash =
          'manual|$_selectedCategory|${amount.toStringAsFixed(2)}|$minuteKey';
      final hash = md5.convert(utf8.encode(rawHash)).toString();

      final expense = Expense(
        hash: hash,
        amount: amount,
        merchant: _selectedCategory!,
        category: _selectedCategory!,
        date: _selectedDate,
        note: note.isEmpty ? null : note,
        paymentMethod: _paymentMethod,
        confidence: 100,
      );

      // ── 1. Save to local SQLite ────────────────────────────────────────
      final db = LocalDatabase.instance;
      final id = await db.insertExpense(expense);

      if (id <= 0) {
        _showSnack('Expense already exists (duplicate)', AppTheme.errorRed);
        setState(() => _saving = false);
        return;
      }

      // ── 2. Piggy bank saving ───────────────────────────────────────────
      final piggySaved = await PiggyBankService.instance.recordSaving(
        expenseAmount: amount,
        expenseId: id,
      );

      // ── 3. Sync to Firestore (fire and forget) ─────────────────────────
      _syncToFirestore(expense, piggySaved);

      // ── 4. Refresh dashboard streams ───────────────────────────────────
      await ExpenseRepository.instance.refresh();

      // ── 5. Show success & pop ──────────────────────────────────────────
      if (mounted) {
        _showSnack(
          'Expense Added Successfully',
          AppTheme.successGreen,
        );
        Navigator.pop(context, true); // true = something was saved
      }
    } catch (e) {
      debugPrint('AddExpenseScreen._saveExpense error: $e');
      _showSnack('Failed to save expense', AppTheme.errorRed);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Fire-and-forget Firestore sync for expense + piggy saving.
  Future<void> _syncToFirestore(Expense expense, double piggySaved) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;

      final userRef = FirebaseFirestore.instance.collection('users').doc(uid);

      // Expense doc
      await userRef.collection('expenses').add({
        'amount': expense.amount,
        'category': expense.category,
        'note': expense.note,
        'paymentMethod': expense.paymentMethod,
        'date': Timestamp.fromDate(expense.date),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Piggy saving doc
      if (piggySaved > 0) {
        await userRef.collection('piggy_savings').add({
          'amount': piggySaved,
          'expenseAmount': expense.amount,
          'mode': PiggyBankService.instance.mode.name,
          'date': Timestamp.fromDate(expense.date),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      debugPrint('Firestore sync error (non-critical): $e');
    }
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight;
    final cardBg = isDark ? AppTheme.cardDark : Colors.white;
    final textPrimary = isDark ? AppTheme.textDarkMode : AppTheme.textDark;
    final textSub = isDark ? AppTheme.textMediumDark : AppTheme.textMedium;

    return Scaffold(
      backgroundColor: bg,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          slivers: [
            // ── App Bar ──────────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 110,
              pinned: true,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_rounded,
                    color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration:
                      const BoxDecoration(gradient: AppTheme.primaryGradient),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(60, 12, 24, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('Add Expense',
                              style: GoogleFonts.poppins(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)),
                          Text('Track every rupee you spend',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.8))),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              backgroundColor: AppTheme.skyBlueDark,
            ),

            // ── Form Content ─────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Amount ─────────────────────────────────────
                        _sectionLabel('Amount', textPrimary),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.04),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextFormField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: GoogleFonts.poppins(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: textPrimary,
                            ),
                            decoration: InputDecoration(
                              prefixText: '₹  ',
                              prefixStyle: GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.skyBlue,
                              ),
                              hintText: '0.00',
                              hintStyle: GoogleFonts.poppins(
                                fontSize: 28,
                                fontWeight: FontWeight.w300,
                                color: textSub,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: cardBg,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 20),
                            ),
                            validator: (v) {
                              if (v == null || v.trim().isEmpty) {
                                return 'Enter an amount';
                              }
                              final amount = double.tryParse(v.trim());
                              if (amount == null || amount <= 0) {
                                return 'Amount must be greater than 0';
                              }
                              return null;
                            },
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Category ──────────────────────────────────
                        _sectionLabel('Category', textPrimary),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: _categories.map((cat) {
                            final selected = _selectedCategory == cat.name;
                            return GestureDetector(
                              onTap: () =>
                                  setState(() => _selectedCategory = cat.name),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? cat.color.withValues(alpha: 0.15)
                                      : cardBg,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: selected
                                        ? cat.color
                                        : (isDark
                                            ? Colors.white
                                                .withValues(alpha: 0.08)
                                            : Colors.grey.shade200),
                                    width: selected ? 2 : 1,
                                  ),
                                  boxShadow: selected
                                      ? [
                                          BoxShadow(
                                            color: cat.color
                                                .withValues(alpha: 0.25),
                                            blurRadius: 8,
                                            offset: const Offset(0, 3),
                                          )
                                        ]
                                      : [
                                          BoxShadow(
                                            color: Colors.black
                                                .withValues(alpha: 0.03),
                                            blurRadius: 6,
                                          )
                                        ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(cat.icon,
                                        size: 18,
                                        color: selected ? cat.color : textSub),
                                    const SizedBox(width: 6),
                                    Text(
                                      cat.name,
                                      style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w500,
                                        color:
                                            selected ? cat.color : textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        if (_selectedCategory == null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('',
                                style: GoogleFonts.poppins(
                                    fontSize: 11, color: AppTheme.errorRed)),
                          ),
                        const SizedBox(height: 24),

                        // ── Payment Method ────────────────────────────
                        _sectionLabel('Payment Method', textPrimary),
                        const SizedBox(height: 10),
                        Row(
                          children: ['UPI', 'Cash'].map((method) {
                            final selected = _paymentMethod == method;
                            final icon = method == 'UPI'
                                ? Icons.account_balance_rounded
                                : Icons.payments_rounded;
                            final color = method == 'UPI'
                                ? const Color(0xFF0EA5E9)
                                : const Color(0xFF10B981);
                            return Expanded(
                              child: GestureDetector(
                                onTap: () =>
                                    setState(() => _paymentMethod = method),
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  margin: EdgeInsets.only(
                                    right: method == 'UPI' ? 6 : 0,
                                    left: method == 'Cash' ? 6 : 0,
                                  ),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 14),
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? color.withValues(alpha: 0.12)
                                        : cardBg,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: selected
                                          ? color
                                          : (isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.08)
                                              : Colors.grey.shade200),
                                      width: selected ? 2 : 1,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.03),
                                        blurRadius: 6,
                                      )
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(icon,
                                          size: 20,
                                          color: selected ? color : textSub),
                                      const SizedBox(width: 8),
                                      Text(
                                        method,
                                        style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: selected
                                              ? FontWeight.w600
                                              : FontWeight.w500,
                                          color: selected ? color : textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 24),

                        // ── Date ──────────────────────────────────────
                        _sectionLabel('Date', textPrimary),
                        const SizedBox(height: 8),
                        GestureDetector(
                          onTap: _pickDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 14),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : Colors.grey.shade200,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 6,
                                )
                              ],
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_rounded,
                                    size: 18, color: AppTheme.skyBlue),
                                const SizedBox(width: 12),
                                Text(
                                  '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}',
                                  style: GoogleFonts.poppins(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    color: textPrimary,
                                  ),
                                ),
                                const Spacer(),
                                Icon(Icons.arrow_forward_ios_rounded,
                                    size: 14, color: textSub),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── Note ──────────────────────────────────────
                        _sectionLabel('Note (optional)', textPrimary),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: cardBg,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.03),
                                blurRadius: 6,
                              )
                            ],
                          ),
                          child: TextFormField(
                            controller: _noteController,
                            maxLines: 3,
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: textPrimary,
                            ),
                            decoration: InputDecoration(
                              hintText: 'e.g. Lunch at college canteen',
                              hintStyle: GoogleFonts.poppins(
                                  fontSize: 13, color: textSub),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                              filled: true,
                              fillColor: cardBg,
                              contentPadding: const EdgeInsets.all(16),
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),

                        // ── Piggy info ────────────────────────────────
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFFF59E0B).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(children: [
                            const Text('🐷', style: TextStyle(fontSize: 22)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _piggyModeDescription(),
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  color: isDark
                                      ? AppTheme.textDarkMode
                                      : const Color(0xFF92400E),
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ]),
                        ),
                        const SizedBox(height: 24),

                        // ── Save Button ───────────────────────────────
                        GradientButton(
                          text: 'Save Expense',
                          isLoading: _saving,
                          onPressed: _saving ? null : _saveExpense,
                        ),

                        const SizedBox(height: 32),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text, Color color) => Text(
        text,
        style: GoogleFonts.poppins(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      );

  String _piggyModeDescription() {
    final piggy = PiggyBankService.instance;
    switch (piggy.mode) {
      case SavingMode.roundoff:
        return 'Piggy Bank: Round-off mode — the difference to the next ₹10 will be auto-saved.';
      case SavingMode.fixed:
        return 'Piggy Bank: Fixed mode — ₹${piggy.fixedAmount.toStringAsFixed(0)} will be auto-saved per expense.';
      case SavingMode.percent:
        return 'Piggy Bank: ${piggy.percentage.toStringAsFixed(0)}% mode — ${piggy.percentage.toStringAsFixed(0)}% of the expense will be auto-saved.';
    }
  }
}

// ── Category data class ─────────────────────────────────────────────────────
class _CategoryItem {
  final String name;
  final IconData icon;
  final Color color;
  const _CategoryItem(this.name, this.icon, this.color);
}
