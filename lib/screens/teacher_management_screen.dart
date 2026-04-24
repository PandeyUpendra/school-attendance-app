import 'package:flutter/material.dart';
import '../models/teacher.dart';
import '../models/timetable_entry.dart';
import '../services/timetable_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  Teacher Management List
// ─────────────────────────────────────────────────────────────────────────────

class TeacherManagementScreen extends StatefulWidget {
  const TeacherManagementScreen({super.key});

  @override
  State<TeacherManagementScreen> createState() =>
      _TeacherManagementScreenState();
}

class _TeacherManagementScreenState extends State<TeacherManagementScreen> {
  final _service = TimetableService();
  List<Teacher> _teachers = [];
  bool _loading = true;

  static const _colors = [
    Colors.teal, Colors.indigo, Colors.orange, Colors.pink,
    Colors.purple, Colors.green, Colors.red, Colors.brown,
    Colors.cyan, Colors.deepPurple,
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _service.getTeachers();
    if (!mounted) return;
    setState(() {
      _teachers = list;
      _loading  = false;
    });
  }

  // ── Open the Add/Edit dialog ─────────────────────────────────────────────

  Future<void> _openDialog({Teacher? existing}) async {
    final teacher = await showDialog<Teacher>(
      context: context,
      builder: (_) => _TeacherDialog(existing: existing),
    );
    if (teacher == null) return;

    // Duplicate class-teacher check
    if (teacher.isClassTeacher && teacher.classTeacherOf != null) {
      final duplicate = _teachers.firstWhere(
        (t) =>
            t.id != teacher.id &&
            t.isClassTeacher &&
            t.classTeacherOf == teacher.classTeacherOf,
        orElse: () =>
            const Teacher(id: '', name: '', subject: '', email: ''),
      );
      if (duplicate.id.isNotEmpty) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange),
              SizedBox(width: 8),
              Text('Conflict', style: TextStyle(fontSize: 16)),
            ]),
            content: Text(
              '${duplicate.name} is already the class teacher of '
              '${teacher.classTeacherOf!}.\n\n'
              'Please remove them as class teacher first.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange),
                child: const Text('OK',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
        return;
      }
    }

    if (existing == null) {
      await _service.addTeacher(teacher);
    } else {
      await _service.updateTeacher(teacher);
    }
    _load();
  }

  // ── Confirm + remove ─────────────────────────────────────────────────────

  Future<void> _confirmRemove(Teacher teacher) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Teacher'),
        content: Text(
            'Remove ${teacher.name}? Their timetable assignments will be cleared.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _service.removeTeacher(teacher.id);
      _load();
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('Manage Teachers'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openDialog(),
        icon: const Icon(Icons.person_add),
        label: const Text('Add Teacher'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _teachers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.people_outline,
                          size: 72, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text('No teachers yet',
                          style: TextStyle(
                              fontSize: 16, color: Colors.grey[500])),
                      const SizedBox(height: 6),
                      const Text('Tap the button below to add one'),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(0, 8, 0, 100),
                  itemCount: _teachers.length,
                  separatorBuilder: (_, __) =>
                      const Divider(height: 1, indent: 72),
                  itemBuilder: (_, i) {
                    final t     = _teachers[i];
                    final color = _colors[i % _colors.length];
                    return InkWell(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TeacherDetailScreen(
                              teacher: t,
                              color:   color,
                              onEdit: () async {
                                Navigator.pop(context);
                                await _openDialog(existing: t);
                              },
                              onDelete: () async {
                                Navigator.pop(context);
                                await _confirmRemove(t);
                              },
                            ),
                          ),
                        );
                        _load(); // refresh in case of edit
                      },
                      child: Container(
                        color: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        child: Row(children: [
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: color,
                            child: Text(t.name[0].toUpperCase(),
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18)),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                              Row(children: [
                                Expanded(
                                  child: Text(t.name,
                                      style: const TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600)),
                                ),
                                if (t.isClassTeacher)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.teal.shade50,
                                      borderRadius:
                                          BorderRadius.circular(20),
                                      border: Border.all(
                                          color: Colors.teal.shade300),
                                    ),
                                    child: Text('Class Teacher',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color:
                                                Colors.teal.shade700)),
                                  ),
                              ]),
                              const SizedBox(height: 2),
                              Text(
                                [
                                  t.subject,
                                  if (t.section.isNotEmpty)
                                    'Sec ${t.section}',
                                  if (t.isClassTeacher &&
                                      t.classTeacherOf != null)
                                    t.classTeacherOf!,
                                ].join('  ·  '),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600),
                              ),
                              if (t.email.isNotEmpty)
                                Text(t.email,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade400)),
                            ]),
                          ),
                          Icon(Icons.chevron_right,
                              color: Colors.grey.shade400, size: 20),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Teacher Detail Screen
