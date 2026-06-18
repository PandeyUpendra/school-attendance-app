import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../models/expense.dart';
import '../../models/fee.dart';
import '../../services/auth_service.dart';
import '../../services/expense_service.dart';
import '../../theme.dart';
import '../../shared/utils/app_logger.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/utils/pdf_theme.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/school_settings_provider.dart';
import '../../shared/utils/pdf_branding_helper.dart';
import '../../shared/widgets/premium_feature_gate.dart';

class ProfitLossScreen extends StatefulWidget {
  const ProfitLossScreen({super.key});

  @override
  State<ProfitLossScreen> createState() => _ProfitLossScreenState();
}

class _MonthlyData {
  final int year;
  final int month;
  final String monthName;
  final double income;
  final double expenses;
  final double netProfit;
  final Map<String, double> incomeByMode;
  final Map<String, double> expenseByCategory;
  final List<Payment> rawPayments;
  final List<Expense> rawExpenses;

  _MonthlyData({
    required this.year,
    required this.month,
    required this.monthName,
    required this.income,
    required this.expenses,
    required this.netProfit,
    required this.incomeByMode,
    required this.expenseByCategory,
    required this.rawPayments,
    required this.rawExpenses,
  });
}

class _ProfitLossScreenState extends State<ProfitLossScreen> {
  bool _loading = true;
  List<_MonthlyData> _monthsData = [];
  _MonthlyData? _selectedMonth;
  String? _errorMessage;

  static const _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final sid = AuthService.currentSchoolId;
      final now = DateTime.now();
      
      // Calculate start date (6 months ago, first day of that month)
      final startOfPeriod = DateTime(now.year, now.month - 5, 1);
      final cutoff = Timestamp.fromDate(startOfPeriod);

      // Fan out queries in parallel
      final expensesFuture = ExpenseService().getExpenses(start: startOfPeriod);
      final paymentsFuture = FirebaseFirestore.instance
          .collectionGroup('payments')
          .where('schoolId', isEqualTo: sid)
          .where('paidOn', isGreaterThanOrEqualTo: cutoff)
          .get();

      final results = await Future.wait([expensesFuture, paymentsFuture]);
      final allExpenses = results[0] as List<Expense>;
      final paymentsSnap = results[1] as QuerySnapshot;
      
      final allPayments = paymentsSnap.docs
          .map((d) => Payment.fromDoc(d.id, Map<String, dynamic>.from(d.data() as Map)))
          .where((p) => !p.reversed) // Exclude reversed payments
          .toList();

      // Aggregate into 6 individual months
      final List<_MonthlyData> aggregated = [];
      for (int i = 5; i >= 0; i--) {
        final targetMonthDate = DateTime(now.year, now.month - i, 1);
        final yr = targetMonthDate.year;
        final m = targetMonthDate.month;
        final name = '${_monthNames[m - 1]} $yr';

        // Filter transactions for this month
        final monthPayments = allPayments.where((p) => p.paidOn.year == yr && p.paidOn.month == m).toList();
        final monthExpenses = allExpenses.where((e) => e.expenseDate.year == yr && e.expenseDate.month == m).toList();

        // Income aggregation
        double income = 0;
        final Map<String, double> incomeByMode = {
          'Cash': 0.0,
          'UPI': 0.0,
          'Bank': 0.0,
          'Cheque': 0.0,
        };
        for (final p in monthPayments) {
          income += p.amount;
          final mode = p.mode;
          incomeByMode[mode] = (incomeByMode[mode] ?? 0.0) + p.amount;
        }

        // Expense aggregation
        double expenses = 0;
        final Map<String, double> expenseByCategory = {};
        for (final e in monthExpenses) {
          expenses += e.amount;
          final cat = e.category;
          expenseByCategory[cat] = (expenseByCategory[cat] ?? 0.0) + e.amount;
        }

        aggregated.add(_MonthlyData(
          year: yr,
          month: m,
          monthName: name,
          income: income,
          expenses: expenses,
          netProfit: income - expenses,
          incomeByMode: incomeByMode,
          expenseByCategory: expenseByCategory,
          rawPayments: monthPayments,
          rawExpenses: monthExpenses,
        ));
      }

