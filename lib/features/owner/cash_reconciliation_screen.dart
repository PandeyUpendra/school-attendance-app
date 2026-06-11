import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';
import '../../services/fee_service.dart';
import '../../theme.dart';
import '../../shared/utils/app_logger.dart';
import '../../shared/utils/currency_utils.dart';

class CashReconciliationScreen extends StatefulWidget {
  const CashReconciliationScreen({super.key});

  @override
  State<CashReconciliationScreen> createState() => _CashReconciliationScreenState();
}

class _CollectorGroup {
  final String email;
  final double totalAmount;
  final List<QueryDocumentSnapshot> docs;

  _CollectorGroup({
    required this.email,
    required this.totalAmount,
    required this.docs,
  });
}

class _CashReconciliationScreenState extends State<CashReconciliationScreen> {
  bool _loading = true;
  List<_CollectorGroup> _groups = [];
  final Set<String> _selectedDocPaths = {}; // Set of document paths selected for reconciliation
  bool _showOnlyToday = false;

  @override
  void initState() {
    super.initState();
    _loadCollections();
  }

  Future<void> _loadCollections() async {
    setState(() => _loading = true);
    _selectedDocPaths.clear();
    try {
      final sid = AuthService.currentSchoolId;
      
      Query query = FirebaseFirestore.instance
          .collectionGroup('payments')
          .where('schoolId', isEqualTo: sid)
          .where('mode', isEqualTo: 'Cash');

      if (_showOnlyToday) {
        final now = DateTime.now();
        final dayStart = DateTime(now.year, now.month, now.day);
        query = query.where('paidOn', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart));
      } else {
        // Show all unreconciled cash payments
        query = query.where('reconciled', isEqualTo: false);
      }

      final snap = await query.get();

      // Group documents by collector (enteredBy)
      final Map<String, List<QueryDocumentSnapshot>> groupedDocs = {};
      for (final doc in snap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        // If it was already reconciled and we are showing all unreconciled, query filters it.
        // If we query by date, we might get reconciled ones, so we filter out reconciled ones manually in that mode.
        final reconciled = data['reconciled'] as bool? ?? false;
        if (_showOnlyToday && reconciled) continue;

        final collector = data['enteredBy'] as String? ?? 'unknown_collector@schoolapp.org';
        groupedDocs.putIfAbsent(collector, () => []).add(doc);
      }

      final List<_CollectorGroup> collectorGroups = [];
      groupedDocs.forEach((email, docs) {
        double total = 0.0;
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final amtPaise = data['amountPaise'] as int? ?? 
              (data['amount'] is num ? ((data['amount'] as num) * 100).round() : 0);
          total += amtPaise / 100.0;
        }

        // Sort docs within group by paidOn descending
        docs.sort((a, b) {
          final tsA = (a.data() as Map)['paidOn'] as Timestamp?;
          final tsB = (b.data() as Map)['paidOn'] as Timestamp?;
          if (tsA == null || tsB == null) return 0;
          return tsB.compareTo(tsA);
        });

        collectorGroups.add(_CollectorGroup(
          email: email,
          totalAmount: total,
          docs: docs,
        ));
      });

      // Sort groups by total amount descending
      collectorGroups.sort((a, b) => b.totalAmount.compareTo(a.totalAmount));