// ─────────────────────────────────────────────────────────────────────────────

class TeacherDetailScreen extends StatefulWidget {
  final Teacher      teacher;
  final Color        color;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const TeacherDetailScreen({
    super.key,
    required this.teacher,
    required this.color,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<TeacherDetailScreen> createState() => _TeacherDetailScreenState();
}

class _TeacherDetailScreenState extends State<TeacherDetailScreen> {
  final _service = TimetableService();

  List<String>  _classes   = [];
  int           _bellCount = 8;
  Map<String, Map<String, Map<int, TimetableEntry>>> _timetable = {};
  List<Teacher> _allTeachers = [];
  bool   _loading     = true;
  String _selectedDay = _currentDay();

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'
  ];
  static const _dayAbbr = {
    'Monday': 'Mon', 'Tuesday': 'Tue', 'Wednesday': 'Wed',
    'Thursday': 'Thu', 'Friday': 'Fri', 'Saturday': 'Sat',
  };

  static String _currentDay() {
    const map = {
      1: 'Monday', 2: 'Tuesday', 3: 'Wednesday',
      4: 'Thursday', 5: 'Friday', 6: 'Saturday',
    };
    return map[DateTime.now().weekday] ?? 'Monday';
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final settings = await _service.getSettings();
    final tt       = await _service.getTimetable();
    final teachers = await _service.getTeachers();
    if (!mounted) return;
    setState(() {
      _classes     = List<String>.from(settings['classes'] as List);
      _bellCount   = settings['numberOfBells'] as int;
      _timetable   = tt;
      _allTeachers = teachers;
      _loading     = false;
    });
  }

  String _subjectLabel(TimetableEntry? e) {
    if (e == null || e.isEmpty) return '';
    if (e.subject?.isNotEmpty == true) return e.subject!;
    final t = _allTeachers.firstWhere((t) => t.id == e.teacherId,
        orElse: () =>
            Teacher(id: '', name: '', subject: '', email: ''));
    return t.subject;
  }

  List<_Slot> get _mySlots {
    final tid = widget.teacher.id;
    final slots = <_Slot>[];
    for (final cls in _classes) {
      for (int b = 1; b <= _bellCount; b++) {
        final entry = _timetable[cls]?[_selectedDay]?[b];
        if (entry?.teacherId == tid) {
          slots.add(_Slot(
            bell:      b,
            className: cls,
            subject:   _subjectLabel(entry),
          ));
        }
      }
    }
    slots.sort((a, b) => a.bell.compareTo(b.bell));
    return slots;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.teacher;
    final c = widget.color;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: Text(t.name,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.bold)),
        backgroundColor: c,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: widget.onEdit,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 32),
              children: [
                // ── Hero header ────────────────────────────────────────────
                Container(
                  color: c,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                  child: Column(children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: Colors.white.withOpacity(0.25),
                      child: Text(
                        t.name[0].toUpperCase(),
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 30),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(t.name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(t.subject,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 14)),
                  ]),
                ),

                const SizedBox(height: 12),

                // ── Info card ──────────────────────────────────────────────
                _infoCard([
                  if (t.email.isNotEmpty)
                    _InfoRow(
                        Icons.email_outlined, 'Email', t.email),
                  if (t.isClassTeacher &&
                      t.classTeacherOf != null) ...[
                    _InfoRow(Icons.class_outlined, 'Class Teacher of',
                        t.classTeacherOf!),
                    if (t.section.isNotEmpty)
                      _InfoRow(Icons.group_work_outlined, 'Section',
                          t.section),
                  ],
                  if (!t.isClassTeacher)
                    _InfoRow(Icons.person_outline, 'Role',
                        'Subject Teacher'),
                ]),

                const SizedBox(height: 12),