      setState(() {
        _monthsData = aggregated;
        // Default select the last month in list (which is current month)
        _selectedMonth = aggregated.last;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.e('ProfitLossScreen', 'Failed to load P&L data: $e', e, st);
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = e.toString();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load P&L: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PremiumFeatureGate(
      feature: 'profit_loss',
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: const Text('Profit & Loss Summary'),
          backgroundColor: AppTheme.primaryDark,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? _buildErrorState()
                : _monthsData.isEmpty
                    ? _buildEmptyState()
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildMonthSelector(),
                        const SizedBox(height: 16),
                        if (_selectedMonth != null) ...[
                          _buildSummaryMetrics(_selectedMonth!),
                          const SizedBox(height: 16),
                          _buildBreakdownSection(_selectedMonth!),
                          const SizedBox(height: 16),
                        ],
                        _buildTrendSection(),
                        const SizedBox(height: 80),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.bar_chart_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No transaction data found for the last 6 months', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppTheme.danger),
            const SizedBox(height: 16),
            Text(
              'Failed to load P&L data:\n$_errorMessage',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthSelector() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Focused Month:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
            DropdownButton<_MonthlyData>(
              value: _selectedMonth,
              underline: const SizedBox(),
              items: _monthsData.map((data) {
                return DropdownMenuItem(
                  value: data,
                  child: Text(
                    data.monthName,
                    style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                );
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _selectedMonth = v);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryMetrics(_MonthlyData data) {
    final isProfit = data.netProfit >= 0;
    
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildMetricCard(
                label: 'TOTAL INCOME',
                value: CurrencyUtils.formatRupees(data.income),
                color: AppTheme.success,
                icon: Icons.trending_up,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMetricCard(
                label: 'TOTAL EXPENSES',
                value: CurrencyUtils.formatRupees(data.expenses),
                color: AppTheme.danger,
                icon: Icons.trending_down,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppTheme.border),
            borderRadius: BorderRadius.circular(12),
          ),
          color: isProfit ? AppTheme.successLight : AppTheme.dangerLight,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  isProfit ? Icons.check_circle_outline : Icons.error_outline,
                  color: isProfit ? AppTheme.success : AppTheme.danger,
                  size: 32,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isProfit ? 'NET PROFIT' : 'NET LOSS',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isProfit ? AppTheme.success : AppTheme.danger,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyUtils.formatRupees(data.netProfit.abs(), showDecimals: true),
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: isProfit ? AppTheme.success : AppTheme.danger,
                        ),
                      ),
                    ],
                  ),
                ),
                ElevatedButton.icon(
                  icon: const Icon(Icons.picture_as_pdf),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isProfit ? AppTheme.primary : Colors.grey.shade800,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => _exportPLReport(data),
                  label: const Text('Export PDF'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.textSecondary, letterSpacing: 1.1),
                ),
                Icon(icon, color: color, size: 20),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownSection(_MonthlyData data) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Income Breakdown
        Expanded(
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: AppTheme.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Income by Mode',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primary),
                  ),
                  const Divider(height: 16),
                  ...data.incomeByMode.entries.map((e) {
                    final percentage = data.income > 0 ? (e.value / data.income) : 0.0;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                              Text(CurrencyUtils.formatRupees(e.value), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: percentage,
                              backgroundColor: Colors.grey.shade100,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.success),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Expense Breakdown
        Expanded(
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              side: const BorderSide(color: AppTheme.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Expenses by Category',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.primary),
                  ),
                  const Divider(height: 16),
                  if (data.expenseByCategory.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text('No expenses logged', style: TextStyle(color: Colors.grey, fontSize: 12))),
                    )
                  else
                    ...data.expenseByCategory.entries.map((e) {
                      final percentage = data.expenses > 0 ? (e.value / data.expenses) : 0.0;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    e.key,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(CurrencyUtils.formatRupees(e.value), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(2),
                              child: LinearProgressIndicator(
                                value: percentage,
                                backgroundColor: Colors.grey.shade100,
                                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.danger),
                                minHeight: 6,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTrendSection() {
    double maxVal = 1000.0;
    for (final md in _monthsData) {
      if (md.income > maxVal) maxVal = md.income;
      if (md.expenses > maxVal) maxVal = md.expenses;
    }
    
    // Grid intervals
    final yInterval = (maxVal / 4).ceilToDouble().clamp(100.0, 5000000.0);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '6-Month Financial Trend',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _legendIndicator(color: AppTheme.success, label: 'Income'),
                const SizedBox(width: 16),
                _legendIndicator(color: AppTheme.danger, label: 'Expenses'),
              ],
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 220,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxVal * 1.15,
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.grey.shade800,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          CurrencyUtils.formatRupees(rod.toY),
                          const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (val, meta) {
                          final idx = val.toInt();
                          if (idx >= 0 && idx < _monthsData.length) {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _monthsData[idx].monthName.split(' ')[0],
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            );
                          }
                          return const SizedBox();
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 46,
                        getTitlesWidget: (val, meta) {
                          if (val == 0) return const Text('0', style: TextStyle(fontSize: 9));
                          if (val >= 100000) {
                            return Text('₹${(val / 100000).toStringAsFixed(1)}L', style: const TextStyle(fontSize: 9));
                          }
                          if (val >= 1000) {
                            return Text('₹${(val / 1000).toStringAsFixed(0)}k', style: const TextStyle(fontSize: 9));
                          }
                          return Text('₹${val.toStringAsFixed(0)}', style: const TextStyle(fontSize: 9));
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: yInterval,
                    getDrawingHorizontalLine: (value) => FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: List.generate(_monthsData.length, (index) {
                    final md = _monthsData[index];
                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(toY: md.income, color: AppTheme.success, width: 10, borderRadius: BorderRadius.circular(4)),
                        BarChartRodData(toY: md.expenses, color: AppTheme.danger, width: 10, borderRadius: BorderRadius.circular(4)),
                      ],
                    );
                  }),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendIndicator({required Color color, required String label}) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }

  Future<void> _exportPLReport(_MonthlyData data) async {
    final settings = Provider.of<SchoolSettingsProvider>(context, listen: false);
    final branding = await PdfBrandingHelper.load(
      schoolName: settings.schoolName,
      schoolLogoUrl: settings.schoolLogo,
    );

    final pdf = pw.Document();
    
    // Load logo if exists or draw a nice text title
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            // Header
            PdfBrandingHelper.buildHeader(branding),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('MONTHLY FINANCIAL REPORT', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: PdfTheme.primary)),
                    pw.Text('Profit & Loss Statement for ${data.monthName}', style: const pw.TextStyle(fontSize: 12, color: PdfTheme.textLight)),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Exported: ${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}', style: const pw.TextStyle(fontSize: 9, color: PdfTheme.textLight)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 8),
            pw.Divider(thickness: 1, color: PdfTheme.primaryLight),
            pw.SizedBox(height: 12),

            // Summary Table
            pw.Text('Executive Summary', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfTheme.primary)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfTheme.grey200),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfTheme.primaryTint),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Metric', style: pw.TextStyle(fontWeight: pw.FontWeight.bold))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Total Income (Fees Collected)')),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(CurrencyUtils.formatRupees(data.income), textAlign: pw.TextAlign.right)),
                  ],
                ),
                pw.TableRow(
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text('Total Operating Expenses')),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(CurrencyUtils.formatRupees(data.expenses), textAlign: pw.TextAlign.right)),
                  ],
                ),
                pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: data.netProfit >= 0 ? PdfTheme.successTint : PdfTheme.dangerTint,
                  ),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(data.netProfit >= 0 ? 'Net Profit' : 'Net Loss', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: data.netProfit >= 0 ? PdfTheme.success : PdfTheme.danger))),
                    pw.Padding(padding: const pw.EdgeInsets.all(8), child: pw.Text(CurrencyUtils.formatRupees(data.netProfit), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: data.netProfit >= 0 ? PdfTheme.success : PdfTheme.danger), textAlign: pw.TextAlign.right)),
                  ],
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // Breakdowns
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Income Breakdown', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfTheme.primary)),
                      pw.SizedBox(height: 6),
                      ...data.incomeByMode.entries.map((e) {
                        return pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(vertical: 4),
                          child: pw.Row(
                            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                            children: [
                              pw.Text(e.key, style: const pw.TextStyle(fontSize: 10)),
                              pw.Text(CurrencyUtils.formatRupees(e.value), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                pw.SizedBox(width: 24),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Expense Breakdown', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfTheme.primary)),
                      pw.SizedBox(height: 6),
                      if (data.expenseByCategory.isEmpty)
                        pw.Text('No expenses logged.', style: const pw.TextStyle(fontSize: 10, color: PdfTheme.textLight))
                      else
                        ...data.expenseByCategory.entries.map((e) {
                          return pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(vertical: 4),
                            child: pw.Row(
                              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                              children: [
                                pw.Text(e.key, style: const pw.TextStyle(fontSize: 10)),
                                pw.Text(CurrencyUtils.formatRupees(e.value), style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 24),

            // Detailed Expenses List
            pw.Text('Detailed Expenses', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: PdfTheme.primary)),
            pw.SizedBox(height: 8),
            if (data.rawExpenses.isEmpty)
              pw.Text('No expenses recorded in this period.', style: const pw.TextStyle(fontSize: 10, color: PdfTheme.textLight))
            else
              pw.Table(
                border: pw.TableBorder.all(color: PdfTheme.grey200),
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: PdfTheme.grey50),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Date', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Category', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Description', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Payment Mode', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Amount', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9), textAlign: pw.TextAlign.right)),
                    ],
                  ),
                  ...data.rawExpenses.map((exp) {
                    return pw.TableRow(
                      children: [
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('${exp.expenseDate.day}/${exp.expenseDate.month}', style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(exp.category, style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(exp.description, style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(exp.paymentMode, style: const pw.TextStyle(fontSize: 9))),
                        pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(CurrencyUtils.formatRupees(exp.amount), style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.right)),
                      ],
                    );
                  }),
                ],
              ),
          ];
        },
      ),
    );

    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'PL_Statement_${data.monthName.replaceAll(' ', '_')}.pdf',
      );
    } catch (e) {
      AppLogger.e('ProfitLossScreen', 'PDF printing failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to print PDF: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }
}
