import 'dart:io';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../providers/school_settings_provider.dart';
import '../../services/auth_service.dart';
import '../../services/school_settings_service.dart';
import '../../theme.dart';
import '../../utils/validators.dart';
import '../../widgets/email_text_form_field.dart';
import '../../widgets/index_building_notice.dart';
import '../../widgets/managed_dropdown.dart';

class EditSchoolSettingsScreen extends StatefulWidget {
  const EditSchoolSettingsScreen({super.key});

  @override
  State<EditSchoolSettingsScreen> createState() =>
      _EditSchoolSettingsScreenState();
}

class _EditSchoolSettingsScreenState extends State<EditSchoolSettingsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _onTabSaved() => setState(() => _editing = false);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('School Settings'),
        actions: [
          if (!_editing)
            TextButton.icon(
              icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
              label: const Text(
                'Edit',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              onPressed: () => setState(() => _editing = true),
            )
          else
            TextButton.icon(
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              label: const Text('Cancel', style: TextStyle(color: Colors.white)),
              onPressed: () => setState(() => _editing = false),
            ),
          const SizedBox(width: 4),
        ],
        bottom: TabBar(
          controller: _tab,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(fontWeight: FontWeight.w600),
          tabs: const [
            Tab(text: 'Basic Info'),
            Tab(text: 'Address'),
            Tab(text: 'Academic'),
            Tab(text: 'Fees'),
            Tab(text: 'Communication'),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!_editing)
            Container(
              color: AppTheme.warning.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: const Row(children: [
                Icon(Icons.lock_outline, size: 16, color: AppTheme.warning),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'View only — tap Edit to make changes',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.warning,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ]),
            ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _BasicInfoTab(editing: _editing, onSaved: _onTabSaved),
                _AddressTab(editing: _editing, onSaved: _onTabSaved),
                _AcademicTab(editing: _editing, onSaved: _onTabSaved),
                _FeesTab(editing: _editing, onSaved: _onTabSaved),
                _CommunicationTab(editing: _editing, onSaved: _onTabSaved),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Basic Info Tab ────────────────────────────────────────────────────────────

class _BasicInfoTab extends StatefulWidget {
  final bool editing;
  final VoidCallback onSaved;

  const _BasicInfoTab({required this.editing, required this.onSaved});

  @override
  State<_BasicInfoTab> createState() => _BasicInfoTabState();
}

class _BasicInfoTabState extends State<_BasicInfoTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late TextEditingController _nameCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;
  late TextEditingController _principalCtrl;
  late TextEditingController _yearCtrl;
  late TextEditingController _tagCtrl;
  late TextEditingController _websiteCtrl;
  String _type = 'Private';
  String _board = 'CBSE';
  String _logoUrl = '';
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _init = false;

  static const _types = ['Private', 'Government', 'Government-Aided'];
  static const _boards = ['CBSE', 'ICSE', 'State Board', 'IGCSE', 'Other'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      final p = context.read<SchoolSettingsProvider>();
      _nameCtrl = TextEditingController(text: p.schoolName == 'My School' ? '' : p.schoolName);
      _phoneCtrl = TextEditingController(text: p.schoolPhone);
      _emailCtrl = TextEditingController(text: p.schoolEmail);
      _principalCtrl = TextEditingController(text: p.principalName);
      _yearCtrl = TextEditingController(text: p.establishedYear);
      _tagCtrl = TextEditingController(text: p.schoolTagline);
      _websiteCtrl = TextEditingController(text: p.schoolWebsite);
      // Accept custom (managed) values too — the dropdown surfaces them as
      // options, so don't force them back to the built-in default on load.
      _type  = p.schoolType.isNotEmpty ? p.schoolType : 'Private';
      _board = p.board.isNotEmpty       ? p.board      : 'CBSE';
      _logoUrl = p.schoolLogo;
      _init = true;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _phoneCtrl.dispose(); _emailCtrl.dispose();
    _principalCtrl.dispose(); _yearCtrl.dispose();
    _tagCtrl.dispose(); _websiteCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickLogo() async {
    final file = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (file == null) return;
    setState(() => _uploadingLogo = true);
    try {
      final ref = FirebaseStorage.instance
          .ref('schools/${AuthService.currentSchoolId}/logo.jpg');
      await ref.putFile(File(file.path));
      final url = await ref.getDownloadURL();
      setState(() { _logoUrl = url; _uploadingLogo = false; });
    } catch (e) {
      setState(() => _uploadingLogo = false);
      if (mounted) _snack('Logo upload failed: $e');
    }
  }

  Future<void> _save() async {
    final emailVal = _emailCtrl.text.trim();
    if (emailVal.isNotEmpty && !Validators.isValidEmail(emailVal)) {
      _snack('Enter a valid email address');
      return;
    }
    setState(() => _saving = true);
    try {
      final p = context.read<SchoolSettingsProvider>();
      final old = p.rawSchool;
      final data = {
        'schoolName': _nameCtrl.text.trim(),
        'logoUrl': _logoUrl,
        'phone': _phoneCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'principalName': _principalCtrl.text.trim(),
        'establishedYear': _yearCtrl.text.trim(),
        'tagline': _tagCtrl.text.trim(),
        'website': _websiteCtrl.text.trim(),
        'schoolType': _type,
        'board': _board,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      await p.updateSchoolSettings(data);
      final uid = (await AuthService().getSession())?['email'] as String? ?? 'owner';
      for (final k in data.keys) {
        if (k == 'updatedAt') continue;
        final oldVal = old[k]?.toString() ?? '';
        final newVal = data[k]?.toString() ?? '';
        if (oldVal != newVal) await p.logChange(k, oldVal, newVal, uid);
      }
      if (mounted) {
        _snack('Settings updated', success: true);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _logoPicker(),
        const SizedBox(height: 16),
        _field(_nameCtrl, 'School Name *', Icons.school_outlined, readOnly: !widget.editing),
        const SizedBox(height: 12),
        _dropdown('School Type', _type, _types, Icons.business_outlined,
            (v) => setState(() => _type = v!), enabled: widget.editing,
            fieldKey: 'school_type'),
        const SizedBox(height: 12),
        _dropdown('Board', _board, _boards, Icons.menu_book_outlined,
            (v) => setState(() => _board = v!), enabled: widget.editing,
            fieldKey: 'school_board'),
        const SizedBox(height: 12),
        _field(_phoneCtrl, 'Phone', Icons.phone_outlined,
            type: TextInputType.phone, readOnly: !widget.editing),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        EmailTextFormField(
          controller: _emailCtrl,
          readOnly: !widget.editing,
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        _field(_principalCtrl, 'Principal Name', Icons.person_outline,
            readOnly: !widget.editing),
        const SizedBox(height: 12),
        _field(_yearCtrl, 'Established Year', Icons.calendar_today_outlined,
            type: TextInputType.number, readOnly: !widget.editing),
        const SizedBox(height: 12),
        _field(_tagCtrl, 'School Tagline', Icons.format_quote_outlined,
            readOnly: !widget.editing),
        const SizedBox(height: 12),
        _field(_websiteCtrl, 'Website', Icons.language_outlined,
            type: TextInputType.url, readOnly: !widget.editing),
        const SizedBox(height: 20),
        if (widget.editing) _saveBtn(_saving, _save),
        const SizedBox(height: 16),
        _changeLogSection(),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _logoPicker() {
    return Center(
      child: GestureDetector(
        onTap: widget.editing ? _pickLogo : null,
        child: Stack(children: [
          CircleAvatar(
            radius: 44,
            backgroundColor: AppTheme.primaryLight.withValues(alpha: 0.3),
            backgroundImage: _logoUrl.isNotEmpty ? CachedNetworkImageProvider(_logoUrl) : null,
            child: _logoUrl.isEmpty
                ? const Icon(Icons.school, size: 36, color: AppTheme.primary)
                : null,
          ),
          if (_uploadingLogo)
            const Positioned.fill(
              child: CircleAvatar(
                  radius: 44,
                  backgroundColor: Colors.black38,
                  child: CircularProgressIndicator(color: Colors.white)),
            ),
          if (widget.editing)
            Positioned(
              bottom: 0, right: 0,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: const BoxDecoration(color: AppTheme.primary, shape: BoxShape.circle),
                child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
              ),
            ),
        ]),
      ),
    );
  }
}

// ── Address Tab ───────────────────────────────────────────────────────────────

class _AddressTab extends StatefulWidget {
  final bool editing;
  final VoidCallback onSaved;

  const _AddressTab({required this.editing, required this.onSaved});

  @override
  State<_AddressTab> createState() => _AddressTabState();
}

class _AddressTabState extends State<_AddressTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late TextEditingController _addrCtrl;
  late TextEditingController _cityCtrl;
  late TextEditingController _pinCtrl;
  String _state = '';
  bool _saving = false;
  bool _init = false;

  static const _states = [
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
    'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka',
    'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya',
    'Mizoram', 'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim',
    'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
    'West Bengal', 'Andaman and Nicobar Islands', 'Chandigarh',
    'Dadra and Nagar Haveli and Daman and Diu', 'Delhi',
    'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry',
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      final p = context.read<SchoolSettingsProvider>();
      _addrCtrl = TextEditingController(text: p.schoolAddress);
      _cityCtrl = TextEditingController(text: p.schoolCity);
      _pinCtrl = TextEditingController(text: p.schoolPinCode);
      _state = _states.contains(p.schoolState) ? p.schoolState : '';
      _init = true;
    }
  }

  @override
  void dispose() {
    _addrCtrl.dispose(); _cityCtrl.dispose(); _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final p = context.read<SchoolSettingsProvider>();
      await p.updateSchoolSettings({
        'address': _addrCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'state': _state,
        'pinCode': _pinCtrl.text.trim(),
      });
      if (mounted) {
        _snack('Settings updated', success: true);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        _field(_addrCtrl, 'Full Address', Icons.location_on_outlined,
            maxLines: 3, readOnly: !widget.editing),
        const SizedBox(height: 12),
        _field(_cityCtrl, 'City', Icons.location_city_outlined,
            readOnly: !widget.editing),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _state.isEmpty ? null : _state,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'State',
            prefixIcon: const Icon(Icons.map_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
          items: _states.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: widget.editing ? (v) => setState(() => _state = v ?? '') : null,
        ),
        const SizedBox(height: 12),
        _field(_pinCtrl, 'PIN Code', Icons.pin_drop_outlined,
            type: TextInputType.number, maxLength: 6, readOnly: !widget.editing),
        const SizedBox(height: 20),
        if (widget.editing) _saveBtn(_saving, _save),
        const SizedBox(height: 32),
      ]),
    );
  }
}

// ── Academic Tab ──────────────────────────────────────────────────────────────

class _AcademicTab extends StatefulWidget {
  final bool editing;
  final VoidCallback onSaved;

  const _AcademicTab({required this.editing, required this.onSaved});

  @override
  State<_AcademicTab> createState() => _AcademicTabState();
}

class _AcademicTabState extends State<_AcademicTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Index into _classOptions (0 = Nursery, 1 = LKG, 2 = UKG, 3 = Class 1 … 14 = Class 12)
  int _fromIdx = 3, _toIdx = 12;
  int _periods = 8, _duration = 45, _lunch = 4;
  List<String> _sections = ['A'];
  String _yearStart = 'April';
  String _workingDays = 'Mon-Sat';
  bool _saving = false;
  bool _init = false;

  static const _sectionOptions = ['A', 'B', 'C', 'D', 'E'];
  static const _durations = [35, 40, 45, 50];

  /// Full ordered list of class options — pre-primary first, then Class 1-12.
  static const _classOptions = [
    'Nursery', 'LKG', 'UKG',
    'Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5', 'Class 6',
    'Class 7', 'Class 8', 'Class 9', 'Class 10', 'Class 11', 'Class 12',
  ];
  static const _prePrimary = ['Nursery', 'LKG', 'UKG'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      final p = context.read<SchoolSettingsProvider>();
      // Prefer label-based fields (new format); fall back to integer → index math.
      _fromIdx = _classOptions.indexOf(p.classesFromLabel);
      if (_fromIdx < 0) _fromIdx = (p.classesFrom + 2).clamp(0, _classOptions.length - 1);
      _toIdx = _classOptions.indexOf(p.classesToLabel);
      if (_toIdx < 0) _toIdx = (p.classesTo + 2).clamp(0, _classOptions.length - 1);
      _periods = p.periodsPerDay;
      _duration = _durations.contains(p.periodDuration) ? p.periodDuration : 45;
      _lunch = p.lunchAfterPeriod;
      _sections = List.from(p.sections);
      _yearStart = p.academicYearStart;
      _workingDays = p.workingDays;
      _init = true;
    }
  }

  Future<void> _save() async {
    if (_sections.isEmpty) { _snack('Select at least one section'); return; }
    if (_toIdx < _fromIdx) { _snack('Class To must be ≥ Class From'); return; }

    final p = context.read<SchoolSettingsProvider>();
    final oldClasses = List<String>.from(p.classList);

    final periodsChanged = p.periodsPerDay != _periods;
    if (periodsChanged && mounted) {
      final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        title: const Text('Change Periods Per Day?'),
        content: const Text(
            'This will reset the timetable. All existing assignments will be cleared.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue')),
        ],
      ));
      if (ok != true) return;
    }

    final newClasses = _generateClassList();

    final removed = oldClasses.where((c) => !newClasses.contains(c)).toList();
    if (removed.isNotEmpty && mounted) {
      final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        title: const Text('Remove Classes?'),
        content: Text(
            'Classes ${removed.join(", ")} will be hidden from class lists but student data will not be deleted. Continue?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Continue')),
        ],
      ));
      if (ok != true) return;
    }

    setState(() => _saving = true);
    try {
      final svc = SchoolSettingsService();
      await p.updateAcademicSettings({
        // New label-based fields (supports pre-primary)
        'classesFromLabel': _classOptions[_fromIdx],
        'classesToLabel': _classOptions[_toIdx],
        // Legacy integer fields for backward compat (Class N → N; pre-primary → 1)
        'classesFrom': _fromIdx >= 3 ? (_fromIdx - 2) : 1,
        'classesTo': _toIdx >= 3 ? (_toIdx - 2) : 1,
        'sections': _sections,
        'classList': newClasses,
        'academicYearStart': _yearStart,
        'workingDays': _workingDays,
        'periodsPerDay': _periods,
        'periodDuration': _duration,
        'lunchAfterPeriod': _lunch,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final added = newClasses.where((c) => !oldClasses.contains(c)).toList();
      await Future.wait(added.map((c) => svc.createClassDocument(c)));
      if (mounted) {
        _snack('Settings updated', success: true);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) _snack('Error: $e');
    }
    if (mounted) setState(() => _saving = false);
  }

  List<String> _generateClassList() {
    final list = <String>[];
    for (int i = _fromIdx; i <= _toIdx; i++) {
      final label = _classOptions[i];
      for (final s in _sections) {
        if (_prePrimary.contains(label)) {
          list.add('$label-$s'); // e.g. "Nursery-A", "LKG-B"
        } else {
          final num = label.replaceFirst('Class ', '');
          list.add('$num-$s'); // e.g. "1-A", "2-B"
        }
      }
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final maxLunch = _periods.clamp(1, 10);
    if (_lunch > maxLunch) _lunch = maxLunch;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('Class Range'),
        Row(children: [
          Expanded(child: _classDropdown('From', _fromIdx, (v) => setState(() => _fromIdx = v))),
          const SizedBox(width: 12),
          Expanded(child: _classDropdown('To', _toIdx, (v) => setState(() => _toIdx = v))),
        ]),
        const SizedBox(height: 16),
        _sectionLabel('Sections'),
        Wrap(
          spacing: 8,
          children: _sectionOptions.map((s) {
            final sel = _sections.contains(s);
            return FilterChip(
              label: Text(s),
              selected: sel,
              selectedColor: AppTheme.primaryLight,
              onSelected: widget.editing
                  ? (v) => setState(() {
                        if (v) { _sections.add(s); _sections.sort(); } else { _sections.remove(s); }
                      })
                  : null,
            );
          }).toList(),
        ),
        if (_sections.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Classes: ${_generateClassList().join(", ")}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
        const SizedBox(height: 16),
        _sectionLabel('Academic Year Starts'),
        _segmented(['April', 'June'], _yearStart, (v) => setState(() => _yearStart = v)),
        const SizedBox(height: 16),
        _sectionLabel('Working Days'),
        _segmented(['Mon-Sat', 'Mon-Fri'], _workingDays, (v) => setState(() => _workingDays = v)),
        const SizedBox(height: 16),
        _sectionLabel('Periods Per Day  ($_periods)'),
        Slider(
          value: _periods.toDouble(), min: 4, max: 10, divisions: 6,
          label: '$_periods', activeColor: AppTheme.primary,
          onChanged: widget.editing ? (v) => setState(() => _periods = v.round()) : null,
        ),
        const SizedBox(height: 8),
        _intDropdown('Period Duration', _duration, _durations, suffix: ' min',
            onChanged: (v) => setState(() => _duration = v)),
        const SizedBox(height: 12),
        _intDropdown('Lunch After Period', _lunch.clamp(1, maxLunch),
            List.generate(maxLunch, (i) => i + 1), prefix: 'After period ',
            onChanged: (v) => setState(() => _lunch = v)),
        const SizedBox(height: 20),
        if (widget.editing) _saveBtn(_saving, _save),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _classDropdown(String label, int idxValue, void Function(int) onChanged) =>
      DropdownButtonFormField<int>(
        value: idxValue.clamp(0, _classOptions.length - 1),
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
        items: List.generate(
          _classOptions.length,
          (i) => DropdownMenuItem(value: i, child: Text(_classOptions[i])),
        ),
        onChanged: widget.editing ? (v) { if (v != null) onChanged(v); } : null,
      );

  Widget _segmented(List<String> opts, String sel, void Function(String) onSel) =>
      Row(
        children: opts.map((o) {
          final s = o == sel;
          return Expanded(
            child: GestureDetector(
              onTap: widget.editing ? () => onSel(o) : null,
              child: Container(
                margin: EdgeInsets.only(right: o == opts.last ? 0 : 8),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: s ? AppTheme.primary : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: s ? AppTheme.primary : Colors.grey.shade300),
                ),
                child: Text(o,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        color: s ? Colors.white : Colors.black87,
                        fontWeight: s ? FontWeight.bold : FontWeight.normal)),
              ),
            ),
          );
        }).toList(),
      );

  Widget _intDropdown(String label, int value, List<int> items,
      {String prefix = '', String suffix = '', required void Function(int) onChanged}) =>
      DropdownButtonFormField<int>(
        value: items.contains(value) ? value : items.first,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          isDense: true,
        ),
        items: items.map((n) => DropdownMenuItem(value: n, child: Text('$prefix$n$suffix'))).toList(),
        onChanged: widget.editing ? (v) { if (v != null) onChanged(v); } : null,
      );
}

