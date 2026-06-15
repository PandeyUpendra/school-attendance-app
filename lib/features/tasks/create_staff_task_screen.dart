import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../models/staff_task.dart';
import '../../models/teacher.dart';
import '../../services/staff_task_service.dart';
import '../../services/timetable_service.dart';
import '../../theme.dart';

/// Localised label for a task priority (display only; stored value uses
/// `priority.name`, so it is unaffected).
String taskPriorityLabel(BuildContext context, TaskPriority p) => switch (p) {
      TaskPriority.high => context.tr('priorityHigh'),
      TaskPriority.medium => context.tr('priorityMedium'),
      TaskPriority.low => context.tr('priorityLow'),
    };

class CreateStaffTaskScreen extends StatefulWidget {
  final String schoolId;
  final String creatorEmail;
  final String creatorRole;
  final String creatorName;
  final bool isPersonal;

  /// When non-null, the screen edits this task instead of creating a new one.
  final StaffTask? existing;

  const CreateStaffTaskScreen({
    super.key,
    required this.schoolId,
    required this.creatorEmail,
    required this.creatorRole,
    required this.creatorName,
    this.isPersonal = false,
    this.existing,
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
  final List<String> _selectedTargetRoles = [];

  List<String> _allClasses = [];
  final List<String> _selectedClasses = [];

  final List<Checkpoint> _checkpoints = [];
  final _checkpointCtrl = TextEditingController();

  bool _loading = true;
  String _searchQuery = '';

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    if (widget.isPersonal) {
      _selectedUserIds = [widget.creatorEmail.toLowerCase().trim()];
      _selectedUserNames = [widget.creatorName];
      _selectedUserRoles = [widget.creatorRole];
    }
    // Prefill from the task being edited.
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e.title;
      _descCtrl.text  = e.description;
      _notesCtrl.text = e.notes ?? '';
      _priority = e.priority;
      if (e.dueDate != null) _dueDate = e.dueDate!;
      _selectedUserIds   = List<String>.from(e.assignedToIds);
      _selectedUserNames = List<String>.from(e.assignedToNames);
      _selectedUserRoles = List<String>.from(e.assignedToRoles);
      _selectedTargetRoles.addAll(e.targetRoles);
      _selectedClasses.addAll(e.targetClasses);
      _checkpoints.addAll(e.checkpoints);
    }
    _loadData();
  }

  Future<void> _loadData() async {
    final teachers = await TimetableService.instance.getTeachers(schoolId: widget.schoolId);
    final coordinators = await TimetableService.instance.getCoordinators(widget.schoolId);
    final settings = await TimetableService.instance.getSettings(schoolId: widget.schoolId);
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
        title: Text(_isEdit
            ? context.tr('editTask')
            : (widget.isPersonal ? context.tr('newPersonalTask') : context.tr('createTaskTitle'))),
        backgroundColor: AppTheme.primaryDark,
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
                      decoration: InputDecoration(labelText: context.tr('taskTitleStar'), border: const OutlineInputBorder()),
                      validator: (v) => (v == null || v.isEmpty) ? context.tr('validationRequired') : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _descCtrl,
                      decoration: InputDecoration(labelText: context.tr('descriptionStar'), border: const OutlineInputBorder()),
                      maxLines: 3,
                      validator: (v) => (v == null || v.isEmpty) ? context.tr('validationRequired') : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _notesCtrl,
                      decoration: InputDecoration(labelText: context.tr('notesOptional'), border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<TaskPriority>(
                            value: _priority,
                            decoration: InputDecoration(labelText: context.tr('priorityLabel'), border: const OutlineInputBorder()),
                            items: TaskPriority.values.map((p) => DropdownMenuItem(value: p, child: Text(taskPriorityLabel(context, p)))).toList(),
                            onChanged: (v) => setState(() => _priority = v!),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: InkWell(
                            onTap: _pickDate,
                            child: InputDecorator(
                              decoration: InputDecoration(labelText: context.tr('dueDateLabel'), border: const OutlineInputBorder()),
                              child: Text('${_dueDate.day}/${_dueDate.month}/${_dueDate.year}'),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (!widget.isPersonal) ...[
                      const SizedBox(height: 24),
                      Text(context.tr('assignToStar'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _buildAssigneeSelector(),
                      const SizedBox(height: 24),
                      Text(context.tr('targetClassesOptional'), style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      _buildClassSelector(),
                    ],
                    const SizedBox(height: 24),
                    Text(context.tr('checkpointsSubtasks'), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    _buildCheckpointSection(),
                    const SizedBox(height: 40),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary, foregroundColor: Colors.white),
                        child: Text(_isEdit ? context.tr('saveChangesUpper') : context.tr('createTaskUpper'), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
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
        Text(context.tr('rolesAssignAll'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
        Wrap(
          spacing: 8,
          children: [
            FilterChip(
              label: Text(context.tr('allTeachers')),
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
              label: Text(context.tr('allCoordinators')),
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
        Text(context.tr('specificStaff'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 6),
        TextField(
          decoration: InputDecoration(
            hintText: 'Search staff by name or email...',
            prefixIcon: const Icon(Icons.search, size: 20),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          ),
          onChanged: (val) {
            setState(() {
              _searchQuery = val.toLowerCase().trim();
            });
          },
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ..._allCoordinators.where((c) {
              final email = (c['email'] as String? ?? '').toLowerCase().trim();
              final name = (c['name'] as String? ?? email).toLowerCase();
              final isSelected = _selectedUserIds.contains(email);
              if (isSelected) return true;
              if (_searchQuery.isEmpty) return true;
              return name.contains(_searchQuery) || email.contains(_searchQuery);
            }).map((c) {
              final email = (c['email'] as String? ?? '').toLowerCase().trim();
              final name = c['name'] as String? ?? email;
              final isSelected = _selectedUserIds.contains(email);
              return FilterChip(
                label: Text('$name ${context.tr('coordSuffix')}'),
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
            ..._allTeachers.where((t) {
              final email = t.email.toLowerCase().trim();
              final name = t.name.toLowerCase();
              final isSelected = _selectedUserIds.contains(email);
              if (isSelected) return true;
              if (_searchQuery.isEmpty) return true;
              return name.contains(_searchQuery) || email.contains(_searchQuery);
            }).map((t) {
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
                selectedColor: AppTheme.primary.withValues(alpha: 0.2),
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
              if (val) {
                _selectedClasses.add(c);
              } else {
                _selectedClasses.remove(c);
              }
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
                decoration: InputDecoration(hintText: context.tr('addCheckpoint'), border: const UnderlineInputBorder()),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('assignToAtLeastOne'))));
      return;
    }

    // Edit mode: patch the editable fields on the existing task, preserving
    // id / status / createdAt / creator.
    if (_isEdit) {
      await StaffTaskService().updateTaskFields(
        widget.schoolId,
        widget.existing!.id,
        {
          'title':           _titleCtrl.text.trim(),
          'description':     _descCtrl.text.trim(),
          'notes':           _notesCtrl.text.trim(),
          'priority':        _priority.name,
          'dueDate':         Timestamp.fromDate(_dueDate),
          'assignedToIds':   _selectedUserIds.map((e) => e.toLowerCase().trim()).toList(),
          'assignedToNames': _selectedUserNames,
          'assignedToRoles': _selectedUserRoles,
          'targetRoles':     _selectedTargetRoles,
          'targetClasses':   _selectedClasses,
          'checkpoints':     _checkpoints.map((c) => c.toJson()).toList(),
        },
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('taskUpdated'))));
      }
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('taskCreatedSuccess'))));
    }
  }
}
