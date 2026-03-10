import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../database/local_database.dart';
import '../models/expense_model.dart';
import '../theme/app_theme.dart';

/// Reports screen — visualises spending via pie chart, bar chart,
/// two-month comparison and spending insights.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  final _db = LocalDatabase.instance;

  // Selected month state
  DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);

  // Current month data
  Map<String, double> _current = {};
  double _currentTotal = 0;
  List<Expense> _monthlyExpenses = [];

  // Previous month data
  Map<String, double> _previous = {};
  double _previousTotal = 0;

  bool _loading = true;
  int _touchedPieIndex = -1;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;

  // ── Category constants ───────────────────────────────────────────────────────

  static const _knownCategories = [
    'Food',
    'Travel',
    'Shopping',
    'Education',
    'Others',
  ];

  static const _categoryColors = <String, Color>{
    'Food': Color(0xFFFF6B6B),
    'Travel': Color(0xFF0EA5E9),
    'Shopping': Color(0xFF0EA5E9),
    'Education': Color(0xFF6366F1),
    'Others': Color(0xFF94A3B8),
  };

  static const _categoryIcons = <String, IconData>{
    'Food': Icons.restaurant_rounded,
    'Travel': Icons.directions_car_rounded,
    'Shopping': Icons.shopping_bag_rounded,
    'Education': Icons.school_rounded,
    'Others': Icons.category_rounded,
  };

  // Map raw DB categories → canonical display categories
  static String _normalise(String raw) {
    const map = {
      'Transport': 'Travel',
      'travel': 'Travel',
      'food': 'Food',
      'shopping': 'Shopping',
      'education': 'Education',
      'Entertainment': 'Others',
      'Utilities': 'Others',
      'Health': 'Others',
      'Transfers': 'Others',
      'Other': 'Others',
    };
    return map[raw] ?? (_knownCategories.contains(raw) ? raw : 'Others');
  }

  static Map<String, double> _normalisedBreakdown(Map<String, double> raw) {
    final result = <String, double>{};
    for (final entry in raw.entries) {
      final key = _normalise(entry.key);
      result[key] = (result[key] ?? 0) + entry.value;
    }
    return result;
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _fadeAnim = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: _animController, curve: Curves.easeOut));
    _loadData();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final curMonthRaw = _selectedMonth;
    final prevMonthRaw = DateTime(curMonthRaw.year, curMonthRaw.month - 1, 1);

    final curRaw = await _db.getCategoryBreakdown(curMonthRaw);
    final prevRaw = await _db.getCategoryBreakdown(prevMonthRaw);
    final curTotal = await _db.getMonthlyTotal(curMonthRaw);
    final prevTotal = await _db.getMonthlyTotal(prevMonthRaw);

    // Fetch individual expenses for the selected month
    final expenses = await _db.getMonthlyExpenses(curMonthRaw);

    if (mounted) {
      setState(() {
        _current = _normalisedBreakdown(curRaw);
        _previous = _normalisedBreakdown(prevRaw);
        _currentTotal = curTotal;
        _previousTotal = prevTotal;
        _monthlyExpenses = expenses;
        _loading = false;
      });
      _animController.forward();
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  String _monthName(DateTime d) {
    const names = [
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
      'December',
    ];
    return names[d.month];
  }

  String get _currentMonthName =>
      _monthName(_selectedMonth) + ' ${_selectedMonth.year}';
  String get _prevMonthName {
    final d = DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1);
    return _monthName(d);
  }

  // Average per category across two months
  Map<String, double> get _averages {
    final all = <String, double>{};
    for (final cat in _knownCategories) {
      final cur = _current[cat] ?? 0;
      final prev = _previous[cat] ?? 0;
      if (cur > 0 || prev > 0) {
        all[cat] = (cur + prev) / 2;
      }
    }
    return all;
  }

  String get _topCategory {
    if (_averages.isEmpty) return 'Shopping';
    return _averages.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.backgroundDark : AppTheme.backgroundLight,
      body: Column(
        children: [
          _buildAppBar(),
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                    color: AppTheme.skyBlueDark,
                  ))
                : FadeTransition(
                    opacity: _fadeAnim,
                    child: RefreshIndicator(
                      onRefresh: _loadData,
                      color: AppTheme.skyBlueDark,
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
                        children: [
                          _buildPieChartCard(),
                          const SizedBox(height: 20),
                          _buildBarChartCard(),
                          const SizedBox(height: 20),
                          _buildMonthComparisonCard(),
                          const SizedBox(height: 20),
                          _buildInsightsCard(),
                          const SizedBox(height: 20),
                          _buildExpenseList(),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── App bar ──────────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return Container(
      decoration: const BoxDecoration(gradient: AppTheme.primaryGradient),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 24, 18),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reports',
                    style: GoogleFonts.poppins(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Colors.white),
                  ),
                  Text(
                    'Spending analysis & insights',
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.75)),
                  ),
                ],
              ),
              const Spacer(),
              _buildMonthSelector(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    final now = DateTime.now();
    // Generate the 12 months for the current year (Jan to Dec)
    final months = List.generate(12, (i) {
      return DateTime(now.year, i + 1, 1);
    });

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<DateTime>(
          value: _selectedMonth,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: Colors.white, size: 20),
          dropdownColor: AppTheme.skyBlueDark,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          onChanged: (DateTime? newValue) {
            if (newValue != null && newValue != _selectedMonth) {
              setState(() {
                _selectedMonth = newValue;
                _loading = true; // Show loading while fetching new data
              });
              _loadData();
            }
          },
          items: months.map<DropdownMenuItem<DateTime>>((DateTime date) {
            final label = '${_monthName(date)} ${date.year}';
            return DropdownMenuItem<DateTime>(
              value: date,
              child: Text(label),
            );
          }).toList(),
        ),
      ),
    );
  }

  // ── Card wrapper ─────────────────────────────────────────────────────────────

  Widget _card(
      {required String title,
      required IconData icon,
      required Color iconColor,
      required Widget child}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppTheme.cardDark : Colors.white;
    final textCol = isDark ? AppTheme.textDarkMode : AppTheme.textDark;
    final shadowCol = isDark
        ? Colors.black.withValues(alpha: 0.3)
        : Colors.black.withValues(alpha: 0.06);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: shadowCol, blurRadius: 14, offset: const Offset(0, 4)),
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
                    color: iconColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 10),
              Text(title,
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textCol)),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  // ── Feature 1: Pie Chart ─────────────────────────────────────────────────────

  Widget _buildPieChartCard() {
    final hasData = _current.isNotEmpty && _currentTotal > 0;

    return _card(
      title: 'Monthly Expense Breakdown',
      icon: Icons.pie_chart_rounded,
      iconColor: const Color(0xFF0EA5E9),
      child: Column(
        children: [
          // Total
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
            decoration: BoxDecoration(
              gradient: AppTheme.primaryGradient,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Total Spending – $_currentMonthName',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.9))),
                Text(
                  '₹${_currentTotal.toStringAsFixed(0)}',
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (!hasData)
            _emptyState('No expenses recorded this month')
          else ...[
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  pieTouchData: PieTouchData(
                    touchCallback: (event, response) {
                      setState(() {
                        if (!event.isInterestedForInteractions ||
                            response == null ||
                            response.touchedSection == null) {
                          _touchedPieIndex = -1;
                          return;
                        }
                        _touchedPieIndex =
                            response.touchedSection!.touchedSectionIndex;
                      });
                    },
                  ),
                  startDegreeOffset: -90,
                  sectionsSpace: 3,
                  centerSpaceRadius: 44,
                  sections: _buildPieSections(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Legend
            ..._knownCategories.map((cat) {
              final amount = _current[cat] ?? 0;
              if (amount == 0) return const SizedBox.shrink();
              final pct = _currentTotal > 0 ? amount / _currentTotal : 0.0;
              final color = _categoryColors[cat]!;
              final icon = _categoryIcons[cat]!;
              return _legendRow(cat, amount, pct, color, icon);
            }),
          ],
        ],
      ),
    );
  }

  List<PieChartSectionData> _buildPieSections() {
    final sections = <PieChartSectionData>[];
    int idx = 0;
    for (final cat in _knownCategories) {
      final amount = _current[cat] ?? 0;
      if (amount == 0) {
        idx++;
        continue;
      }
      final pct = _currentTotal > 0 ? amount / _currentTotal * 100 : 0.0;
      final isTouched = idx == _touchedPieIndex;
      final color = _categoryColors[cat]!;
      sections.add(PieChartSectionData(
        color: color,
        value: amount,
        title: '${pct.toStringAsFixed(0)}%',
        radius: isTouched ? 70 : 58,
        titleStyle: GoogleFonts.poppins(
          fontSize: isTouched ? 13 : 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        badgeWidget: isTouched
            ? Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                          color: color.withValues(alpha: 0.4),
                          blurRadius: 6,
                          offset: const Offset(0, 2))
                    ]),
                child: Text(cat,
                    style: GoogleFonts.poppins(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
              )
            : null,
        badgePositionPercentageOffset: 1.3,
      ));
      idx++;
    }
    return sections;
  }

  Widget _legendRow(
      String label, double amount, double pct, Color color, IconData icon) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textCol = isDark ? AppTheme.textDarkMode : AppTheme.textDark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
                '$label – ₹${amount.toStringAsFixed(0)} (${(pct * 100).toStringAsFixed(0)}%)',
                style: GoogleFonts.poppins(
                    fontSize: 12, fontWeight: FontWeight.w500, color: textCol)),
          ),
        ],
      ),
    );
  }

  // ── Feature 2: Bar Chart ─────────────────────────────────────────────────────

  Widget _buildBarChartCard() {
    final hasData = _current.values.any((v) => v > 0);

    return _card(
      title: 'Category Comparison',
      icon: Icons.bar_chart_rounded,
      iconColor: const Color(0xFF0EA5E9),
      child: hasData
          ? Column(
              children: [
                SizedBox(
                  height: 200,
                  child: BarChart(
                    BarChartData(
                      alignment: BarChartAlignment.spaceAround,
                      maxY: _current.values.isEmpty
                          ? 100
                          : (_current.values.reduce(math.max) * 1.2),
                      barTouchData: BarTouchData(
                        enabled: true,
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipColor: (group) => const Color(0xFF1A1A2E),
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final cat = _knownCategories[groupIndex];
                            return BarTooltipItem(
                              '₹${rod.toY.toStringAsFixed(0)}',
                              GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12),
                              children: [
                                TextSpan(
                                  text: '\n$cat',
                                  style: GoogleFonts.poppins(
                                      color:
                                          Colors.white.withValues(alpha: 0.7),
                                      fontSize: 10),
                                )
                              ],
                            );
                          },
                        ),
                      ),
                      titlesData: FlTitlesData(
                        show: true,
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            getTitlesWidget: (value, meta) {
                              final idx = value.toInt();
                              if (idx < 0 || idx >= _knownCategories.length) {
                                return const SizedBox.shrink();
                              }
                              final abbrevs = [
                                'Food',
                                'Travel',
                                'Shop',
                                'Edu',
                                'Other'
                              ];
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(abbrevs[idx],
                                    style: GoogleFonts.poppins(
                                        fontSize: 9,
                                        color: AppTheme.textMedium,
                                        fontWeight: FontWeight.w500)),
                              );
                            },
                            reservedSize: 24,
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 44,
                            getTitlesWidget: (value, meta) {
                              if (value == 0) return const SizedBox.shrink();
                              return Text(
                                  value >= 1000
                                      ? '₹${(value / 1000).toStringAsFixed(1)}k'
                                      : '₹${value.toInt()}',
                                  style: GoogleFonts.poppins(
                                      fontSize: 9, color: AppTheme.textLight));
                            },
                          ),
                        ),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (value) => const FlLine(
                            color: Color(0xFFE5E7EB), strokeWidth: 1),
                      ),
                      borderData: FlBorderData(show: false),
                      barGroups: _buildBarGroups(),
                    ),
                  ),
                ),
              ],
            )
          : _emptyState('No expense data to display'),
    );
  }

  List<BarChartGroupData> _buildBarGroups() {
    final groups = <BarChartGroupData>[];
    for (int i = 0; i < _knownCategories.length; i++) {
      final cat = _knownCategories[i];
      final value = _current[cat] ?? 0;
      final color = _categoryColors[cat]!;
      groups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: value,
            gradient: LinearGradient(
              colors: [color.withValues(alpha: 0.7), color],
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
            ),
            width: 32,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: (_current.values.isEmpty
                      ? 100
                      : _current.values.reduce(math.max)) *
                  1.2,
              color: color.withValues(alpha: 0.06),
            ),
          ),
        ],
      ));
    }
    return groups;
  }

  // ── Feature 3: Two-Month Comparison ─────────────────────────────────────────

  Widget _buildMonthComparisonCard() {
    return _card(
      title: 'Monthly Comparison',
      icon: Icons.compare_arrows_rounded,
      iconColor: const Color(0xFFF59E0B),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                  child: _monthSummaryChip(
                      _prevMonthName, _previousTotal, const Color(0xFF0EA5E9))),
              const SizedBox(width: 12),
              Expanded(
                  child: _monthSummaryChip(_currentMonthName, _currentTotal,
                      const Color(0xFFFF6B6B))),
            ],
          ),
          const SizedBox(height: 14),
          // Comparison bar
          if (_previousTotal > 0 || _currentTotal > 0) ...[
            _comparisonBar(),
            const SizedBox(height: 10),
            // Delta message
            Builder(builder: (_) {
              final diff = _currentTotal - _previousTotal;
              final isMore = diff > 0;
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: (isMore ? AppTheme.errorRed : AppTheme.successGreen)
                      .withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                        isMore
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 16,
                        color:
                            isMore ? AppTheme.errorRed : AppTheme.successGreen),
                    const SizedBox(width: 6),
                    Text(
                      diff == 0
                          ? 'Same as last month'
                          : isMore
                              ? 'Your spending increased by ₹${diff.abs().toStringAsFixed(0)} compared to last month.'
                              : 'Your spending decreased by ₹${diff.abs().toStringAsFixed(0)} compared to last month.',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isMore
                              ? AppTheme.errorRed
                              : AppTheme.successGreen),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _monthSummaryChip(String month, double total, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(month,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('₹${total.toStringAsFixed(0)}',
              style: GoogleFonts.poppins(
                  fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text('total spent',
              style:
                  GoogleFonts.poppins(fontSize: 10, color: AppTheme.textLight)),
        ],
      ),
    );
  }

  Widget _comparisonBar() {
    final max = math.max(_previousTotal, _currentTotal);
    final prevFrac = max > 0 ? _previousTotal / max : 0.0;
    final curFrac = max > 0 ? _currentTotal / max : 0.0;
    return Column(
      children: [
        _barRow(
            _prevMonthName, prevFrac, const Color(0xFF0EA5E9), _previousTotal),
        const SizedBox(height: 8),
        _barRow(
            _currentMonthName, curFrac, const Color(0xFFFF6B6B), _currentTotal),
      ],
    );
  }

  Widget _barRow(String label, double fraction, Color color, double amount) {
    return Row(
      children: [
        SizedBox(
          width: 54,
          child: Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 10, color: AppTheme.textMedium)),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 10,
              backgroundColor: color.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('₹${amount.toStringAsFixed(0)}',
            style: GoogleFonts.poppins(
                fontSize: 10, fontWeight: FontWeight.w700, color: color)),
      ],
    );
  }

  // ── Feature 4: Spending Insights ─────────────────────────────────────────────

  Widget _buildInsightsCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final top = _topCategory;
    final avgs = _averages;
    final topColor = _categoryColors[top] ?? AppTheme.textDark;
    final topIcon = _categoryIcons[top] ?? Icons.category_rounded;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            topColor.withValues(alpha: 0.06),
            isDark ? AppTheme.cardDark : Colors.white
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: topColor.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4)),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.lightbulb_rounded,
                    color: Color(0xFFF59E0B), size: 18),
              ),
              const SizedBox(width: 10),
              Text('Spending Insights',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textDark)),
            ],
          ),
          const SizedBox(height: 14),

          if (avgs.isEmpty)
            _emptyState('Not enough data for insights')
          else ...[
            // Sub-title
            Text('2-Month Category Average',
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    color: AppTheme.textMedium,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 10),

            // Category averages
            ...avgs.entries.map((e) {
              final cat = e.key;
              final avg = e.value;
              final color = _categoryColors[cat]!;
              final icon = _categoryIcons[cat]!;
              final isTop = cat == top;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: isTop ? color.withValues(alpha: 0.1) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: isTop
                      ? Border.all(color: color.withValues(alpha: 0.3))
                      : null,
                ),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(cat,
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight:
                                  isTop ? FontWeight.w700 : FontWeight.w500,
                              color: isTop ? color : AppTheme.textDark)),
                    ),
                    Text('₹${avg.toStringAsFixed(0)}',
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: color)),
                    if (isTop) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('TOP',
                            style: GoogleFonts.poppins(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ],
                  ],
                ),
              );
            }),

            const SizedBox(height: 8),
            const Divider(),
            const SizedBox(height: 8),

            // Top category highlight
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                      color: topColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20)),
                  child: Icon(topIcon, color: topColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Top Spending Category',
                          style: GoogleFonts.poppins(
                              fontSize: 10, color: AppTheme.textMedium)),
                      Text(top,
                          style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: topColor)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Insight message
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: topColor.withValues(alpha: 0.07),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: topColor.withValues(alpha: 0.2))),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 14, color: topColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You spend most of your money on $top. Consider reducing this category to improve savings.',
                      style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: topColor,
                          fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Shared: empty state ──────────────────────────────────────────────────────

  Widget _emptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 40, color: AppTheme.textLight),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppTheme.textMedium)),
        ],
      ),
    );
  }

  // ── Feature 6: Monthly Expense List ──────────────────────────────────────────

  Widget _buildExpenseList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            'Monthly Expense List',
            style: GoogleFonts.poppins(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).brightness == Brightness.dark
                  ? AppTheme.textDarkMode
                  : AppTheme.textDark,
            ),
          ),
        ),
        if (_monthlyExpenses.isEmpty)
          _emptyState('No expenses found for this month')
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _monthlyExpenses.length,
            separatorBuilder: (ctx, i) => const Divider(height: 1),
            itemBuilder: (ctx, i) {
              final expense = _monthlyExpenses[i];
              final dateStr = DateFormat('MMM d').format(expense.date);
              final cat = _normalise(expense.category);
              final icon = _categoryIcons[cat] ?? Icons.category_rounded;
              final color = _categoryColors[cat] ?? AppTheme.textDark;

              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                title: Text(
                  expense.merchant,
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppTheme.textDarkMode
                        : AppTheme.textDark,
                  ),
                ),
                subtitle: Row(
                  children: [
                    Text(
                      expense.paymentMethod,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppTheme.textMediumDark
                            : AppTheme.textMedium,
                      ),
                    ),
                    Text(
                      ' • $dateStr',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Theme.of(context).brightness == Brightness.dark
                            ? AppTheme.textMediumDark
                            : AppTheme.textMedium,
                      ),
                    ),
                  ],
                ),
                trailing: Text(
                  '₹${expense.amount.toStringAsFixed(0)}',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? AppTheme.textDarkMode
                        : AppTheme.textDark,
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}