// ── Fees Tab ──────────────────────────────────────────────────────────────────

class _FeesTab extends StatefulWidget {
  final bool editing;
  final VoidCallback onSaved;

  const _FeesTab({required this.editing, required this.onSaved});

  @override
  State<_FeesTab> createState() => _FeesTabState();
}

class _FeesTabState extends State<_FeesTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _freq = 'Monthly';
  int _dueDate = 10;
  bool _lateEnabled = false;
  late TextEditingController _lateCtrl;
  int _reminder = 7;
  bool _saving = false;
  bool _init = false;

  static const _freqs = ['Monthly', 'Quarterly', 'Half-Yearly', 'Annually'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      final p = context.read<SchoolSettingsProvider>();
      _freq = _freqs.contains(p.feeFrequency) ? p.feeFrequency : 'Monthly';
      _dueDate = p.feeDueDate.clamp(1, 28);
      _lateEnabled = p.lateFeeEnabled;
      _lateCtrl = TextEditingController(text: p.lateFeePerDay > 0 ? '${p.lateFeePerDay}' : '');
      _reminder = p.reminderDaysBefore.clamp(1, 14);
      _init = true;
    }
  }

  @override
  void dispose() { _lateCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final p = context.read<SchoolSettingsProvider>();
      await p.updateFeeSettings({
        'feeFrequency': _freq,
        'feeDueDate': _dueDate,
        'lateFeeEnabled': _lateEnabled,
        'lateFeePerDay': int.tryParse(_lateCtrl.text) ?? 0,
        'reminderDaysBefore': _reminder,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        _snack('Settings updated', success: true);
        widget.onSaved();
      }
    } catch (e) { if (mounted) _snack('Error: $e'); }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _sectionLabel('Fee Frequency'),
        Wrap(spacing: 8, runSpacing: 8, children: _freqs.map((f) {
          final sel = f == _freq;
          return ChoiceChip(
            label: Text(f), selected: sel,
            selectedColor: AppTheme.primaryLight,
            onSelected: widget.editing ? (_) => setState(() => _freq = f) : null,
          );
        }).toList()),
        const SizedBox(height: 16),
        DropdownButtonFormField<int>(
          value: _dueDate,
          decoration: InputDecoration(
            labelText: 'Fee Due Date',
            prefixIcon: const Icon(Icons.calendar_today_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
          items: List.generate(28, (i) => i + 1)
              .map((n) => DropdownMenuItem(value: n, child: Text('${_ordinal(n)} of month')))
              .toList(),
          onChanged: widget.editing ? (v) { if (v != null) setState(() => _dueDate = v); } : null,
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Late Fee Applicable',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Switch(value: _lateEnabled, activeColor: AppTheme.primary,
              onChanged: widget.editing ? (v) => setState(() => _lateEnabled = v) : null),
        ]),
        if (_lateEnabled) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _lateCtrl,
            keyboardType: TextInputType.number,
            readOnly: !widget.editing,
            decoration: InputDecoration(
              labelText: 'Late Fee Per Day (₹)',
              prefixIcon: const Icon(Icons.currency_rupee_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _sectionLabel('Reminder Days Before Due  ($_reminder days)'),
        Slider(value: _reminder.toDouble(), min: 1, max: 14, divisions: 13,
            label: '$_reminder', activeColor: AppTheme.primary,
            onChanged: widget.editing ? (v) => setState(() => _reminder = v.round()) : null),
        const SizedBox(height: 20),
        if (widget.editing) _saveBtn(_saving, _save),
        const SizedBox(height: 32),
      ]),
    );
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    switch (n % 10) {
      case 1: return '${n}st'; case 2: return '${n}nd'; case 3: return '${n}rd';
      default: return '${n}th';
    }
  }
}

