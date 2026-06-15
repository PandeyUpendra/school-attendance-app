import 'package:flutter/material.dart';
import '../../theme.dart';
import '../../l10n/app_strings.dart';
import '../../models/todo_item.dart';
import '../../services/todo_service.dart';
import '../../shared/widgets/index_building_notice.dart';
import '../../shared/utils/app_transitions.dart';

class TodoListScreen extends StatefulWidget {
  final String userId;
  final String role;

  const TodoListScreen({
    super.key,
    required this.userId,
    required this.role,
  });

  @override
  State<TodoListScreen> createState() => _TodoListScreenState();
}

class _TodoListScreenState extends State<TodoListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _svc = TodoService();

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(context.tr('myTodoList')),
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tab,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Completed'),
          ],
        ),
      ),
      body: StreamBuilder<List<TodoItem>>(
        stream: _svc.streamForUser(widget.userId),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppTheme.primary));
          }
          if (snap.hasError && isIndexBuildingError(snap.error)) {
            return IndexBuildingNotice(onRetry: () => setState(() {}));
          }
          final all = snap.data ?? [];
          final pending   = all.where((t) => !t.isCompleted).toList();
          final completed = all.where((t) => t.isCompleted).toList();

          return PremiumTabBarView(
            controller: _tab,
            children: [
              _TodoTab(
                items: pending,
                emptyMessage: 'No pending tasks.\nTap + to add one.',
                svc: _svc,
              ),
              _TodoTab(
                items: completed,
                emptyMessage: 'No completed tasks yet.',
                svc: _svc,
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddSheet(context),
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text(context.tr('addTask')),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddTodoSheet(
        userId: widget.userId,
        role: widget.role,
        svc: _svc,
      ),
    );
  }
}

// ── Pending / Completed tab ───────────────────────────────────────────────────

class _TodoTab extends StatelessWidget {
  final List<TodoItem> items;
  final String emptyMessage;
  final TodoService svc;

  const _TodoTab({
    required this.items,
    required this.emptyMessage,
    required this.svc,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline,
                size: 56, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text(
              emptyMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
            ),
          ],
        ),
      );
    }

    // Group: overdue → today → upcoming
    final overdue  = items.where((t) => t.isOverdue).toList();
    final today    = items.where((t) => t.isDueToday).toList();
    final upcoming = items
        .where((t) => !t.isDueToday && !t.isOverdue && t.dueDate != null)
        .toList();
    final noDue    = items.where((t) => t.dueDate == null).toList();

    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      children: [
        if (overdue.isNotEmpty) ...[
          const _GroupHeader('OVERDUE', color: AppTheme.danger),
          ..._tiles(overdue),
        ],
        if (today.isNotEmpty) ...[
          const _GroupHeader('TODAY', color: AppTheme.warning),
          ..._tiles(today),
        ],
        if (upcoming.isNotEmpty) ...[
          const _GroupHeader('UPCOMING', color: AppTheme.primary),
          ..._tiles(upcoming),
        ],
        if (noDue.isNotEmpty) ...[
          const _GroupHeader('NO DUE DATE', color: Colors.grey),
          ..._tiles(noDue),
        ],
      ],
    );
  }

  List<Widget> _tiles(List<TodoItem> items) =>
      items.map((item) => _TodoTile(item: item, svc: svc)).toList();
}

class _GroupHeader extends StatelessWidget {
  final String label;
  final Color color;
  const _GroupHeader(this.label, {required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(children: [
        Container(
          width: 3, height: 14,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
                letterSpacing: 0.9)),
      ]),
    );
  }
}

// ── Todo tile ─────────────────────────────────────────────────────────────────

class _TodoTile extends StatelessWidget {
  final TodoItem item;
  final TodoService svc;

