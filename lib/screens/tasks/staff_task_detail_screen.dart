import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/staff_task.dart';
import '../../services/staff_task_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';

class StaffTaskDetailScreen extends StatefulWidget {
  final String schoolId;
  final String taskId;
  const StaffTaskDetailScreen({super.key, required this.schoolId, required this.taskId});

  @override
  State<StaffTaskDetailScreen> createState() => _StaffTaskDetailScreenState();
}

class _StaffTaskDetailScreenState extends State<StaffTaskDetailScreen> {
  String _userEmail = '';
  String _userRole = '';
  String _userName = '';
  final _updateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadUser();
  }

  Future<void> _loadUser() async {
    final session = await AuthService().getSession();
    if (session != null) {
      setState(() {
        _userEmail = session['email'] ?? '';
        _userRole = session['role'] ?? '';
        _userName = session['name'] ?? _userEmail;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('schools')
          .doc(widget.schoolId)
          .collection('staff_tasks')
          .doc(widget.taskId)
          .snapshots(),
      builder: (context, snapshot) {

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Scaffold(body: Center(child: Text('Task not found')));
        }

        final task = StaffTask.fromFirestore(snapshot.data!.data() as Map<String, dynamic>, snapshot.data!.id);
        final isCreator = task.createdBy == _userEmail;
        final isAssigned = task.assignedToIds.contains(_userEmail);
        final isOverdue = task.status == TaskStatus.overdue || (task.status != TaskStatus.completed && task.dueDate.isBefore(DateTime.now()));

        return Scaffold(
          appBar: AppBar(
            title: const Text('Task Details'),
            backgroundColor: isOverdue ? Colors.red : AppTheme.primary,
            foregroundColor: Colors.white,
            actions: [
              if (isCreator)
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(context, task),
                ),
            ],

          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isOverdue)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red)),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.red),
                        SizedBox(width: 8),
                        Text('OVERDUE TASK', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: Text(task.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    ),
                    _PriorityBadge(priority: task.priority),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Created by: ${task.creatorName} (${task.creatorRole})', style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                const SizedBox(height: 16),
                const Text('Description', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(task.description),
                if (task.notes?.isNotEmpty == true) ...[
                  const SizedBox(height: 16),
                  const Text('Notes', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(task.notes!, style: const TextStyle(fontStyle: FontStyle.italic)),
                ],
                const SizedBox(height: 24),
                _buildInfoSection(task),
                const SizedBox(height: 24),
                const Text('Status', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _buildStatusPicker(task),
                const SizedBox(height: 24),
                if (task.checkpoints.isNotEmpty) ...[
                  const Text('Checkpoints', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _buildCheckpoints(task),
                  const SizedBox(height: 24),
                ],
                const Text('Progress Updates', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _buildUpdatesList(task),
                const SizedBox(height: 12),
                _buildAddUpdateRow(task),
                const SizedBox(height: 40),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildInfoSection(StaffTask task) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _infoRow(Icons.calendar_today, 'Due Date', '${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year}'),
          const Divider(),
          _infoRow(Icons.people, 'Assigned To', task.assignedToNames.join(", ")),
          if (task.targetClasses.isNotEmpty) ...[
            const Divider(),
            _infoRow(Icons.class_outlined, 'Classes', task.targetClasses.join(", ")),
          ],
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppTheme.primary),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPicker(StaffTask task) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _statusButton(task, TaskStatus.pending, 'Pending', Colors.blue),
        _statusButton(task, TaskStatus.inProgress, 'In Progress', Colors.orange),
        _statusButton(task, TaskStatus.completed, 'Completed', Colors.green),
      ],
    );
  }

  Widget _statusButton(StaffTask task, TaskStatus status, String label, Color color) {
    bool isSelected = task.status == status;
    return InkWell(
      onTap: () => _updateStatus(task, status),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color),
        ),
        child: Text(label, style: TextStyle(color: isSelected ? Colors.white : color, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _buildCheckpoints(StaffTask task) {
    return Column(
      children: task.checkpoints.asMap().entries.map((entry) {
        int idx = entry.key;
        Checkpoint cp = entry.value;
        return CheckboxListTile(
          value: cp.isCompleted,
          title: Text(cp.title, style: TextStyle(decoration: cp.isCompleted ? TextDecoration.lineThrough : null)),
          onChanged: (val) => _toggleCheckpoint(task, idx, val ?? false),
          activeColor: AppTheme.primary,
          contentPadding: EdgeInsets.zero,
          dense: true,
        );
      }).toList(),
    );
  }

  Widget _buildUpdatesList(StaffTask task) {
    if (task.progressUpdates.isEmpty) {
      return Text('No updates yet', style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic, fontSize: 13));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: task.progressUpdates.map((update) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.arrow_right, size: 18, color: AppTheme.primary),
            Expanded(child: Text(update, style: const TextStyle(fontSize: 13))),
          ],
        ),
      )).toList(),
    );
  }

  Widget _buildAddUpdateRow(StaffTask task) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _updateCtrl,
            decoration: const InputDecoration(hintText: 'Add progress note...', border: UnderlineInputBorder()),
            style: const TextStyle(fontSize: 13),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.send, color: AppTheme.primary),
          onPressed: () => _addUpdate(task),
        ),
      ],
    );
  }

  void _updateStatus(StaffTask task, TaskStatus status) {
    if (task.status == status) return;
    StaffTaskService().updateTask(task.copyWith(status: status), _userEmail, _userName, _userRole);
  }

  void _toggleCheckpoint(StaffTask task, int index, bool isCompleted) {
    List<Checkpoint> newList = List.from(task.checkpoints);
    newList[index] = Checkpoint(title: newList[index].title, isCompleted: isCompleted);
    StaffTaskService().updateTask(task.copyWith(checkpoints: newList), _userEmail, _userName, _userRole);
  }

  void _addUpdate(StaffTask task) {
    if (_updateCtrl.text.trim().isEmpty) return;
    final now = DateTime.now();
    final timestamp = '${now.day}/${now.month} ${now.hour}:${now.minute}';
    final newUpdate = '[$timestamp] ${_updateCtrl.text.trim()}';

    List<String> updates = List.from(task.progressUpdates);
    updates.add(newUpdate);

    StaffTaskService().updateTask(task.copyWith(progressUpdates: updates), _userEmail, _userName, _userRole);
    _updateCtrl.clear();
  }

  void _confirmDelete(BuildContext context, StaffTask task) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Task'),
        content: const Text('Are you sure you want to delete this task? (It will be soft-deleted)'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              StaffTaskService().deleteTask(task, _userEmail, _userName, _userRole);
              Navigator.pop(ctx); // Dialog
              Navigator.pop(context); // Screen
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }

}

class _PriorityBadge extends StatelessWidget {
  final TaskPriority priority;
  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (priority) {
      case TaskPriority.high:
        color = Colors.red;
        break;
      case TaskPriority.medium:
        color = Colors.orange;
        break;
      case TaskPriority.low:
        color = Colors.green;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(priority.name.toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