// ── Communication Tab ─────────────────────────────────────────────────────────

class _CommunicationTab extends StatefulWidget {
  final bool editing;
  final VoidCallback onSaved;

  const _CommunicationTab({required this.editing, required this.onSaved});

  @override
  State<_CommunicationTab> createState() => _CommunicationTabState();
}

class _CommunicationTabState extends State<_CommunicationTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  bool _whatsapp = false;
  bool _bus = false;
  String _lang = 'English';
  int _routes = 0;
  late TextEditingController _waCtrl;
  bool _saving = false;
  bool _init = false;

  static const _langs = ['English', 'Hindi', 'Both'];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_init) {
      final p = context.read<SchoolSettingsProvider>();
      _whatsapp = p.whatsappEnabled;
      _bus = p.busServiceAvailable;
      _lang = _langs.contains(p.preferredLanguage) ? p.preferredLanguage : 'English';
      _routes = p.busRouteCount;
      _waCtrl = TextEditingController(text: p.schoolWhatsapp);
      _init = true;
    }
  }

  @override
  void dispose() { _waCtrl.dispose(); super.dispose(); }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final p = context.read<SchoolSettingsProvider>();
      await p.updateCommSettings({
        'whatsappEnabled': _whatsapp,
        'schoolWhatsapp': _waCtrl.text.trim(),
        'preferredLanguage': _lang,
        'busServiceAvailable': _bus,
        'busRouteCount': _routes,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        _snack('Settings updated', success: true);
        widget.onSaved();
      }
    } catch (e) { if (mounted) _snack('Error: $e'); }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _toggleRow('WhatsApp Notifications', _whatsapp,
            (v) => setState(() => _whatsapp = v)),
        if (_whatsapp) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _waCtrl,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            readOnly: !widget.editing,
            decoration: InputDecoration(
              labelText: 'WhatsApp Number',
              prefixText: '+91 ',
              prefixIcon: const Icon(Icons.chat_outlined),
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _sectionLabel('Preferred Language'),
        Wrap(spacing: 8, children: _langs.map((l) {
          final sel = l == _lang;
          return ChoiceChip(
            label: Text(l), selected: sel,
            selectedColor: AppTheme.primaryLight,
            onSelected: widget.editing ? (_) => setState(() => _lang = l) : null,
          );
        }).toList()),
        const SizedBox(height: 16),
        _toggleRow('Bus Service Available', _bus, (v) => setState(() => _bus = v)),
        if (_bus) ...[
          const SizedBox(height: 12),
          _sectionLabel('Number of Routes  ($_routes)'),
          Slider(value: _routes.clamp(1, 50).toDouble(), min: 1, max: 50,
              activeColor: AppTheme.primary,
              onChanged: widget.editing ? (v) => setState(() => _routes = v.round()) : null),
        ],
        const SizedBox(height: 20),
        if (widget.editing) _saveBtn(_saving, _save),
        const SizedBox(height: 16),
        _changeLogSection(),
        const SizedBox(height: 32),
      ]),
    );
  }

  Widget _toggleRow(String label, bool value, void Function(bool) onChanged) =>
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        Switch(
          value: value,
          activeColor: AppTheme.primary,
          onChanged: widget.editing ? onChanged : null,
        ),
      ]);
}

