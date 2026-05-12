import 'package:flutter/material.dart';
import '../../models/staff_task.dart';
import '../../services/staff_task_service.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';
import 'create_staff_task_screen.dart';
import 'staff_task_detail_screen.dart';

class StaffTaskManagementScreen extends StatefulWidget {
  const StaffTaskManagementScreen({super.key});

  @override
  State<StaffTaskManagementScreen> createState() => _StaffTaskManagementScreenState();
}

class _StaffTaskManagementScreenState extends State<StaffTaskManagementScreen> {
  String _userEmail = '';
  String _userRole = '';
  String _userName = '';
  String _schoolId = '';
  bool _loading = true;

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
        _schoolId = session['schoolId'] ?? '';
        _loading = false;
      });
    }
  }


  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    int tabCount = _userRole == 'principal' ? 4 : (_userRole == 'coordinator' ? 4 : 3);

    return DefaultTabController(
      length: tabCount,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Task Management'),
          backgroundColor: AppTheme.primary,
          foregroundColor: Colors.white,
          bottom: TabBar(
            isScrollable: true,
            tabs: _buildTabs(),
            indicatorColor: Colors.white,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
          ),
        ),
        body: TabBarView(
          children: _buildTabViews(),
        ),
        floatingActionButton: (_userRole == 'principal' || _userRole == 'coordinator')
            ? FloatingActionButton(
                onPressed: () => _navigateToCreateTask(),
                backgroundColor: AppTheme.primary,
                child: const Icon(Icons.add_task, color: Colors.white),
              )
            : FloatingActionButton(
                onPressed: () => _navigateToCreatePersonalTask(),
                backgroundColor: AppTheme.primary,
                child: const Icon(Icons.add, color: Colors.white),
                tooltip: 'Add Personal Task',
              ),
      ),
    );
  }

  List<Widget> _buildTabs() {
    if (_userRole == 'principal') {
      return [
        const Tab(text: 'Assigned by Me'),
        const Tab(text: 'Personal'),
        const Tab(text: 'Completed'),
        const Tab(text: 'Overdue'),
      ];
    } else if (_userRole == 'coordinator') {
      return [
        const Tab(text: 'Assigned to Me'),
        const Tab(text: 'Assigned by Me'),
        const Tab(text: 'Personal'),
        const Tab(text: 'Completed & Overdue'),
      ];
    } else {
      return [
        const Tab(text: 'Assigned to Me'),
        const Tab(text: 'Personal'),
        const Tab(text: 'Completed & Overdue'),
      ];
    }
  }

  List<Widget> _buildTabViews() {
    if (_userRole == 'principal') {
      return [
        _TaskList(stream: StaffTaskService().getTasksCreatedBy(_schoolId, _userEmail), schoolId: _schoolId, filter: (t) => t.status != TaskStatus.completed && t.status != TaskStatus.overdue && (t.assignedToIds.any((id) => id != _userEmail) || t.assignedToRoles.any((r) => r != _userRole))),
        _TaskList(stream: StaffTaskService().getPersonalTasks(_schoolId, _userEmail), schoolId: _schoolId),
        _TaskList(stream: StaffTaskService().getTasksCreatedBy(_schoolId, _userEmail), schoolId: _schoolId, filter: (t) => t.status == TaskStatus.completed),
        _TaskList(stream: StaffTaskService().getTasksCreatedBy(_schoolId, _userEmail), schoolId: _schoolId, filter: (t) => t.status == TaskStatus.overdue),
      ];
    } else if (_userRole == 'coordinator') {
      return [
        _TaskList(stream: StaffTaskService().getTasksAssignedTo(_schoolId, _userEmail, _userRole), schoolId: _schoolId, filter: (t) => t.createdBy != _userEmail && t.status != TaskStatus.completed),
        _TaskList(stream: StaffTaskService().getTasksCreatedBy(_schoolId, _userEmail), schoolId: _schoolId, filter: (t) => (t.assignedToIds.any((id) => id != _userEmail) || t.assignedToRoles.any((r) => r != _userRole)) && t.status != TaskStatus.completed),
        _TaskList(stream: StaffTaskService().getPersonalTasks(_schoolId, _userEmail), schoolId: _schoolId),
        _TaskList(stream: StaffTaskService().getTasksAssignedTo(_schoolId, _userEmail, _userRole), schoolId: _schoolId, filter: (t) => t.status == TaskStatus.completed || t.status == TaskStatus.overdue),
      ];
    } else {
      return [
        _TaskList(stream: StaffTaskService().getTasksAssignedTo(_schoolId, _userEmail, _userRole), schoolId: _schoolId, filter: (t) => t.createdBy != _userEmail && t.status != TaskStatus.completed),
        _TaskList(stream: StaffTaskService().getPersonalTasks(_schoolId, _userEmail), schoolId: _schoolId),
        _TaskList(stream: StaffTaskService().getTasksAssignedTo(_schoolId, _userEmail, _userRole), schoolId: _schoolId, filter: (t) => t.status == TaskStatus.completed || t.status == TaskStatus.overdue),
      ];
    }
  }


  void _navigateToCreateTask() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateStaffTaskScreen(schoolId: _schoolId, creatorEmail: _userEmail, creatorRole: _userRole, creatorName: _userName)),
    );
  }

  void _navigateToCreatePersonalTask() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => CreateStaffTaskScreen(schoolId: _schoolId, creatorEmail: _userEmail, creatorRole: _userRole, creatorName: _userName, isPersonal: true)),
    );
  }

}