      setState(() {
        _groups = collectorGroups;
        _loading = false;
      });
    } catch (e, st) {
      AppLogger.e('CashReconciliationScreen', 'Failed to load cash payments: $e', e, st);
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load collections: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  Future<void> _reconcileSelected() async {
    if (_selectedDocPaths.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Deposit?'),
        content: Text('Mark ${_selectedDocPaths.length} cash collections as deposited into the school bank account? This action is audited.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.success),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm Deposit'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);
    try {
      final List<DocumentReference> refs = [];
      for (final group in _groups) {
        for (final doc in group.docs) {
          if (_selectedDocPaths.contains(doc.reference.path)) {
            refs.add(doc.reference);
          }
        }
      }

      await FeeService().reconcilePayments(refs, true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully reconciled ${refs.length} cash payments'), backgroundColor: AppTheme.success),
        );
      }
      _loadCollections();
    } catch (e) {
      AppLogger.e('CashReconciliationScreen', 'Reconciliation failed: $e');
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reconcile: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double grandTotal = 0;
    int grandCount = 0;
    for (final group in _groups) {
      grandTotal += group.totalAmount;
      grandCount += group.docs.length;
    }

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Cash Reconciliation'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadCollections,
          ),
        ],
      ),
      body: Column(
        children: [
          _buildGrandSummaryCard(grandTotal, grandCount),
          _buildToggleFilter(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _groups.isEmpty
                    ? _buildEmptyState()
                    : _buildGroupsList(),
          ),
          if (_selectedDocPaths.isNotEmpty) _buildReconcileActionBar(),
        ],
      ),
    );
  }

  Widget _buildGrandSummaryCard(double total, int count) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _showOnlyToday ? 'TODAY\'S CASH COLLECTED' : 'UNRECONCILED CASH OUSTANDING',
                style: const TextStyle(
                  color: AppTheme.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                CurrencyUtils.formatRupees(total, showDecimals: true),
                style: const TextStyle(
                  color: AppTheme.primary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          CircleAvatar(
            backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.3),
            radius: 28,
            child: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.primary, size: 28),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleFilter() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Show All Pending Cash'),
            selected: !_showOnlyToday,
            selectedColor: AppTheme.primary,
            labelStyle: TextStyle(color: !_showOnlyToday ? Colors.white : Colors.black87),
            onSelected: (v) {
              if (v) {
                setState(() {
                  _showOnlyToday = false;
                  _loadCollections();
                });
              }
            },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Collected Today'),
            selected: _showOnlyToday,
            selectedColor: AppTheme.primary,
            labelStyle: TextStyle(color: _showOnlyToday ? Colors.white : Colors.black87),
            onSelected: (v) {
              if (v) {
                setState(() {
                  _showOnlyToday = true;
                  _loadCollections();
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.verified_outlined, size: 64, color: AppTheme.success.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          const Text(
            'All clean!',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            _showOnlyToday ? 'No cash collections recorded today.' : 'All cash collections are reconciled and deposited.',
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupsList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _groups.length,
      itemBuilder: (context, index) {
        final group = _groups[index];
        final cleanEmail = group.email.split('@')[0];
        
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 0,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: AppTheme.border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: ExpansionTile(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cleanEmail.toUpperCase(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      Text(
                        group.email,
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Text(
                  CurrencyUtils.formatRupees(group.totalAmount, showDecimals: true),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary),
                ),
              ],
            ),
            subtitle: Text('${group.docs.length} payments pending deposit', style: const TextStyle(fontSize: 12)),
            children: [
              const Divider(height: 1),
              Container(
                color: Colors.grey.shade50,
                child: ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: group.docs.length,
                  itemBuilder: (context, docIdx) {
                    final doc = group.docs[docIdx];
                    final data = doc.data() as Map<String, dynamic>;
                    
                    final receiptNo = data['receiptNo'] as String? ?? 'RCP-XXXX';
                    final amtPaise = data['amountPaise'] as int? ?? 
                        (data['amount'] is num ? ((data['amount'] as num) * 100).round() : 0);
                    final amt = amtPaise / 100.0;
                    
                    final ts = data['paidOn'] as Timestamp?;
                    final date = ts != null ? ts.toDate() : DateTime.now();
                    final dateStr = '${date.day}/${date.month}/${date.year}';

                    // Parse path to find student info or details
                    // Path format: schools/{sid}/fee_payments/{className}/students/{roll}/payments/{docId}
                    final pathSegments = doc.reference.path.split('/');
                    String studentInfo = 'Student';
                    if (pathSegments.length >= 6) {
                      final className = pathSegments[4].replaceAll('_', ' ');
                      final roll = pathSegments[6];
                      studentInfo = 'Roll $roll · Class $className';
                    }

                    final isSelected = _selectedDocPaths.contains(doc.reference.path);

                    return CheckboxListTile(
                      value: isSelected,
                      activeColor: AppTheme.primary,
                      title: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(receiptNo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          Text(CurrencyUtils.formatRupees(amt), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                      subtitle: Text('$studentInfo\nCollected on $dateStr', style: const TextStyle(fontSize: 11)),
                      isThreeLine: true,
                      onChanged: (val) {
                        setState(() {
                          if (val == true) {
                            _selectedDocPaths.add(doc.reference.path);
                          } else {
                            _selectedDocPaths.remove(doc.reference.path);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReconcileActionBar() {
    double selectedTotal = 0;
    for (final group in _groups) {
      for (final doc in group.docs) {
        if (_selectedDocPaths.contains(doc.reference.path)) {
          final data = doc.data() as Map<String, dynamic>;
          final amtPaise = data['amountPaise'] as int? ?? 
              (data['amount'] is num ? ((data['amount'] as num) * 100).round() : 0);
          selectedTotal += amtPaise / 100.0;
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_selectedDocPaths.length} items selected',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Total: ${CurrencyUtils.formatRupees(selectedTotal, showDecimals: true)}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.primary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.success,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _reconcileSelected,
              child: const Text(
                'Mark Deposited',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
