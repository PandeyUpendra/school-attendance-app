import '../../l10n/app_strings.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/teacher.dart';
import '../../theme.dart';
class TeacherLeaveBalanceScreen extends StatefulWidget {
  final Teacher teacher;
  const TeacherLeaveBalanceScreen({super.key, required this.teacher});

  @override
  State<TeacherLeaveBalanceScreen> createState() => _TeacherLeaveBalanceScreenState();
}

class _LeaveQuota {
  final String name;
  final int quota;
  final Color color;
  final IconData icon;

  _LeaveQuota({
    required this.name,
    required this.quota,
    required this.color,
    required this.icon,
  });
}

class _TeacherLeaveBalanceScreenState extends State<TeacherLeaveBalanceScreen> {
  // Default yearly quotas
  final List<_LeaveQuota> _quotas = [
    _LeaveQuota(name: 'Casual Leave', quota: 12, color: Colors.blue, icon: Icons.beach_access),
    _LeaveQuota(name: 'Medical Leave', quota: 10, color: Colors.red, icon: Icons.medical_services_outlined),
    _LeaveQuota(name: 'Earned Leave', quota: 15, color: Colors.green, icon: Icons.stars_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('leaveQuotaBalances')),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('schools')
            .doc(widget.teacher.schoolId)
            .collection('leave_applications')
            .where('teacherId', isEqualTo: widget.teacher.id)
            .where('status', isEqualTo: 'approved')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error loading leave applications: ${snapshot.error}'));
          }

          final approvedLeaves = snapshot.data?.docs ?? [];
          
          // Map reasons to categories and calculate taken days
          int casualTaken = 0;
          int medicalTaken = 0;
          int earnedTaken = 0;

          final List<Map<String, dynamic>> ledger = [];

          for (final doc in approvedLeaves) {
            final data = doc.data() as Map<String, dynamic>;
            final reason = data['reason'] as String? ?? 'Other';
            final days = data['numberOfDays'] as int? ?? 1;
            final startDate = data['startDate'] as String? ?? '';
            
            String category;
            if (reason.contains('Medical') || reason.contains('Health')) {
              category = 'Medical Leave';
              medicalTaken += days;
            } else if (reason.contains('Family') || 
                       reason.contains('Personal') || 
                       reason.contains('Wedding') || 
                       reason.contains('Bereavement')) {
              category = 'Casual Leave';
              casualTaken += days;
            } else {
              category = 'Earned Leave';
              earnedTaken += days;
            }

            ledger.add({
              'startDate': startDate,
              'days': days,
              'reason': reason,
              'category': category,
            });
          }

          // Sort ledger by startDate descending
          ledger.sort((a, b) => b['startDate'].toString().compareTo(a['startDate'].toString()));

          final takenMap = {
            'Casual Leave': casualTaken,
            'Medical Leave': medicalTaken,
            'Earned Leave': earnedTaken,
          };

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildOverviewHeader(casualTaken + medicalTaken + earnedTaken),
              const SizedBox(height: 16),
              const Text(
                'QUOTA BREAKDOWN',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 0.8),
              ),
              const SizedBox(height: 8),
              ..._quotas.map((q) {
                final taken = takenMap[q.name] ?? 0;
                final remaining = (q.quota - taken).clamp(0, q.quota);
                return _buildQuotaCard(q, taken, remaining);
              }),
              const SizedBox(height: 20),
              const Text(
                'APPROVED LEAVE LEDGER',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 0.8),
              ),
              const SizedBox(height: 8),
              if (ledger.isEmpty)
                _buildEmptyLedgerCard()
              else
                ...ledger.map((item) => _buildLedgerTile(item)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildOverviewHeader(int totalTaken) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primaryMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TOTAL APPROVED LEAVES (THIS YEAR)',
            style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1.1),
          ),
          const SizedBox(height: 8),
          Text(
            '$totalTaken Days',
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          const Text(
            'Remaining balances are updated automatically as leaves get approved.',
            style: TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildQuotaCard(_LeaveQuota q, int taken, int remaining) {
    final percentage = q.quota > 0 ? (taken / q.quota).clamp(0.0, 1.0) : 0.0;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: q.color.withValues(alpha: 0.1),
                  foregroundColor: q.color,
                  radius: 20,
                  child: Icon(q.icon),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        q.name,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppTheme.textPrimary),
                      ),
                      Text(
                        'Quota: ${q.quota} days',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$remaining Left',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: remaining > 0 ? AppTheme.primary : AppTheme.danger),
                    ),
                    Text(
                      '$taken taken',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage,
                minHeight: 6,
                backgroundColor: Colors.grey.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(q.color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyLedgerCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: Text(
            'No approved leaves registered in the ledger.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _buildLedgerTile(Map<String, dynamic> item) {
    // Format YYYY-MM-DD to DD MMM YYYY
    final dateStr = item['startDate'] as String;
    String formattedDate = dateStr;
    const months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    try {
      final parts = dateStr.split('-');
      if (parts.length == 3) {
        final d = int.parse(parts[2]);
        final m = int.parse(parts[1]);
        final y = int.parse(parts[0]);
        formattedDate = '$d ${months[m]} $y';
      }
    } catch (_) {}

    final days = item['days'] as int;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: AppTheme.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        title: Text(
          formattedDate,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
        ),
        subtitle: Text('${item['category']} · ${item['reason']}', style: const TextStyle(fontSize: 12)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            '$days day${days > 1 ? 's' : ''}',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppTheme.primary),
          ),
        ),
      ),
    );
  }
}