// ── Shared helpers ────────────────────────────────────────────────────────────

Widget _sectionLabel(String t) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(t, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
    );

Widget _field(
  TextEditingController ctrl,
  String label,
  IconData icon, {
  TextInputType type = TextInputType.text,
  int? maxLength,
  int maxLines = 1,
  bool readOnly = false,
}) =>
    TextField(
      controller: ctrl,
      keyboardType: type,
      maxLength: maxLength,
      maxLines: maxLines,
      readOnly: readOnly,
      textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        counterText: '',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
    );

Widget _dropdown(
  String label,
  String value,
  List<String> items,
  IconData icon,
  void Function(String?) onChanged, {
  bool enabled = true,
  String? fieldKey,
}) {
  // When editing and a fieldKey is supplied, use the user-manageable dropdown
  // so owners can add/remove school-specific values (board, type, …). When
  // read-only (not editing) fall back to a plain, non-interactive dropdown.
  if (enabled && fieldKey != null) {
    return ManagedDropdown(
      fieldKey: fieldKey,
      label: label,
      seeds: items,
      value: value,
      prefixIcon: Icon(icon),
      onChanged: onChanged,
    );
  }
  return DropdownButtonFormField<String>(
    value: value,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      isDense: true,
    ),
    items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
    onChanged: enabled ? onChanged : null,
  );
}

