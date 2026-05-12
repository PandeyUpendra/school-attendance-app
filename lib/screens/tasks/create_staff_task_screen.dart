import 'package:flutter/material.dart';
import '../../models/staff_task.dart';
import '../../models/teacher.dart';
import '../../services/staff_task_service.dart';
import '../../services/timetable_service.dart';
import '../../theme.dart';

class CreateStaffTaskScreen extends StatefulWidget {
  final String schoolId;
  final String creatorEmail;
  final String creatorRole;
  final String creatorName;
  final bool isPersonal;

  const CreateStaffTaskScreen({
    super.key,
    required this.schoolId,
    required this.creatorEmail,
    required this.creatorRole,
    required this.creatorName,
    this.isPersonal = false,
  });

  @override
  State<CreateStaffTaskScreen> createState() => _CreateStaffTaskScreenState();
}


class _CreateStaffTaskScreenState extends State<CreateStaffTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  TaskPriority _priority = TaskPriority.medium;
  DateTime _dueDate = DateTime.now().add(const Duration(days: 1));

  List<Teacher> _allTeachers = [];
  List<Map<String, dynamic>> _allCoordinators = [];
  List<String> _selectedUserIds = [];
  List<String> _selectedUserNames = [];
  List<String> _selectedUserRoles = [];
  List<String> _selectedTargetRoles = [];

  List<String> _allClasses = [];
  List<String> _selectedClasses = [];

  List<Checkpoint> _checkpoints = [];
  final _checkpointCtrl = TextEditingController();

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget.isPersonal) {
      _selectedUserIds = [widget.creatorEmail.toLowerCase().trim()];
      _selectedUserNames = [widget.creatorName];
      _selectedUserRoles = [widget.creatorRole];
    }
    _loadData();
  }

  Future<void> _loadData() async {
    final teachers = await TimetableService().getTeachers(schoolId: widget.schoolId);
    final coordinators = await TimetableService().getCoordinators(widget.schoolId);
    final settings = await TimetableService().getSettings(schoolId: widget.schoolId);
    final classes = List<String>.from(settings['classes'] as List);

    if (mounted) {
      setState(() {
        _allTeachers = teachers;
        _allCoordinators = coordinators;
        _allClasses = classes;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isPersonal ? 'New Personal Task' : 'Create Task'),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _titleCtrl,
                      decoration: const InputDecoration(labelText: 'Task Title*', border: OutlineInputBorder()),
                      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(labelText: 'Description*', border: OutlineInputBorder()),
                      maxLines: 3,
                      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesCtrl,
                      decoration: const InputDecoration(labelText: 'Notes (Optional)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<TaskPriority>(
                            value: _priority,
                            decoration: const InputDecoration(labelText: 'Priority', border: OutlineInputBorder()),
                            items: TaskPriority.values.map((p) => DropdownMenuItem(value: p, child: Text(p.name.toUpperCase()))).toList(),
                            onChanged: (v) => setState(() => _priority = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            child: InputDecorator(
                              decoration: const InputDecoration(labelText: 'Due Date', border: OutlineInputBorder()),
                              child: Text('${_dueDate.day}/${_dueDate.month}/${_dueDate.year}'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!widget.isPersonal) ...[
                      const SizedBox(height: 24),
                      const Text('Assign To*', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _buildAssigneeSelector(),
                      const SizedBox(height: 24),
                      const Text('Target Classes (Optional)', style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _buildClassSelector(),
                    ],
                    const SizedBox(height: 24),
                    const Text('Checkpoints / Sub-tasks', style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _buildCheckpointSection(),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                        child: const Text('CREATE TASK', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildAssigneeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Roles (Assign to all in role):', style: TextStyle(fontSize: 12, color: Colors.grey)),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: const Text('All Teachers'),
              selected: _selectedTargetRoles.contains('teacher'),
              onSelected: (val) {
                setState(() {
                  if (val) {
                    _selectedTargetRoles.add('teacher');
                  } else {
                    _selectedTargetRoles.remove('teacher');
                  }
                });
              },
            ),
            FilterChip(
              label: const Text('All Coordinators'),
              selected: _selectedTargetRoles.contains('coordinator'),
              onSelected: (val) {
                setState(() {
                  if (val) {
                    _selectedTargetRoles.add('coordinator');
                  } else {
                    _selectedTargetRoles.remove('coordinator');
                  }
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        const Text('Specific Staff:', style: TextStyle(fontSize: 12, color: Colors.grey)),
        Wrap(
          spacing: 8,
          children: [
            ..._allCoordinators.map((c) {
              final email = (c['email'] as String? ?? '').toLowerCase().trim();
              final name = c['name'] as String? ?? email;
              final isSelected = _selectedUserIds.contains(email);
              return FilterChip(
                label: Text('$name (Coord)'),
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedUserIds.add(email);
                      _selectedUserNames.add(name);
                      _selectedUserRoles.add('coordinator');
                    } else {
                      int idx = _selectedUserIds.indexOf(email);
                      if (idx != -1) {
                        _selectedUserIds.removeAt(idx);
                        _selectedUserNames.removeAt(idx);
                        _selectedUserRoles.removeAt(idx);
                      }
                    }
                  });
                },
              );
            }),
            ..._allTeachers.map((t) {
              final email = t.email.toLowerCase().trim();
              final isSelected = _selectedUserIds.contains(email);
              return FilterChip(
                label: Text(t.name),
                selected: isSelected,
                onSelected: (val) {
                  setState(() {
                    if (val) {
                      _selectedUserIds.add(email);
                      _selectedUserNames.add(t.name);
                      _selectedUserRoles.add('teacher');
                    } else {
                      int idx = _selectedUserIds.indexOf(email);
                      if (idx != -1) {
                        _selectedUserIds.removeAt(idx);
                        _selectedUserNames.removeAt(idx);
                        _selectedUserRoles.removeAt(idx);
                      }
                    }
                  });
                },
                selectedColor: AppTheme.primary.withOpacity(0.2),
                checkmarkColor: AppTheme.primary,
              );
            }),
          ],
        ),
      ],
    );
  }

  Widget _buildClassSelector() {
    return Wrap(
      spacing: 8,
      children: _allClasses.map((c) {
        final isSelected = _selectedClasses.contains(c);
        return FilterChip(
          label: Text(c),
          selected: isSelected,
          onSelected: (val) {
            setState(() {
              if (val) _selectedClasses.add(c);
              else _selectedClasses.remove(c);
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildCheckpointSection() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _checkpointCtrl,
                decoration: const InputDecoration(hintText: 'Add a checkpoint', border: UnderlineInputBorder()),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle, color: AppTheme.primary),
              onPressed: () {
                if (_checkpointCtrl.text.isNotEmpty) {
                  setState(() {
                    _checkpoints.add(Checkpoint(title: _checkpointCtrl.text));
                    _checkpointCtrl.clear();
                  });
                }
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._checkpoints.asMap().entries.map((entry) {
          int idx = entry.key;
          Checkpoint cp = entry.value;
          return ListTile(
            leading: const Icon(Icons.circle_outlined, size: 20),
            title: Text(cp.title),
            trailing: IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
              onPressed: () => setState(() => _checkpoints.removeAt(idx)),
            ),
            dense: true,
          );
        }),
      ],
    );
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date != null) setState(() => _dueDate = date);
  }

  void _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedUserIds.isEmpty && _selectedTargetRoles.isEmpty && !widget.isPersonal) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please assign to at least one person or role')));
      return;
    }

    final task = StaffTask(
      id: '', // Will be set by service
      schoolId: widget.schoolId,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),

      notes: _notesCtrl.text.trim(),
      createdBy: widget.creatorEmail.toLowerCase().trim(),
      creatorRole: widget.creatorRole,
      creatorName: widget.creatorName,
      assignedToIds: _selectedUserIds.map((e) => e.toLowerCase().trim()).toList(),
      assignedToNames: _selectedUserNames,
      assignedToRoles: _selectedUserRoles,
      targetRoles: _selectedTargetRoles,
      targetClasses: _selectedClasses,
      priority: _priority,
      status: TaskStatus.pending,
      createdAt: DateTime.now(),
      dueDate: _dueDate,
      checkpoints: _checkpoints,
    );

    await StaffTaskService().createTaskWithAutoId(task);
    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Task created successfully')));
    }
  }
}
