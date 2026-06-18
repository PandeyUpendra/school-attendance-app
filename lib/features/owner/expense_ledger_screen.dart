import '../../l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/expense.dart';
import '../../services/expense_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import '../../shared/utils/currency_utils.dart';
import '../../shared/utils/app_logger.dart';
import '../../shared/widgets/premium_feature_gate.dart';

class ExpenseLedgerScreen extends StatefulWidget {
  const ExpenseLedgerScreen({super.key});

  @override
  State<ExpenseLedgerScreen> createState() => _ExpenseLedgerScreenState();
}

class _ExpenseLedgerScreenState extends State<ExpenseLedgerScreen> {
  final ExpenseService _expenseService = ExpenseService();
  String _selectedCategory = 'All';
  DateTimeRange? _selectedDateRange;
  
  static const List<String> _categories = [
    'Salaries',
    'Rent',
    'Utilities',
    'Maintenance',
    'Stationery',
    'Other'
  ];

  @override
  Widget build(BuildContext context) {
    return PremiumFeatureGate(
      feature: 'expense_tracking',
      child: Scaffold(
        backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('expenseLedger')),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
      ),
      body: StreamBuilder<List<Expense>>(
        stream: _expenseService.watchExpenses(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final allExpenses = snapshot.data ?? [];
          final filteredExpenses = allExpenses.where((e) {
            final matchesCategory = _selectedCategory == 'All' || e.category == _selectedCategory;
            
            bool matchesDate = true;
            if (_selectedDateRange != null) {
              final expDate = DateTime(e.expenseDate.year, e.expenseDate.month, e.expenseDate.day);
              final start = DateTime(_selectedDateRange!.start.year, _selectedDateRange!.start.month, _selectedDateRange!.start.day);
              final end = DateTime(_selectedDateRange!.end.year, _selectedDateRange!.end.month, _selectedDateRange!.end.day);
              matchesDate = !expDate.isBefore(start) && !expDate.isAfter(end);
            }
            
            return matchesCategory && matchesDate;
          }).toList();

          double totalPaise = 0;
          for (final exp in filteredExpenses) {
            totalPaise += exp.amountPaise;
          }
          final totalAmount = totalPaise / 100.0;

          return Column(
            children: [
              _buildSummaryCard(totalAmount, filteredExpenses.length),
              _buildFilterBar(),
              Expanded(
                child: filteredExpenses.isEmpty
                    ? _buildEmptyState()
                    : _buildLedgerList(filteredExpenses),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddExpenseBottomSheet(context),
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add),
        label: Text(context.tr('addExpense')),
      ),
    ),);
  }

  Widget _buildSummaryCard(double total, int count) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primaryMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppTheme.primaryDark.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TOTAL EXPENSES',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            CurrencyUtils.formatRupees(total, showDecimals: true),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.tr('showingTransactionsFiltered').replaceFirst('{count}', count.toString()),
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          // Category filter
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: InputDecoration(
                labelText: context.tr('categoryLabel'),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              items: ['All', ..._categories].map((cat) {
                return DropdownMenuItem(value: cat, child: Text(cat));
              }).toList(),
              onChanged: (v) {
                if (v != null) {
                  setState(() => _selectedCategory = v);
                }
              },
            ),
          ),
          const SizedBox(width: 12),
          // Date range button
          OutlinedButton.icon(
            icon: const Icon(Icons.date_range, size: 16),
            label: Text(
              _selectedDateRange == null
                  ? context.tr('allDates')
                  : '${_selectedDateRange!.start.day}/${_selectedDateRange!.start.month} - ${_selectedDateRange!.end.day}/${_selectedDateRange!.end.month}',
              style: const TextStyle(fontSize: 12),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              side: BorderSide(color: Colors.grey.shade400),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _selectDateRange,
          ),
          if (_selectedDateRange != null) ...[
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.clear, size: 18),
              onPressed: () => setState(() => _selectedDateRange = null),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _selectDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _selectedDateRange,
      builder: (context, child) {
        return Theme(
          data: AppTheme.light.copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.receipt_long_outlined, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            context.tr('noExpensesFound'),
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('changeFiltersLogExpense'),
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerList(List<Expense> expenses) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: expenses.length,
      itemBuilder: (context, index) {
        final exp = expenses[index];
        final date = exp.expenseDate;
        final dateStr = '${date.day} ${months[date.month - 1]} ${date.year}';
        
        IconData catIcon;
        Color catColor;
        switch (exp.category) {
          case 'Salaries':
            catIcon = Icons.people_outline;
            catColor = Colors.blue;
            break;
          case 'Rent':
            catIcon = Icons.home_work_outlined;
            catColor = Colors.orange;
            break;
          case 'Utilities':
            catIcon = Icons.lightbulb_outline;
            catColor = Colors.amber;
            break;
          case 'Maintenance':
            catIcon = Icons.build_outlined;
            catColor = Colors.purple;
            break;
          case 'Stationery':
            catIcon = Icons.edit_note_outlined;
            catColor = Colors.teal;
            break;
          default:
            catIcon = Icons.category_outlined;
            catColor = Colors.grey;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppTheme.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: catColor.withValues(alpha: 0.1),
              foregroundColor: catColor,
              child: Icon(catIcon),
            ),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    exp.category,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Text(
                  CurrencyUtils.formatRupees(exp.amount, showDecimals: true),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppTheme.danger,
                  ),
                ),
              ],
            ),
            subtitle: Text(
              '$dateStr · ${exp.paymentMode}',
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
            childrenPadding: const EdgeInsets.all(16),
            expandedCrossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (exp.description.isNotEmpty) ...[
                Text(
                  '${context.tr('description')}:',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppTheme.textSecondary),
                ),
                const SizedBox(height: 4),
                Text(
                  exp.description,
                  style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 12),
              ],
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('loggedBy').replaceFirst('{user}', exp.recordedBy),
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                      if (exp.createdAt != null)
                        Text(
                          context.tr('createdAtTime').replaceFirst('{time}', '${exp.createdAt!.day}/${exp.createdAt!.month} ${exp.createdAt!.hour}:${exp.createdAt!.minute.toString().padLeft(2, '0')}'),
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                    onPressed: () => _confirmDelete(context, exp),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context, Expense exp) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.tr('deleteExpenseConfirmTitle')),
        content: Text(context.tr('deleteExpenseConfirmMsg').replaceFirst('{amount}', CurrencyUtils.formatRupees(exp.amount))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('cancel')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('delete')),
          ),
        ],
      ),
    );

    if (ok == true) {
      try {
        await _expenseService.deleteExpense(exp.id);
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('expenseDeletedSuccess')), backgroundColor: AppTheme.success),
        );
      } catch (e) {
        AppLogger.e('ExpenseLedgerScreen', 'Delete failed: $e');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('expenseDeleteFailed').replaceFirst('{error}', e.toString())), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  void _showAddExpenseBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AddExpenseBottomSheet(),
    );
  }
}