  const _TodoTile({required this.item, required this.svc});

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppTheme.danger,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      confirmDismiss: (_) async {
        return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(context.tr('deleteTaskTitle')),
            content: Text(context.tr('deleteItemTitleConfirm').replaceAll('{title}', item.title)),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(context.tr('cancel'))),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: Text(context.tr('delete'),
                      style: const TextStyle(color: AppTheme.danger))),
            ],
          ),
        );
      },
      onDismissed: (_) => svc.deleteTodo(item.id),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: item.isOverdue && !item.isCompleted
              ? Border.all(color: AppTheme.danger.withValues(alpha: 0.4))
              : item.isDueToday && !item.isCompleted
                  ? Border.all(color: AppTheme.warning.withValues(alpha: 0.5))
                  : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showEditSheet(context),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              // Checkbox
              GestureDetector(
                onTap: () => svc.toggleComplete(item.id, !item.isCompleted),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: item.isCompleted
                        ? AppTheme.success
                        : Colors.transparent,
                    border: Border.all(
                      color: item.isCompleted
                          ? AppTheme.success
                          : Colors.grey.shade400,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: item.isCompleted
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 14)
                      : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        decoration: item.isCompleted
                            ? TextDecoration.lineThrough
                            : null,
                        color: item.isCompleted
                            ? Colors.grey
                            : Colors.black87,
                      ),
                    ),
                    if (item.dueDate != null) ...[
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 11,
                          color: item.isOverdue && !item.isCompleted
                              ? AppTheme.danger
                              : item.isDueToday && !item.isCompleted
                                  ? AppTheme.warning
                                  : Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(item.dueDate!),
                          style: TextStyle(
                            fontSize: 11,
                            color: item.isOverdue && !item.isCompleted
                                ? AppTheme.danger
                                : item.isDueToday && !item.isCompleted
                                    ? AppTheme.warning
                                    : Colors.grey.shade500,
                            fontWeight: item.isDueToday || item.isOverdue
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                        if (item.isOverdue && !item.isCompleted) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppTheme.danger.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(context.tr('overdue'),
                                style: const TextStyle(
                                    fontSize: 9,
                                    color: AppTheme.danger,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ]),
                    ],
                  ],
                ),
              ),
              // Reminder bell
              GestureDetector(
                onTap: () =>
                    svc.updateReminder(item.id, !item.reminderEnabled),
                child: Tooltip(
                  message: item.reminderEnabled
                      ? 'Reminder on'
                      : 'Reminder off',
                  child: Icon(
                    item.reminderEnabled
                        ? Icons.notifications_active
                        : Icons.notifications_off_outlined,
                    size: 20,
                    color: item.reminderEnabled
                        ? AppTheme.primary
                        : Colors.grey.shade400,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right,
                  color: Colors.grey.shade300, size: 18),
            ]),
          ),
        ),
      ),
    );
  }

  void _showEditSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditTodoSheet(item: item, svc: svc),
    );
  }

  String _formatDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) {
      return 'Today';
    }
    final tomorrow = now.add(const Duration(days: 1));
    if (d.year == tomorrow.year &&
        d.month == tomorrow.month &&
        d.day == tomorrow.day) {
      return 'Tomorrow';
    }
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ── Add Todo bottom sheet ─────────────────────────────────────────────────────

class _AddTodoSheet extends StatefulWidget {
  final String userId;
  final String role;
  final TodoService svc;

  const _AddTodoSheet({
    required this.userId,
    required this.role,
    required this.svc,
  });

  @override
  State<_AddTodoSheet> createState() => _AddTodoSheetState();
}

class _AddTodoSheetState extends State<_AddTodoSheet> {
  static const String _customKey = '__custom__';

  final _customCtrl = TextEditingController();
  String? _selectedTemplate;
  bool _isCustom = false;
  DateTime? _dueDate;
  bool _reminderEnabled = false;
  bool _saving = false;

  List<String> get _templates =>
      TodoTemplates.forRole(widget.role);

  @override
  void dispose() {
    _customCtrl.dispose();
    super.dispose();
  }

  String? get _effectiveTitle {
    if (_isCustom) {
      return _customCtrl.text.trim().isEmpty
          ? null
          : _customCtrl.text.trim();
    }
    return _selectedTemplate;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    final title = _effectiveTitle;
    if (title == null) return;
    setState(() => _saving = true);
    try {
      await widget.svc.addTodo(TodoItem(
        id: '',
        userId: widget.userId,
        role: widget.role,
        title: title,
        isCustom: _isCustom,
        dueDate: _dueDate,
        reminderEnabled: _reminderEnabled,
        isCompleted: false,
        createdAt: DateTime.now(),
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.tr('failedToSaveTaskError').replaceAll('{error}', e.toString())),
          backgroundColor: Colors.red.shade700,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _effectiveTitle != null;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),

            Row(children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.add_task,
                    color: AppTheme.primary, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(context.tr('addTodoTask'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold))),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ]),
            const SizedBox(height: 16),