Widget _saveBtn(bool saving, VoidCallback onSave) => SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.save_outlined),
        label: Text(saving ? 'Saving…' : 'Save Settings'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        onPressed: saving ? null : onSave,
      ),
    );

Widget _changeLogSection() {
  return Builder(builder: (context) {
    final p = context.read<SchoolSettingsProvider>();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: p.watchChangeLog(),
      builder: (context, snap) {
        // Optional section — stay hidden while the composite index builds
        // rather than pushing a notice into the settings form.
        if (snap.hasError && isIndexBuildingError(snap.error)) {
          return const SizedBox.shrink();
        }
        final logs = snap.data ?? [];
        if (logs.isEmpty) return const SizedBox.shrink();
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Recent Changes',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          ),
          ...logs.map((log) {
            final ts = log['changedAt'];
            String dateStr = '';
            if (ts is Timestamp) {
              final dt = ts.toDate();
              dateStr = '${dt.day}/${dt.month}/${dt.year}';
            }
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 3)],
              ),
              child: Row(children: [
                const Icon(Icons.history, size: 14, color: Colors.grey),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${log['field']} changed by ${log['changedBy'] ?? 'owner'}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                Text(dateStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            );
          }),
        ]);
      },
    );
  });
}

extension _SnackExt on State {
  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppTheme.success : AppTheme.danger,
    ));
  }
}
