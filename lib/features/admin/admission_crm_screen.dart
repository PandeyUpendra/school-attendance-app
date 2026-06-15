import 'package:flutter/material.dart';
import '../../models/lead.dart';
import '../../services/lead_service.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';

class AdmissionCrmScreen extends StatefulWidget {
  const AdmissionCrmScreen({super.key});

  @override
  State<AdmissionCrmScreen> createState() => _AdmissionCrmScreenState();
}

class _AdmissionCrmScreenState extends State<AdmissionCrmScreen>
    with SingleTickerProviderStateMixin {
  final LeadService _leadService = LeadService();
  late TabController _tabCtrl;

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
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  void _showAddLeadDialog() {
    final nameCtrl = TextEditingController();
    final classCtrl = TextEditingController();
    final parentCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Admission Lead', style: TextStyle(fontWeight: FontWeight.bold)),
        content: SingleChildScrollView(
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Student Name'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter name' : null,
                ),
                TextFormField(
                  controller: classCtrl,
                  decoration: const InputDecoration(labelText: 'Target Class (e.g. Class 6)'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter class' : null,
                ),
                TextFormField(
                  controller: parentCtrl,
                  decoration: const InputDecoration(labelText: 'Parent/Guardian Name'),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter parent name' : null,
                ),
                TextFormField(
                  controller: phoneCtrl,
                  decoration: const InputDecoration(labelText: 'Contact Phone'),
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.trim().isEmpty ? 'Enter phone' : null,
                ),
                TextFormField(
                  controller: emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email Address'),
                  keyboardType: TextInputType.emailAddress,
                ),
                TextFormField(
                  controller: noteCtrl,
                  decoration: const InputDecoration(labelText: 'Initial Note/Feedback'),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final lead = Lead(
                id: '',
                studentName: nameCtrl.text.trim(),
                className: classCtrl.text.trim(),
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
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  void _showLeadDetailsSheet(Lead lead) {
    final noteCtrl = TextEditingController(text: lead.note);
    String currentStage = lead.stage;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      lead.studentName,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (c) => AlertDialog(
                          title: const Text('Delete Lead'),
                          content: const Text('Are you sure you want to delete this lead?'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('No')),
                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Yes')),
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
              Text('Target Class: ${lead.className}', style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              const SizedBox(height: 12),
              const Divider(),
              const SizedBox(height: 8),
              
              // Contact details
              Row(children: [
                const Icon(Icons.person, size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('Parent: ${lead.parentName}', style: const TextStyle(fontSize: 14)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.phone, size: 16, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text('Phone: ${lead.parentPhone}', style: const TextStyle(fontSize: 14)),
              ]),
              if (lead.parentEmail.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.email, size: 16, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text('Email: ${lead.parentEmail}', style: const TextStyle(fontSize: 14)),
                ]),
              ],
              const SizedBox(height: 16),
              
              // Stage selector
              const Text('Pipeline Stage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: currentStage,
                decoration: InputDecoration(
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: _stages.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
                onChanged: (val) {
                  if (val != null) {
                    setS(() => currentStage = val);
                    _leadService.updateLeadStage(lead.id, val);
                  }
                },
              ),
              const SizedBox(height: 16),

              // Notes
              const Text('Notes / Follow-up Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 8),
              TextField(
                controller: noteCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Enter log details here...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 16),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () async {
                    await _leadService.updateLeadNote(lead.id, noteCtrl.text.trim());
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('Save Details'),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Admission CRM'),
        backgroundColor: AppTheme.primaryDark,
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: _stages.map((s) => Tab(text: s)).toList(),
        ),
      ),
      body: StreamBuilder<List<Lead>>(
        stream: _leadService.watchLeads(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final leads = snapshot.data ?? [];

          return TabBarView(
            controller: _tabCtrl,
            children: _stages.map((stage) {
              final filtered = leads.where((l) => l.stage == stage).toList();
              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.folder_open_outlined, size: 60, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('No leads in "$stage"', style: TextStyle(color: Colors.grey.shade500, fontSize: 15)),
                    ],
                  ),
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: filtered.length,
                itemBuilder: (ctx, i) {
                  final lead = filtered[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      title: Text(
                        lead.studentName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 4),
                          Text('Class: ${lead.className} • Parent: ${lead.parentName}'),
                          if (lead.note.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              lead.note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ],
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                      onTap: () => _showLeadDetailsSheet(lead),
                    ),
                  );
                },
              );
            }).toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddLeadDialog,
        backgroundColor: AppTheme.primary,
        child: const Icon(Icons.add),
      ),
    );
  }
}