                // ── Timetable section ──────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text('TIMETABLE',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500,
                          letterSpacing: 0.8)),
                ),

                // Day selector
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      children: _days.map((d) {
                        final sel = d == _selectedDay;
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _selectedDay = d),
                          child: AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 150),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: sel ? c : Colors.grey.shade100,
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: Border.all(
                                  color: sel
                                      ? c
                                      : Colors.grey.shade300),
                            ),
                            child: Text(_dayAbbr[d]!,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: sel
                                        ? Colors.white
                                        : Colors.grey.shade600)),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),

                const Divider(height: 1),

                // Slots
                Builder(builder: (_) {
                  final slots = _mySlots;
                  if (slots.isEmpty) {
                    return Container(
                      color: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          vertical: 28),
                      child: Column(children: [
                        Icon(Icons.event_available_outlined,
                            size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text(
                            'No classes on ${_dayAbbr[_selectedDay]}',
                            style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey.shade400)),
                      ]),
                    );
                  }
                  return Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    child: Column(
                      children: [
                        for (int i = 0; i < slots.length; i++) ...[
                          _SlotRow(slot: slots[i], color: c),
                          if (i < slots.length - 1)
                            const Divider(height: 20),
                        ],
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 24),

                // ── Delete button ──────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red),
                    label: const Text('Delete Teacher',
                        style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _infoCard(List<Widget> rows) {
    if (rows.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Column(children: [
        for (int i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1) const Divider(height: 16),
        ],
      ]),
    );
  }
}

// ── Info row ──────────────────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label, value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 18, color: Colors.grey.shade400),
      const SizedBox(width: 10),
      Text('$label: ',
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
      Expanded(
        child: Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis),
      ),
    ]);
  }
}

// ── Slot row ──────────────────────────────────────────────────────────────────

class _Slot {
  final int    bell;
  final String className;
  final String subject;
  const _Slot(
      {required this.bell,
      required this.className,
      required this.subject});
}

class _SlotRow extends StatelessWidget {
  final _Slot slot;
  final Color color;
  const _SlotRow({required this.slot, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 36, height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('${slot.bell}',
            style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15)),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(slot.className,
              style: const TextStyle(
                  fontSize: 14, fontWeight: FontWeight.w600)),
          if (slot.subject.isNotEmpty)
            Text(slot.subject,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500)),
        ]),
      ),
      Text('Bell ${slot.bell}',
          style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500)),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Add / Edit Teacher Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _TeacherDialog extends StatefulWidget {
  final Teacher? existing;
  const _TeacherDialog({this.existing});

  @override
  State<_TeacherDialog> createState() => _TeacherDialogState();
}