class _AddExpenseBottomSheet extends StatefulWidget {
  const _AddExpenseBottomSheet();

  @override
  State<_AddExpenseBottomSheet> createState() => _AddExpenseBottomSheetState();
}

class _AddExpenseBottomSheetState extends State<_AddExpenseBottomSheet> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();
  
  String _category = 'Salaries';
  String _paymentMode = 'Cash';
  DateTime _expenseDate = DateTime.now();
  bool _saving = false;

  static const List<String> _categories = [
    'Salaries',
    'Rent',
    'Utilities',
    'Maintenance',
    'Stationery',
    'Other'
  ];

  static const List<String> _paymentModes = [
    'Cash',
    'Bank',
    'UPI',
    'Cheque'
  ];

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: AppTheme.light.copyWith(
            colorScheme: const ColorScheme.light(
              primary: AppTheme.primary,
              onPrimary: Colors.white,
              onSurface: AppTheme.textPrimary,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() => _expenseDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _saving = true);
    try {
      final amount = double.parse(_amountController.text.trim());
      final userEmail = AuthService().currentFirebaseUser?.email ?? 'owner@schoolapp.org';

      final expense = Expense(
        id: '', // Will be generated by Firestore
        amount: amount,
        category: _category,
        description: _descriptionController.text.trim(),
        expenseDate: _expenseDate,
        recordedBy: userEmail,
        paymentMode: _paymentMode,
      );

      await ExpenseService().addExpense(expense);
      
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('expenseLoggedSuccess')), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      AppLogger.e('AddExpenseBottomSheet', 'Save failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('expenseSaveFailed').replaceFirst('{error}', e.toString())), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + viewInsets.bottom),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.tr('logExpense'),
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(),
              const SizedBox(height: 12),
              // Amount field
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: InputDecoration(
                  labelText: context.tr('amountRupeesRequired'),
                  prefixText: '₹ ',
                  border: const OutlineInputBorder(),
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return context.tr('pleaseEnterAmount');
                  }
                  final n = double.tryParse(val.trim());
                  if (n == null || n <= 0) {
                    return context.tr('pleaseEnterValidAmount');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              // Category field
              DropdownButtonFormField<String>(
                value: _category,
                decoration: InputDecoration(
                  labelText: context.tr('categoryRequired'),
                  border: const OutlineInputBorder(),
                ),
                items: _categories.map((cat) {
                  return DropdownMenuItem(value: cat, child: Text(cat));
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _category = v);
                  }
                },
              ),
              const SizedBox(height: 16),
              // Payment Mode field
              DropdownButtonFormField<String>(
                value: _paymentMode,
                decoration: InputDecoration(
                  labelText: context.tr('paymentModeRequired'),
                  border: const OutlineInputBorder(),
                ),
                items: _paymentModes.map((mode) {
                  return DropdownMenuItem(value: mode, child: Text(mode));
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _paymentMode = v);
                  }
                },
              ),
              const SizedBox(height: 16),
              // Date picker
              InkWell(
                onTap: _selectDate,
                child: InputDecorator(
                  decoration: InputDecoration(
                    labelText: context.tr('expenseDateRequired'),
                    border: const OutlineInputBorder(),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_expenseDate.day}/${_expenseDate.month}/${_expenseDate.year}',
                        style: const TextStyle(fontSize: 15),
                      ),
                      const Icon(Icons.calendar_today, color: AppTheme.primary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Description
              TextFormField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: context.tr('descriptionNotes'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      )
                    : Text(
                        context.tr('saveExpense'),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
