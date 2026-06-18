import 'package:flutter/material.dart';
import '../../models/lead.dart';
import '../../services/lead_service.dart';
import '../../services/auth_service.dart';
import '../../services/timetable_service.dart';
import '../../theme.dart';
import '../students/add_student_screen.dart';
import '../../shared/widgets/email_text_form_field.dart';
import '../../shared/utils/app_transitions.dart';

class AdmissionCrmScreen extends StatefulWidget {
  const AdmissionCrmScreen({super.key});

  @override
  State<AdmissionCrmScreen> createState() => _AdmissionCrmScreenState();
}

class _AdmissionCrmScreenState extends State<AdmissionCrmScreen>
    with SingleTickerProviderStateMixin {
  final LeadService _leadService = LeadService();
  late TabController _tabCtrl;

  String _userEmail = '';
  String _userRole = '';
  bool _isLoading = true;
  List<String> _schoolClasses = [];

  // Filter option for staff (All vs My Enquiries)
  bool _showMyEnquiriesOnly = false;
  
  // Search query
  String _searchQuery = '';
  final TextEditingController _searchCtrl = TextEditingController();

  static const List<String> _stages = [
    'Inquiry',
    'Visit',
    'Docs Pending',
    'Approved',
    'Admitted'
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _stages.length, vsync: this);
    _loadUserSession();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserSession() async {
    try {
      final session = await AuthService().getSession();
      final settings = await TimetableService().getSettings();
      if (mounted) {
        setState(() {
          _userEmail = session?['email'] as String? ?? '';
          _userRole = session?['role'] as String? ?? '';
          _schoolClasses = List<String>.from(settings['classes'] ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAddLeadDialog() async {
    final nameCtrl = TextEditingController();
    final parentCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    
    final classesList = _schoolClasses.isNotEmpty 
        ? _schoolClasses 
        : ['Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5', 'Class 6', 'Class 7', 'Class 8', 'Class 9', 'Class 10'];
    
    String selectedClass = classesList.contains('Class 6') ? 'Class 6' : classesList.first;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          _userRole == 'guardian' ? 'Refer a Student' : 'Add Admission Lead',
          style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary),
        ),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Student Name *',
                    hintText: 'Enter student\'s full name',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter name' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedClass,
                  decoration: const InputDecoration(labelText: 'Target Class *'),
                  items: classesList
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      selectedClass = val;
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: parentCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Parent/Guardian Name *',
                    hintText: 'Enter parent\'s full name',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter parent name' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Contact Phone *',
                    hintText: 'Enter mobile number',
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter phone' : null,
                ),
                const SizedBox(height: 12),
                EmailTextFormField(
                  controller: emailCtrl,
                  isOptional: true,
                  decoration: const InputDecoration(
                    labelText: 'Email Address (Optional)',
                    hintText: 'parent@example.com',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: noteCtrl,
                  decoration: InputDecoration(
                    labelText: _userRole == 'guardian' ? 'Notes / Referral Message' : 'Initial Note / Feedback',
                    hintText: 'Any extra details...',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final lead = Lead(
                id: '',
                studentName: nameCtrl.text.trim(),
                className: selectedClass,
                parentName: parentCtrl.text.trim(),
                parentPhone: phoneCtrl.text.trim(),
                parentEmail: emailCtrl.text.trim(),
                stage: 'Inquiry',
                note: noteCtrl.text.trim(),
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
                schoolId: '',
              );
              await _leadService.addLead(lead);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Admission Enquiry saved successfully!'),
                    backgroundColor: AppTheme.success,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    ).then((_) {
      nameCtrl.dispose();
      parentCtrl.dispose();
      phoneCtrl.dispose();
      emailCtrl.dispose();
      noteCtrl.dispose();
    });
  }

  void _showLeadDetailsSheet(Lead lead) async {
    final isGuardian = _userRole == 'guardian';
    final isStaff = !isGuardian;
    final isMgmt = _userRole == 'principal' || _userRole == 'coordinator';
    
    final followUpCtrl = TextEditingController();
    DateTime? tempNextDate;
    String currentStage = lead.stage;

    try {
      await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final isAdmitted = currentStage == 'Admitted';

          return Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header Block
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          lead.studentName,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ),
                      if (isMgmt)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Delete Lead'),
                                content: const Text('Are you sure you want to delete this lead permanently?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
                                    child: const Text('Yes, Delete'),
                                  ),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await _leadService.deleteLead(lead.id);
                              if (ctx.mounted) {
                                Navigator.pop(ctx); // Close sheet
                              }
                            }
                          },
                        )
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryLight.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          lead.className,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppTheme.primary),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildStageBadge(currentStage),
                    ],
                  ),
                  const SizedBox(height: 16),
                  
                  // Contact Details Section
                  const Text('Contact Information', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 8),
                  _buildDetailRow(Icons.person, 'Parent', lead.parentName),
                  _buildDetailRow(Icons.phone, 'Phone', lead.parentPhone),
                  if (lead.parentEmail.isNotEmpty)
                    _buildDetailRow(Icons.email, 'Email', lead.parentEmail),
                  
                  // Creator Details (requirement: proper track of who created)
                  if (lead.createdByEmail.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _buildDetailRow(
                      Icons.account_circle_outlined, 
                      'Logged By', 
                      '${lead.createdByName} (${_formatRole(lead.createdByRole)})',
                    ),
                  ],
                  const SizedBox(height: 8),
                  _buildDetailRow(Icons.calendar_today, 'Enquiry Date', _formatDateOnly(lead.createdAt)),
                  
                  const Divider(height: 24),

                  // Stage selector & Convert buttons (For Staff Only)
                  if (isStaff) ...[
                    const Text('Pipeline Stage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: currentStage,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: _stages.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                      onChanged: (val) async {
                        if (val != null) {
                          setS(() => currentStage = val);
                          await _leadService.updateLeadStage(lead.id, val);
                        }
                      },
                    ),
                    
                    if (isMgmt && isAdmitted) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(ctx); // Close sheet first
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AddStudentScreen(
                                  className: lead.className,
                                  initialStudentName: lead.studentName,
                                  initialParentName: lead.parentName,
                                  initialParentPhone: lead.parentPhone,
                                  initialParentEmail: lead.parentEmail,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.person_add),
                          label: const Text('Convert to Student Profile', style: TextStyle(fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.success,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                    const Divider(height: 32),
                  ],

                  // Follow-up Log / Timeline
                  const Text('Follow-Up History & Timeline', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  const SizedBox(height: 12),
                  
                  _FollowUpTimeline(followUps: lead.followUps),
                  
                  // Log New Follow-Up Section (Staff Only)
                  if (isStaff) ...[
                    const Divider(height: 24),
                    const Text('Log New Follow-Up', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: followUpCtrl,
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'Enter call details, meeting minutes, or notes here...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.alarm, size: 18, color: AppTheme.accent),
                        const SizedBox(width: 8),
                        Text(
                          tempNextDate == null 
                              ? 'Schedule Next Contact (Optional)' 
                              : 'Next Contact: ${_formatDateOnly(tempNextDate!)}',
                          style: TextStyle(
                            fontSize: 13, 
                            fontWeight: FontWeight.w600,
                            color: tempNextDate == null ? AppTheme.textSecondary : AppTheme.accent,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: DateTime.now().add(const Duration(days: 2)),
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                            );
                            if (picked != null) {
                              setS(() => tempNextDate = picked);
                            }
                          },
                          child: const Text('Select Date'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 44,
                      child: ElevatedButton(
                        onPressed: () async {
                          final note = followUpCtrl.text.trim();
                          if (note.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please enter follow-up details first.')),
                            );
                            return;
                          }
                          await _leadService.addFollowUp(lead.id, note, tempNextDate);
                          if (!mounted) return;
                          if (ctx.mounted) {
                            Navigator.pop(ctx);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Follow-up logged successfully.'),
                                backgroundColor: AppTheme.success,
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: const Text('Save Details', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
    } finally {
      followUpCtrl.dispose();
    }
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: AppTheme.primaryMid),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textSecondary),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStageBadge(String stage) {
    Color bg = Colors.grey.shade100;
    Color fg = Colors.grey.shade800;

    switch (stage) {
      case 'Inquiry':
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
        break;
      case 'Visit':
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        break;
      case 'Docs Pending':
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        break;
      case 'Approved':
        bg = Colors.purple.shade50;
        fg = Colors.purple.shade800;
        break;
      case 'Admitted':
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        stage,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }

  String _formatDateOnly(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  String _formatRole(String role) {
    if (role.isEmpty) return 'Staff';
    return role.substring(0, 1).toUpperCase() + role.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isGuardian = _userRole == 'guardian';

    if (isGuardian) {
      return _buildGuardianReferralPortal();
    }

    return _buildStaffCrm();
  }

  // ── Guardian Referral Layout ──────────────────────────────────────────────
  Widget _buildGuardianReferralPortal() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Refer a Student'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Referral Banner Card
          Container(
            width: double.infinity,
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppTheme.primaryDark, AppTheme.primaryMid],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.primaryDark.withOpacity(0.2),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.card_giftcard, color: Colors.white, size: 24),
                    SizedBox(width: 8),
                    Text(
                      'Grow Our School Family!',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'Refer your friends, relatives, or neighbors to join our community. Fill in their details and follow their enrollment progress below.',
                  style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                ),
              ],
            ),
          ),
          
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'My Referrals',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
              ),
            ),
          ),
          
          Expanded(
            child: StreamBuilder<List<Lead>>(
              stream: _leadService.watchLeads(emailFilter: _userEmail),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error loading referrals: ${snapshot.error}'));
                }

                final referrals = snapshot.data ?? [];

                if (referrals.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people_outline, size: 50, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        const Text(
                          'You haven\'t referred anyone yet.',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tap the "+" button below to add your first referral!',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: referrals.length,
                  itemBuilder: (ctx, i) {
                    final ref = referrals[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.grey.shade200),
                      ),
                      elevation: 0,
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        title: Text(
                          ref.studentName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text('Class: ${ref.className} • Parent: ${ref.parentName}'),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                _buildStageBadge(ref.stage),
                                const SizedBox(width: 8),
                                if (ref.stage == 'Admitted')
                                  const Icon(Icons.check_circle, color: AppTheme.success, size: 16),
                              ],
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
                        onTap: () => _showLeadDetailsSheet(ref),
                      ),
                    );
                  },
                );
              },
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddLeadDialog,
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.add),
        label: const Text('Add Referral'),
      ),
    );
  }

  // ── Staff CRM Layout ──────────────────────────────────────────────────────
  Widget _buildStaffCrm() {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Admission CRM'),
        backgroundColor: AppTheme.primaryDark,
        elevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: _stages.map((s) => Tab(text: s)).toList(),
        ),
      ),
      body: Column(
        children: [
          // Search & Filter controls
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Column(
              children: [
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                    suffixIcon: _searchQuery.isNotEmpty 
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _searchQuery = '';
                                _searchCtrl.clear();
                              });
                            },
                          )
                        : null,
                    hintText: 'Search by student, parent, or creator...',
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: AppTheme.border),
                    ),
                  ),
                  onChanged: (val) {
                    setState(() {
                      _searchQuery = val.trim().toLowerCase();
                    });
                  },
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('My Enquiries Only'),
                      selected: _showMyEnquiriesOnly,
                      selectedColor: AppTheme.primaryLight.withOpacity(0.5),
                      checkmarkColor: AppTheme.primary,
                      labelStyle: TextStyle(
                        fontSize: 12, 
                        fontWeight: _showMyEnquiriesOnly ? FontWeight.bold : FontWeight.normal,
                        color: _showMyEnquiriesOnly ? AppTheme.primary : AppTheme.textPrimary,
                      ),
                      onSelected: (val) {
                        setState(() {
                          _showMyEnquiriesOnly = val;
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _searchQuery.isNotEmpty || _showMyEnquiriesOnly
                            ? 'Filters active'
                            : '',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontStyle: FontStyle.italic),
                        textAlign: TextAlign.end,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          Expanded(
            child: StreamBuilder<List<Lead>>(
              stream: _leadService.watchLeads(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text('Error loading pipeline: ${snapshot.error}'));
                }

                var leads = snapshot.data ?? [];

                // 1. Filter by Creator if checked
                if (_showMyEnquiriesOnly) {
                  leads = leads.where((l) => l.createdByEmail.toLowerCase() == _userEmail.toLowerCase()).toList();
                }

                // 2. Filter by search query if text entered
                if (_searchQuery.isNotEmpty) {
                  leads = leads.where((l) =>
                      l.studentName.toLowerCase().contains(_searchQuery) ||
                      l.parentName.toLowerCase().contains(_searchQuery) ||
                      l.parentPhone.contains(_searchQuery) ||
                      l.createdByName.toLowerCase().contains(_searchQuery)
                  ).toList();
                }

                return PremiumTabBarView(
                  controller: _tabCtrl,
                  children: _stages.map((stage) {
                    final filtered = leads.where((l) => l.stage == stage).toList();
                    
                    if (filtered.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open_outlined, size: 50, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'No enquiries in "$stage"',
                              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final lead = filtered[i];
                        
                        // Check if follow-up is overdue
                        final isOverdue = lead.nextFollowUpDate != null && 
                            lead.nextFollowUpDate!.isBefore(DateTime.now().subtract(const Duration(days: 1)));

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isOverdue ? AppTheme.danger.withOpacity(0.5) : Colors.grey.shade200,
                              width: isOverdue ? 1.5 : 1.0,
                            ),
                          ),
                          elevation: 0,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    lead.studentName,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                                if (isOverdue)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppTheme.dangerLight,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'Overdue',
                                      style: TextStyle(fontSize: 10, color: AppTheme.danger, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                Text('Class: ${lead.className} • Parent: ${lead.parentName}'),
                                if (lead.createdByEmail.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Logged by: ${lead.createdByName} (${_formatRole(lead.createdByRole)})',
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                  ),
                                ],
                                if (lead.nextFollowUpDate != null) ...[
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.alarm, size: 12, color: AppTheme.accent),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Next Call: ${_formatDateOnly(lead.nextFollowUpDate!)}',
                                        style: TextStyle(
                                          fontSize: 11, 
                                          fontWeight: FontWeight.bold,
                                          color: isOverdue ? AppTheme.danger : AppTheme.accent,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                            trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: AppTheme.textSecondary),
                            onTap: () => _showLeadDetailsSheet(lead),
                          ),
                        );
                      },
                    );
                  }).toList(),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddLeadDialog,
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add),
      ),
    );
  }
}

// ── Vertical Timeline Widget ──────────────────────────────────────────────
class _FollowUpTimeline extends StatelessWidget {
  final List<FollowUp> followUps;

  const _FollowUpTimeline({required this.followUps});

  @override
  Widget build(BuildContext context) {
    if (followUps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12.0),
        child: Text(
          'No follow-up records found. Add follow-up logs below.',
          style: TextStyle(fontStyle: FontStyle.italic, color: AppTheme.textSecondary, fontSize: 13),
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: followUps.length,
      itemBuilder: (context, index) {
        final f = followUps[index];
        final isLast = index == followUps.length - 1;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: AppTheme.accent,
                    shape: BoxShape.circle,
                  ),
                ),
                if (!isLast)
                  Container(
                    width: 2,
                    height: 48,
                    color: AppTheme.border,
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    f.note,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'By ${f.byName} (${_formatRole(f.byRole)}) • ${_formatDateTime(f.date)}',
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  String _formatRole(String role) {
    if (role.isEmpty) return 'Staff';
    return role.substring(0, 1).toUpperCase() + role.substring(1);
  }
}