class _TeacherDialogState extends State<_TeacherDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _subjectCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _sectionCtrl;
  final TextEditingController _newClassCtrl = TextEditingController();
  late bool _isClassTeacher;
  String? _classTeacherOf;
  List<String> _classes = [];
  bool _loadingClasses = true;
  bool _showAddClass   = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final t = widget.existing;
    _nameCtrl       = TextEditingController(text: t?.name ?? '');
    _subjectCtrl    = TextEditingController(text: t?.subject ?? '');
    _emailCtrl      = TextEditingController(text: t?.email ?? '');
    _sectionCtrl    = TextEditingController(text: t?.section ?? '');
    _isClassTeacher = t?.isClassTeacher ?? false;
    _classTeacherOf = t?.classTeacherOf;
    _loadClasses();
  }

  Future<void> _loadClasses() async {
    final settings = await TimetableService().getSettings();
    if (!mounted) return;
    final classes = List<String>.from(settings['classes'] as List);
    setState(() {
      _classes = classes;
      if (_classTeacherOf != null &&
          !classes.contains(_classTeacherOf)) {
        _classTeacherOf = null;
      }
      _loadingClasses = false;
    });
  }

  Future<void> _addNewClass() async {
    final name = _newClassCtrl.text.trim();
    if (name.isEmpty) return;
    if (_classes.contains(name)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Class already exists')));
      return;
    }
    final settings = await TimetableService().getSettings();
    final classes =
        List<String>.from(settings['classes'] as List)..add(name);
    settings['classes']        = classes;
    settings['numberOfBells']  =
        (settings['bells'] as List? ?? []).length;
    await TimetableService().saveSettings(settings);
    if (!mounted) return;
    setState(() {
      _classes        = classes;
      _classTeacherOf = name;
      _newClassCtrl.clear();
      _showAddClass   = false;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _subjectCtrl.dispose();
    _emailCtrl.dispose();
    _sectionCtrl.dispose();
    _newClassCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit Teacher' : 'Add Teacher'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                    labelText: 'Full Name',
                    prefixIcon: Icon(Icons.person_outline)),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(
                    labelText: 'Subject',
                    prefixIcon: Icon(Icons.book_outlined)),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined)),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Required';
                  if (!v.contains('@')) return 'Enter a valid email';
                  return null;
                },
              ),
              const SizedBox(height: 8),

              // ── Class Teacher toggle ────────────────────────────────────
              Container(
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: _isClassTeacher
                      ? Colors.teal.shade50
                      : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: _isClassTeacher
                          ? Colors.teal.shade300
                          : Colors.grey.shade300),
                ),
                child: SwitchListTile(
                  value: _isClassTeacher,
                  onChanged: (v) => setState(() {
                    _isClassTeacher = v;
                    if (!v) {
                      _classTeacherOf = null;
                      _sectionCtrl.clear();
                    }
                  }),
                  activeColor: Colors.teal,
                  title: Text(
                    'Class Teacher',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _isClassTeacher
                            ? Colors.teal.shade700
                            : Colors.grey.shade700),
                  ),
                  subtitle: Text(
                    _isClassTeacher
                        ? 'Can add & manage students'
                        : 'Cannot add students',
                    style: TextStyle(
                        fontSize: 11,
                        color: _isClassTeacher
                            ? Colors.teal.shade600
                            : Colors.grey.shade500),
                  ),
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 2),
                ),
              ),

              // ── Class Teacher fields ────────────────────────────────────
              if (_isClassTeacher) ...[
                const SizedBox(height: 10),
                if (_loadingClasses)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  if (_classes.isNotEmpty && !_showAddClass)
                    DropdownButtonFormField<String>(
                      value: _classTeacherOf,
                      decoration: InputDecoration(
                        labelText: 'Class Teacher of',
                        prefixIcon: const Icon(Icons.class_outlined),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      hint: const Text('Select class'),
                      items: _classes
                          .map((c) => DropdownMenuItem(
                              value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) =>
                          setState(() => _classTeacherOf = v),
                      validator: (_) =>
                          _isClassTeacher &&
                                  _classTeacherOf == null &&
                                  _classes.isNotEmpty &&
                                  !_showAddClass
                              ? 'Select a class'
                              : null,
                    ),

                  if (_showAddClass || _classes.isEmpty) ...[
                    if (_classes.isNotEmpty) const SizedBox(height: 6),
                    Row(children: [
                      Expanded(
                        child: TextField(
                          controller: _newClassCtrl,
                          decoration: InputDecoration(
                            labelText: 'New class name',
                            hintText: 'e.g. Class 6A',
                            prefixIcon: const Icon(
                                Icons.add_circle_outline,
                                color: Colors.teal),
                            border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                          ),
                          textCapitalization: TextCapitalization.words,
                          onSubmitted: (_) => _addNewClass(),
                          autofocus: _classes.isEmpty,
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: _addNewClass,
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 15),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(10))),
                        child: const Text('Add'),
                      ),
                    ]),
                    if (_showAddClass && _classes.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => setState(() {
                            _showAddClass = false;
                            _newClassCtrl.clear();
                          }),
                          child: const Text('Cancel',
                              style: TextStyle(fontSize: 12)),
                        ),
                      ),
                  ],

                  if (_classes.isNotEmpty && !_showAddClass)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        onPressed: () =>
                            setState(() => _showAddClass = true),
                        icon: const Icon(Icons.add, size: 15),
                        label: const Text('Add new class',
                            style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(
                            foregroundColor: Colors.teal,
                            padding:
                                const EdgeInsets.only(top: 4)),
                      ),
                    ),
                ],

                // Section BELOW class selector
                const SizedBox(height: 12),
                TextFormField(
                  controller: _sectionCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Section (optional)',
                      prefixIcon: Icon(Icons.group_work_outlined),
                      hintText: 'e.g. A, B, C'),
                  textCapitalization: TextCapitalization.characters,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final teacher = Teacher(
                id: widget.existing?.id ??
                    DateTime.now().millisecondsSinceEpoch.toString(),
                name:    _nameCtrl.text.trim(),
                subject: _subjectCtrl.text.trim(),
                email:
                    _emailCtrl.text.trim().toLowerCase(),
                section: _sectionCtrl.text.trim(),
                isClassTeacher: _isClassTeacher,
                classTeacherOf:
                    _isClassTeacher ? _classTeacherOf : null,
              );
              Navigator.pop(context, teacher);
            }
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white),
          child: Text(_isEdit ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