class _TaskList extends StatelessWidget {
  final Stream<List<StaffTask>> stream;
  final String schoolId;
  final bool Function(StaffTask)? filter;

  const _TaskList({required this.stream, required this.schoolId, this.filter});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<StaffTask>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        var tasks = snapshot.data ?? [];
        if (filter != null) {
          tasks = tasks.where(filter!).toList();
        }

        if (tasks.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.assignment_turned_in_outlined, size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text('No tasks found', style: TextStyle(color: Colors.grey.shade500)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final task = tasks[index];
            return _StaffTaskTile(task: task, schoolId: schoolId);
          },
        );
      },
    );
  }
}


class _StaffTaskTile extends StatelessWidget {
  final StaffTask task;
  final String schoolId;

  const _StaffTaskTile({required this.task, required this.schoolId});

  @override
  Widget build(BuildContext context) {
    Color priorityColor;
    switch (task.priority) {
      case TaskPriority.high:
        priorityColor = Colors.red;
        break;
      case TaskPriority.medium:
        priorityColor = Colors.orange;
        break;
      case TaskPriority.low:
        priorityColor = Colors.green;
        break;
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => StaffTaskDetailScreen(
                schoolId: schoolId,
                taskId: task.id,
              ),
            ),
          );
        },

        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: priorityColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      task.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  _StatusBadge(status: task.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                task.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Due: ${task.dueDate.day}/${task.dueDate.month}/${task.dueDate.year}',
                        style: TextStyle(fontSize: 12, color: task.status == TaskStatus.overdue ? Colors.red : Colors.grey.shade700, fontWeight: FontWeight.w600),
                      ),
                      if (task.assignedToNames.isNotEmpty)
                        Text(
                          'To: ${task.assignedToNames.join(", ")}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                  if (task.checkpoints.isNotEmpty)
                    Text(
                      '${task.checkpoints.where((c) => c.isCompleted).length}/${task.checkpoints.length} done',
                      style: TextStyle(fontSize: 12, color: AppTheme.primary, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final TaskStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case TaskStatus.pending:
        color = Colors.blue;
        label = 'Pending';
        break;
      case TaskStatus.inProgress:
        color = Colors.orange;
        label = 'In Progress';
        break;
      case TaskStatus.completed:
        color = Colors.green;
        label = 'Completed';
        break;
      case TaskStatus.overdue:
        color = Colors.red;
        label = 'Overdue';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color, width: 0.5)),
      child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
    );
  }
}