            // Template dropdown
            Text(context.tr('selectTask'),
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: BorderRadius.circular(10),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  hint: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Text(context.tr('chooseCommonTaskHint'),
                        style: TextStyle(fontSize: 14)),
                  ),
                  value: _isCustom
                      ? _customKey
                      : _selectedTemplate,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  borderRadius: BorderRadius.circular(10),
                  items: [
                    ..._templates.map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(t, style: const TextStyle(fontSize: 14)),
                        )),
                    DropdownMenuItem(
                      value: _customKey,
                      child: Row(children: [
                        Icon(Icons.edit_outlined,
                            size: 16, color: AppTheme.primary),
                        SizedBox(width: 8),
                        Text(context.tr('addCustomTaskHint'),
                            style: TextStyle(
                                fontSize: 14,
                                color: AppTheme.primary,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ),
                  ],
                  onChanged: (val) {
                    setState(() {
                      if (val == _customKey) {
                        _isCustom = true;
                        _selectedTemplate = null;
                      } else {
                        _isCustom = false;
                        _selectedTemplate = val;
                      }
                    });
                  },
                ),
              ),
            ),

            // Custom text field
            if (_isCustom) ...[
              const SizedBox(height: 12),
              TextField(
                controller: _customCtrl,
                autofocus: true,
                maxLength: 120,
                textInputAction: TextInputAction.done,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) {
                  if (!_saving && _effectiveTitle != null) _save();
                },
                decoration: InputDecoration(
                  labelText: context.tr('customTaskTitle'),
                  hintText: context.tr('customTaskHint'),
                  prefixIcon: const Icon(Icons.edit_outlined),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10)),
                  isDense: true,
                  counterText: '',
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Date picker row
            Row(children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(context.tr('dueDate'),
                  style:
                      const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              const Spacer(),
              GestureDetector(
                onTap: _pickDate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: _dueDate != null
                        ? AppTheme.primary.withValues(alpha: 0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: _dueDate != null
                            ? AppTheme.primary.withValues(alpha: 0.3)
                            : Colors.grey.shade300),
                  ),
                  child: Text(
                    _dueDate != null
                        ? _fmtDate(_dueDate!)
                        : 'Set date',
                    style: TextStyle(
                      fontSize: 13,
                      color: _dueDate != null
                          ? AppTheme.primary
                          : Colors.grey.shade600,
                      fontWeight: _dueDate != null
                          ? FontWeight.w600
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
              if (_dueDate != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => setState(() => _dueDate = null),
                  child: const Icon(Icons.close,
                      size: 16, color: Colors.grey),
                ),
              ],
            ]),

            const SizedBox(height: 14),

            // Reminder toggle
            Row(children: [
              Icon(
                _reminderEnabled
                    ? Icons.notifications_active
                    : Icons.notifications_off_outlined,
                size: 18,
                color:
                    _reminderEnabled ? AppTheme.primary : Colors.grey,
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(context.tr('dailyReminder'),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                Text(
                  _reminderEnabled
                      ? 'Shown on home screen every day until done'
                      : 'No reminder',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500),
                ),
              ]),
              const Spacer(),
              Switch(
                value: _reminderEnabled,
                onChanged: (v) => setState(() => _reminderEnabled = v),
                activeColor: AppTheme.primary,
              ),
            ]),

            const SizedBox(height: 20),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: canSave && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check),
                label: Text(_saving ? 'Saving…' : 'Add Task'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}

// ── Edit Todo bottom sheet ────────────────────────────────────────────────────

class _EditTodoSheet extends StatefulWidget {
  final TodoItem item;
  final TodoService svc;

  const _EditTodoSheet({required this.item, required this.svc});

  @override
  State<_EditTodoSheet> createState() => _EditTodoSheetState();
}

class _EditTodoSheetState extends State<_EditTodoSheet> {
  late DateTime? _dueDate;
  late bool _reminder;

  @override
  void initState() {
    super.initState();
    _dueDate = widget.item.dueDate;
    _reminder = widget.item.reminderEnabled;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppTheme.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  Future<void> _save() async {
    await widget.svc.updateDueDate(widget.item.id, _dueDate);
    await widget.svc.updateReminder(widget.item.id, _reminder);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit_outlined,
                  color: AppTheme.primary, size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.item.title,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
          const SizedBox(height: 16),

          // Due date
          Row(children: [
            const Icon(Icons.calendar_today_outlined,
                size: 18, color: AppTheme.primary),
            const SizedBox(width: 8),
            Text(context.tr('dueDate'),
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            const Spacer(),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: _dueDate != null
                      ? AppTheme.primary.withValues(alpha: 0.1)
                      : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: _dueDate != null
                          ? AppTheme.primary.withValues(alpha: 0.3)
                          : Colors.grey.shade300),
                ),
                child: Text(
                  _dueDate != null ? _fmtDate(_dueDate!) : 'Set date',
                  style: TextStyle(
                    fontSize: 13,
                    color: _dueDate != null
                        ? AppTheme.primary
                        : Colors.grey.shade600,
                    fontWeight: _dueDate != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                ),
              ),
            ),
            if (_dueDate != null) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _dueDate = null),
                child: const Icon(Icons.close, size: 16, color: Colors.grey),
              ),
            ],
          ]),

          const SizedBox(height: 14),

          // Reminder
          Row(children: [
            Icon(
              _reminder
                  ? Icons.notifications_active
                  : Icons.notifications_off_outlined,
              size: 18,
              color: _reminder ? AppTheme.primary : Colors.grey,
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(context.tr('dailyReminder'),
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600)),
              Text(
                _reminder
                    ? 'Shown on home screen every day until done'
                    : 'No reminder',
                style:
                    TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ]),
            const Spacer(),
            Switch(
              value: _reminder,
              onChanged: (v) => setState(() => _reminder = v),
              activeColor: AppTheme.primary,
            ),
          ]),

          const SizedBox(height: 20),

          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(context.tr('deleteTaskTitle')),
                      content: Text(context.tr('deleteWidgetItemTitleConfirm').replaceAll('{title}', widget.item.title)),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(context.tr('cancel'))),
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(context.tr('delete'),
                                style: const TextStyle(color: AppTheme.danger))),
                      ],
                    ),
                  );
                  if (confirm == true && mounted) {
                    await widget.svc.deleteTodo(widget.item.id);
                    if (!mounted) return;
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  }
                },
                icon: const Icon(Icons.delete_outline, color: AppTheme.danger),
                label: Text(context.tr('delete'),
                    style: const TextStyle(color: AppTheme.danger)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.danger),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.check),
                label: Text(context.tr('save')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }
}
