import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme.dart';
import '../l10n/app_strings.dart';
import '../services/auth_service.dart';

class GuardianPTMScreen extends StatefulWidget {
  final String studentClass;

  const GuardianPTMScreen({super.key, required this.studentClass});

  @override
  State<GuardianPTMScreen> createState() => _GuardianPTMScreenState();
}

class _GuardianPTMScreenState extends State<GuardianPTMScreen> {
  final _db = FirebaseFirestore.instance;

  String get _schoolId => AuthService.currentSchoolId;

  Stream<List<Map<String, dynamic>>> _streamPTMEvents() {
    return _db
        .collection('schools')
        .doc(_schoolId)
        .collection('ptm_events')
        .where('className', isEqualTo: widget.studentClass)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final data = doc.data();
              data['id'] = doc.id;
              return data;
            }).toList());
  }

  String _formatDate(dynamic dateVal) {
    if (dateVal == null) return '—';
    DateTime? dt;
    if (dateVal is Timestamp) {
      dt = dateVal.toDate();
    } else if (dateVal is String) {
      dt = DateTime.tryParse(dateVal);
    }
    if (dt == null) return dateVal.toString();
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${dt.day.toString().padLeft(2, '0')} ${months[dt.month]} ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Parent-Teacher Meetings',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            Text(
              '${context.tr('classLabel')} ${widget.studentClass}',
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _streamPTMEvents(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error loading PTM events: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          final events = snapshot.data ?? [];
          if (events.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_month_outlined,
                    size: 64,
                    color: Colors.grey.shade300,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No PTM meetings scheduled for ${widget.studentClass}',
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
                  ),
                ],
              ),
            );
          }

          // Sort events by date ascending
          events.sort((a, b) {
            final da = a['date'];
            final db = b['date'];
            if (da == null || db == null) return 0;
            final dta = da is Timestamp ? da.toDate() : DateTime.tryParse(da.toString()) ?? DateTime.now();
            final dtb = db is Timestamp ? db.toDate() : DateTime.tryParse(db.toString()) ?? DateTime.now();
            return dta.compareTo(dtb);
          });

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: events.length,
            itemBuilder: (context, i) {
              final ev = events[i];
              final dateStr = _formatDate(ev['date']);
              final timeStr = ev['time'] as String? ?? '—';
              final roomStr = ev['room'] as String? ?? '—';
              final notes = ev['notes'] as String? ?? '';
              final title = ev['title'] as String? ?? 'PTM Meeting';

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
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
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.groups_outlined,
                            color: AppTheme.primary,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        const Icon(Icons.calendar_today_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          dateStr,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                        const SizedBox(width: 16),
                        const Icon(Icons.access_time_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.place_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 8),
                        Text(
                          'Venue: $roomStr',
                          style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                    if (notes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Notes:',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notes,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
