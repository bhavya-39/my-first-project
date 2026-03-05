import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../theme/app_theme.dart';
import '../services/auth_service.dart';
import '../services/budget_service.dart';
import '../services/budget_alert_service.dart';
import '../services/sms_listener_service.dart';
import '../services/expense_repository.dart';
import '../services/piggy_bank_service.dart';
import '../models/expense_model.dart';
import '../widgets/budget_card.dart';
import '../widgets/category_breakdown_card.dart';
import '../widgets/piggy_bank_card.dart';
import 'login_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with SingleTickerProviderStateMixin {
  // ── Services ────────────────────────────────────────────────────────────────
  final _authService = AuthService();
  final _budgetService = BudgetService();
  final _budgetAlertService = BudgetAlertService();
  final _smsListener = SmsListenerService.instance;
  final _repository = ExpenseRepository.instance;
  final _piggyBank = PiggyBankService.instance;

  User? get _user => FirebaseAuth.instance.currentUser;

  // ── Animation ────────────────────────────────────────────────────────────────
  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // ── State streams ─────────────────────────────────────────────────────────
  late StreamSubscription<List<Expense>> _expensesSub;
  late StreamSubscription<Map<String, double>> _categorySub;
  late StreamSubscription<double> _totalSub;
  late StreamSubscription<List<Expense>> _reviewSub;

  List<Expense> _expenses = [];
  Map<String, double> _categories = {};
  double _monthlySpent = 0;
  List<Expense> _pendingReview = [];
  double _piggyTotal = 0;
  int _piggyCount = 0;
  double? _budget;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _animController.forward();

    // Wire up SMS listener → repository
    _smsListener.init(_repository);

    // Subscribe to repository streams
    _expensesSub = _repository.expensesStream.listen((e) {
      if (mounted) setState(() => _expenses = e);
    });
    _categorySub = _repository.categoryStream.listen((c) {
      if (mounted) setState(() => _categories = c);
    });
    _totalSub = _repository.totalStream.listen((t) {
      if (mounted) {
        setState(() => _monthlySpent = t);
        _checkBudgetAlerts();
      }
    });
    _reviewSub = _repository.reviewStream.listen((r) {
      if (mounted) setState(() => _pendingReview = r);
    });

    // Initial load
    _repository.refresh();
    _loadPiggyBank();
    _piggyBank.loadSettings().then((_) {
      if (mounted) setState(() {});
    });

    // Sync historical inbox on launch
    _syncSms(silent: true);

    // Subscribe to budget
    _budgetService.getBudgetStream().listen((b) {
      if (mounted) setState(() => _budget = b);
    });
  }

  /// Load piggy bank total and count for the current month.
  Future<void> _loadPiggyBank() async {
    final total = await _piggyBank.getMonthlySavings();
    final count = await _piggyBank.getMonthlySavingsCount();
    if (mounted) {
      setState(() {
        _piggyTotal = total;
        _piggyCount = count;
      });
    }
  }

  void _checkBudgetAlerts() {
    if (_budget != null && _budget! > 0 && _monthlySpent > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _budgetAlertService.checkAndAlert(
              context: context, spent: _monthlySpent, budget: _budget!);
        }
      });
    }
  }

  Future<void> _syncSms({bool silent = false}) async {
    if (_syncing) return;
    setState(() => _syncing = true);

    final granted = await _smsListener.requestPermissions();
    if (!granted) {
      setState(() => _syncing = false);
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('SMS permission required',
              style: GoogleFonts.poppins(fontSize: 13)),
          backgroundColor: AppTheme.errorRed,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
      return;
    }

    final count = await _smsListener.syncInbox();
    await _loadPiggyBank();
    if (mounted) {
      setState(() => _syncing = false);
      if (!silent || count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor:
              count > 0 ? AppTheme.successGreen : AppTheme.primaryBlue,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          content: Row(children: [
            Icon(count > 0 ? Icons.sms_rounded : Icons.check_circle_outline,
                color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Text(
              count > 0
                  ? '$count new UPI transaction${count > 1 ? 's' : ''} imported!'
                  : 'No new UPI transactions found',
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white),
            ),
          ]),
        ));
      }
    }
  }

  Future<void> _handleSignOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Sign Out',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        content: Text('Are you sure?',
            style:
                GoogleFonts.poppins(fontSize: 14, color: AppTheme.textMedium)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: AppTheme.textMedium))),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Sign Out',
                  style: GoogleFonts.poppins(
                      color: AppTheme.errorRed, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _authService.signOut();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
    }
  }

  Future<void> _showSetBudgetDialog() async {
    final controller = TextEditingController(
        text: _budget != null ? _budget!.toStringAsFixed(0) : '');
    final formKey = GlobalKey<FormState>();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.pie_chart_rounded,
                color: Color(0xFF8B5CF6), size: 20),
          ),
          const SizedBox(width: 10),
          Text(_budget != null ? 'Edit Budget' : 'Set Monthly Budget',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 16)),
        ]),
        content: Form(
          key: formKey,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              autofocus: true,
              style: GoogleFonts.poppins(
                  fontSize: 20, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                prefixText: '₹  ',
                hintText: '5000',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: Color(0xFF8B5CF6), width: 2)),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter an amount';
                if (double.tryParse(v.trim()) == null ||
                    double.parse(v.trim()) <= 0) {
                  return 'Invalid amount';
                }
                return null;
              },
            ),
            const SizedBox(height: 8),
            Text('🔔 Alerts at 70%, 90% & 100% — even when app is closed',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppTheme.textLight)),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: AppTheme.textMedium))),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              await _budgetService
                  .setBudget(double.parse(controller.text.trim()));
              _budgetAlertService.resetAlerts();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: Text('Save',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  // ── Review workflow: confirm / reject low-confidence transactions ────────────
  Future<void> _showReviewDialog(Expense expense) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.help_outline_rounded,
                color: Color(0xFFF59E0B), size: 18),
          ),
          const SizedBox(width: 8),
          const Flexible(
            child: Text('Review Transaction',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
          ),
        ]),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _reviewRow('Merchant', expense.merchant),
              _reviewRow('Amount', '₹${expense.amount.toStringAsFixed(2)}'),
              _reviewRow('Category', expense.category),
              _reviewRow('Date',
                  '${expense.date.day}/${expense.date.month}/${expense.date.year}'),
              if (expense.bank != null) _reviewRow('Bank', expense.bank!),
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8)),
                child: Text(
                  'Confidence: ${expense.confidence}% — Please verify this transaction',
                  style: GoogleFonts.poppins(
                      fontSize: 11, color: const Color(0xFFF59E0B)),
                ),
              ),
            ]),
        actions: [
          TextButton(
            onPressed: () async {
              await _repository.rejectExpense(expense.id!);
              await _loadPiggyBank();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text('❌ Reject',
                style: GoogleFonts.poppins(
                    color: AppTheme.errorRed, fontWeight: FontWeight.w600)),
          ),
          ElevatedButton(
            onPressed: () async {
              await _repository.confirmExpense(expense.id!);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.successGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: Text('✅ Confirm',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _reviewRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppTheme.textMedium)),
          ),
          Flexible(
            child: Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ]),
      );

  @override
  void dispose() {
    _animController.dispose();
    _expensesSub.cancel();
    _categorySub.cancel();
    _totalSub.cancel();
    _reviewSub.cancel();
    super.dispose();
  }

  // ── Build ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final email = _user?.email ?? 'Student';
    final displayName = _capitalize(email.split('@').first);

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: FadeTransition(
        opacity: _fadeAnim,
        child: CustomScrollView(
          slivers: [
            // ── App Bar ──────────────────────────────────────────────────────
            SliverAppBar(
              expandedHeight: 130,
              pinned: true,
              automaticallyImplyLeading: false,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  decoration:
                      const BoxDecoration(gradient: AppTheme.primaryGradient),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Welcome back,',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      color:
                                          Colors.white.withValues(alpha: 0.8))),
                              Text(displayName,
                                  style: GoogleFonts.poppins(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white)),
                              Text('Track your UPI expenses',
                                  style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color:
                                          Colors.white.withValues(alpha: 0.7))),
                            ],
                          ),
                          Row(children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                                border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.5)),
                              ),
                              child: Center(
                                child: Text(
                                  displayName.isNotEmpty
                                      ? displayName[0].toUpperCase()
                                      : 'S',
                                  style: GoogleFonts.poppins(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white),
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _handleSignOut,
                              icon: const Icon(Icons.logout_rounded,
                                  color: Colors.white),
                              tooltip: 'Sign Out',
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              backgroundColor: AppTheme.primaryBlue,
            ),

            // ── Content ───────────────────────────────────────────────────────
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Quick Actions ──────────────────────────────────────────
                  Text('Quick Actions',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark)),
                  const SizedBox(height: 12),
                  Row(children: [
                    _quickAction(
                      icon: Icons.add_circle_outline_rounded,
                      label: 'Add\nExpense',
                      color: const Color(0xFFFF6B6B),
                      onTap: () {},
                    ),
                    const SizedBox(width: 10),
                    _quickAction(
                      icon: Icons.pie_chart_outline_rounded,
                      label: 'Budget\nPlan',
                      color: const Color(0xFF8B5CF6),
                      onTap: _showSetBudgetDialog,
                    ),
                    const SizedBox(width: 10),
                    _quickAction(
                      icon: _syncing ? Icons.sync_rounded : Icons.sms_outlined,
                      label: _syncing ? 'Syncing\n...' : 'Sync\nUPI',
                      color: const Color(0xFF0EA5E9),
                      onTap: _syncing ? () {} : () => _syncSms(),
                    ),
                    const SizedBox(width: 10),
                    _quickAction(
                      icon: Icons.bar_chart_rounded,
                      label: 'Reports',
                      color: const Color(0xFFF59E0B),
                      onTap: () {},
                    ),
                  ]),
                  const SizedBox(height: 22),

                  // ── Pending Review banner ──────────────────────────────────
                  if (_pendingReview.isNotEmpty) ...[
                    _buildReviewBanner(),
                    const SizedBox(height: 20),
                  ],

                  // ── Budget Card ────────────────────────────────────────────
                  Text('Budget Tracker',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark)),
                  const SizedBox(height: 10),
                  BudgetCard(
                    budget: _budget,
                    spent: _monthlySpent,
                    onSetBudget: _showSetBudgetDialog,
                  ),
                  const SizedBox(height: 22),

                  // ── Piggy Bank Card ────────────────────────────────────────
                  Text('Piggy Bank Savings',
                      style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textDark)),
                  const SizedBox(height: 10),
                  PiggyBankCard(
                    totalSaved: _piggyTotal,
                    savingsCount: _piggyCount,
                    currentMode: _piggyBank.mode,
                    percentage: _piggyBank.percentage,
                    fixedAmount: _piggyBank.fixedAmount,
                    onModeChanged: (mode) async {
                      await _piggyBank.updateSettings(mode: mode);
                      await _piggyBank.recalculateCurrentMonth();
                      await _loadPiggyBank();
                      if (mounted) setState(() {});
                    },
                    onPercentageChanged: (pct) async {
                      await _piggyBank.updateSettings(
                        mode: SavingMode.percent,
                        percentage: pct,
                      );
                      await _piggyBank.recalculateCurrentMonth();
                      await _loadPiggyBank();
                      if (mounted) setState(() {});
                    },
                  ),
                  const SizedBox(height: 22),

                  // ── This Month Expenses card ───────────────────────────────
                  _buildMonthlyCard(),
                  const SizedBox(height: 22),

                  // ── Category Breakdown ─────────────────────────────────────
                  if (_categories.isNotEmpty) ...[
                    CategoryBreakdownCard(
                      breakdown: _categories,
                      totalSpent: _monthlySpent,
                    ),
                    const SizedBox(height: 22),
                  ],

                  // ── Transaction List ───────────────────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('UPI Transactions',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textDark)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('${_expenses.length} this month',
                            style: GoogleFonts.poppins(
                                fontSize: 10,
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.w500)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  if (_expenses.isEmpty)
                    _buildEmptyState()
                  else
                    ..._expenses.take(15).map(_buildTransactionTile),

                  const SizedBox(height: 32),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Review Banner ─────────────────────────────────────────────────────────────
  Widget _buildReviewBanner() {
    return GestureDetector(
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (ctx) => DraggableScrollableSheet(
            initialChildSize: 0.6,
            maxChildSize: 0.9,
            minChildSize: 0.4,
            expand: false,
            builder: (_, controller) => Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(children: [
                Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2))),
                Text('Needs Review',
                    style: GoogleFonts.poppins(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                Text('Low-confidence transactions — tap to confirm or reject',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppTheme.textMedium)),
                const SizedBox(height: 14),
                Expanded(
                  child: ListView(controller: controller, children: [
                    ..._pendingReview.map((e) => ListTile(
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF59E0B)
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.help_outline_rounded,
                                color: Color(0xFFF59E0B), size: 18),
                          ),
                          title: Text(e.merchant,
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          subtitle: Text(
                              '${e.category} · ${e.confidence}% confidence',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: AppTheme.textMedium)),
                          trailing: Text('₹${e.amount.toStringAsFixed(0)}',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.errorRed)),
                          onTap: () {
                            Navigator.pop(ctx);
                            _showReviewDialog(e);
                          },
                        )),
                  ]),
                ),
              ]),
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.4)),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${_pendingReview.length} transaction${_pendingReview.length > 1 ? 's' : ''} need your review',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: const Color(0xFF92400E)),
            ),
          ),
          Text('Review →',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: const Color(0xFFF59E0B),
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  // ── Monthly spending summary ───────────────────────────────────────────────────
  Widget _buildMonthlyCard() {
    final now = DateTime.now();
    final remaining = (_budget ?? 0) - _monthlySpent;
    final hasBudget = _budget != null && _budget! > 0;

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
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_monthName(now.month)} Expenses',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textDark)),
            Text('From UPI transactions only',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppTheme.textMedium)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('₹${_monthlySpent.toStringAsFixed(0)}',
              style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFFF6B6B))),
          if (hasBudget)
            Text(
                remaining >= 0
                    ? '₹${remaining.toStringAsFixed(0)} left'
                    : '₹${(-remaining).toStringAsFixed(0)} over',
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: remaining >= 0
                        ? AppTheme.successGreen
                        : AppTheme.errorRed)),
        ]),
      ]),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────────
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03), blurRadius: 8)
          ]),
      child: Column(children: [
        Icon(Icons.sms_outlined, size: 44, color: AppTheme.textLight),
        const SizedBox(height: 10),
        Text('No UPI transactions this month',
            style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.textDark)),
        const SizedBox(height: 6),
        Text(
            'The app auto-reads your UPI debit SMS.\nGrant SMS permission to start tracking.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 12, color: AppTheme.textMedium, height: 1.5)),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: () => _syncSms(),
          icon: const Icon(Icons.sms_rounded, size: 16),
          label: Text('Scan SMS Now',
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w500)),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.primaryBlue,
            side: BorderSide(color: AppTheme.primaryBlue),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
        ),
      ]),
    );
  }

  // ── Transaction tile ───────────────────────────────────────────────────────────
  Widget _buildTransactionTile(Expense e) {
    final color = AppTheme.errorRed;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(9),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.arrow_downward_rounded, color: color, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(e.merchant,
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: AppTheme.textDark),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('UPI',
                    style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.primaryBlue)),
              ),
              if (e.bank != null) ...[
                const SizedBox(width: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(e.bank!,
                      style: GoogleFonts.poppins(
                          fontSize: 9, color: AppTheme.textMedium)),
                ),
              ],
            ]),
            Text(e.category,
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppTheme.textMedium)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('-₹${e.amount.toStringAsFixed(0)}',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, fontSize: 14, color: color)),
          Text('${e.date.day}/${e.date.month}/${e.date.year}',
              style:
                  GoogleFonts.poppins(fontSize: 10, color: AppTheme.textLight)),
        ]),
      ]),
    );
  }

  // ── Quick action tile ─────────────────────────────────────────────────────────
  Widget _quickAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4))
            ],
          ),
          child: Column(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textDark,
                    height: 1.3)),
          ]),
        ),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _monthName(int m) {
    const n = [
      '',
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December'
    ];
    return n[m];
  }
}
