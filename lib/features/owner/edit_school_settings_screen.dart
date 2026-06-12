import 'dart:io';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../shared/providers/school_settings_provider.dart';
import '../../shared/providers/locale_provider.dart';
import '../../services/auth_service.dart';
import '../../services/school_settings_service.dart';
import '../../l10n/app_strings.dart';
import '../../theme.dart';
import '../../shared/utils/image_utils.dart';
import '../../shared/utils/validators.dart';
import '../../shared/widgets/email_text_form_field.dart';
import '../../shared/widgets/index_building_notice.dart';
import '../../shared/widgets/managed_dropdown.dart';

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
        backgroundColor: AppTheme.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(context.tr('schoolSettingsTitle')),
        actions: [
          if (!_editing)
            TextButton.icon(
              icon: const Icon(Icons.edit_outlined, color: Colors.white, size: 18),
              label: Text(
                context.tr('edit'),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
              ),
              onPressed: () => setState(() => _editing = true),
            )
          else
            TextButton.icon(
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              label: Text(context.tr('cancel'), style: const TextStyle(color: Colors.white)),
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
          tabs: [
            Tab(text: context.tr('tabBasicInfo')),
            Tab(text: context.tr('tabAddress')),
            Tab(text: context.tr('tabAcademic')),
            Tab(text: context.tr('tabFees')),
            Tab(text: context.tr('tabCommunication')),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!_editing)
            Container(
              color: AppTheme.warning.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                const Icon(Icons.lock_outline, size: 16, color: AppTheme.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.tr('viewOnlyWarning'),
                    style: const TextStyle(
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
      final bytes = await ImageUtils.compressAndStripExif(File(file.path), quality: 70);
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
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
      _snack(context.tr('enterValidEmailMsg'));
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
        _snack(context.tr('settingsUpdated'), success: true);
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
        _field(_nameCtrl, context.tr('schoolNameRequiredLabel'), Icons.school_outlined, readOnly: !widget.editing),
        const SizedBox(height: 12),
        _dropdown(context.tr('schoolTypeLabel'), _type, _types, Icons.business_outlined,
            (v) => setState(() => _type = v!), enabled: widget.editing,
            fieldKey: 'school_type'),
        const SizedBox(height: 12),
        _dropdown(context.tr('boardLabel'), _board, _boards, Icons.menu_book_outlined,
            (v) => setState(() => _board = v!), enabled: widget.editing,
            fieldKey: 'school_board'),
        const SizedBox(height: 12),
        _field(_phoneCtrl, context.tr('phoneLabel'), Icons.phone_outlined,
            type: TextInputType.phone, readOnly: !widget.editing),
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        EmailTextFormField(
          controller: _emailCtrl,
          readOnly: !widget.editing,
          decoration: InputDecoration(
            labelText: context.tr('emailLabel'),
            prefixIcon: const Icon(Icons.email_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        const SizedBox(height: 12),
        _field(_principalCtrl, context.tr('principalNameLabel'), Icons.person_outline,
            readOnly: !widget.editing),
        const SizedBox(height: 12),
        _field(_yearCtrl, context.tr('establishedYearEditLabel'), Icons.calendar_today_outlined,
            type: TextInputType.number, readOnly: !widget.editing),
        const SizedBox(height: 12),
        _field(_tagCtrl, context.tr('schoolTaglineEditLabel'), Icons.format_quote_outlined,
            readOnly: !widget.editing),
        const SizedBox(height: 12),
        _field(_websiteCtrl, context.tr('websiteLabel'), Icons.language_outlined,
            type: TextInputType.url, readOnly: !widget.editing),
        const SizedBox(height: 20),
        if (widget.editing) _saveBtn(context, _saving, _save),
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
        _snack(context.tr('settingsUpdated'), success: true);
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
        _field(_addrCtrl, context.tr('fullAddressLabel'), Icons.location_on_outlined,
            maxLines: 3, readOnly: !widget.editing),
        const SizedBox(height: 12),
        _field(_cityCtrl, context.tr('cityLabel'), Icons.location_city_outlined,
            readOnly: !widget.editing),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _state.isEmpty ? null : _state,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: context.tr('stateLabel'),
            prefixIcon: const Icon(Icons.map_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
          items: _states.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
          onChanged: widget.editing ? (v) => setState(() => _state = v ?? '') : null,
        ),
        const SizedBox(height: 12),
        _field(_pinCtrl, context.tr('pinCodeLabel'), Icons.pin_drop_outlined,
            type: TextInputType.number, maxLength: 6, readOnly: !widget.editing),
        const SizedBox(height: 20),
        if (widget.editing) _saveBtn(context, _saving, _save),
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
  List<String> _classList = [];
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
      _classList = List.from(p.classList);
      if (_classList.isEmpty) {
        _classList = _generateClassList();
      } else {
        _sortClassList();
      }
      _yearStart = p.academicYearStart;
      _workingDays = p.workingDays;
      _init = true;
    }
  }

  String _getClassPrefix(String label) {
    if (_prePrimary.contains(label)) {
      return label;
    } else {
      return label.replaceFirst('Class ', '');
    }
  }

  void _sortClassList() {
    _classList.sort((a, b) {
      final partsA = a.split('-');
      final partsB = b.split('-');
      final prefixA = partsA[0];
      final prefixB = partsB[0];
      final secA = partsA.length > 1 ? partsA[1] : '';
      final secB = partsB.length > 1 ? partsB[1] : '';

      final idxA = _classOptions.indexWhere((label) => _getClassPrefix(label) == prefixA);
      final idxB = _classOptions.indexWhere((label) => _getClassPrefix(label) == prefixB);

      if (idxA != idxB) {
        return idxA.compareTo(idxB);
      }
      return secA.compareTo(secB);
    });
  }

  void _syncClassListToRange() {
    if (_toIdx < _fromIdx) return;
    final validPrefixes = <String>{};
    for (int i = _fromIdx; i <= _toIdx; i++) {
      validPrefixes.add(_getClassPrefix(_classOptions[i]));
    }

    setState(() {
      _classList.removeWhere((item) {
        final parts = item.split('-');
        if (parts.isEmpty) return true;
        return !validPrefixes.contains(parts[0]);
      });

      for (int i = _fromIdx; i <= _toIdx; i++) {
        final prefix = _getClassPrefix(_classOptions[i]);
        final hasAny = _classList.any((item) => item.startsWith('$prefix-'));
        if (!hasAny) {
          for (final s in _sections) {
            _classList.add('$prefix-$s');
          }
        }
      }

      _sortClassList();
    });
  }

  void _addGlobalSection(String s) {
    setState(() {
      for (int i = _fromIdx; i <= _toIdx; i++) {
        final prefix = _getClassPrefix(_classOptions[i]);
        final item = '$prefix-$s';
        if (!_classList.contains(item)) {
          _classList.add(item);
        }
      }
      _sortClassList();
    });
  }

  void _removeGlobalSection(String s) {
    setState(() {
      _classList.removeWhere((item) => item.endsWith('-$s'));
    });
  }

  Future<void> _save() async {
    if (_sections.isEmpty) { _snack(context.tr('selectAtLeastOneSecMsg')); return; }
    if (_toIdx < _fromIdx) { _snack(context.tr('classToMinMsg')); return; }

    final p = context.read<SchoolSettingsProvider>();
    final oldClasses = List<String>.from(p.classList);

    final periodsChanged = p.periodsPerDay != _periods;
    if (periodsChanged && mounted) {
      final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        title: Text(context.tr('changePeriodsQ')),
        content: Text(context.tr('changePeriodsBody')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('cancel'))),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('btnContinue'))),
        ],
      ));
      if (ok != true) return;
    }

    final newClasses = List<String>.from(_classList);

    final removed = oldClasses.where((c) => !newClasses.contains(c)).toList();
    if (removed.isNotEmpty && mounted) {
      final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
        title: Text(context.tr('removeClassesQ')),
        content: Text(
            '${context.tr('removeClassesPrefix')} ${removed.join(", ")} ${context.tr('removeClassesSuffix')}'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(context.tr('cancel'))),
          ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr('btnContinue'))),
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
        _snack(context.tr('settingsUpdated'), success: true);
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
        _sectionLabel(context.tr('classRangeLabel')),
        Row(children: [
          Expanded(child: _classDropdown(context.tr('rangeFrom'), _fromIdx, (v) {
            setState(() => _fromIdx = v);
            _syncClassListToRange();
          })),
          const SizedBox(width: 12),
          Expanded(child: _classDropdown(context.tr('rangeTo'), _toIdx, (v) {
            setState(() => _toIdx = v);
            _syncClassListToRange();
          })),
        ]),
        const SizedBox(height: 16),
        _sectionLabel(context.tr('sectionsLabel')),
        Wrap(
          spacing: 8,
          children: _sectionOptions.map((s) {
            final sel = _sections.contains(s);
            return FilterChip(
              label: Text(s),
              selected: sel,
              selectedColor: AppTheme.primaryLight,
              onSelected: widget.editing
                  ? (v) {
                      if (v) {
                        setState(() {
                          _sections.add(s);
                          _sections.sort();
                        });
                        _addGlobalSection(s);
                      } else {
                        setState(() {
                          _sections.remove(s);
                        });
                        _removeGlobalSection(s);
                      }
                    }
                  : null,
            );
          }).toList(),
        ),
        if (_classList.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '${context.tr('classesLabel')}: ${_classList.join(", ")}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
        if (widget.editing && _toIdx >= _fromIdx) ...[
          const SizedBox(height: 20),
          _sectionLabel(context.tr('classWiseSectionsLabel')),
          const SizedBox(height: 4),
          Text(
            context.tr('classWiseSectionsDesc'),
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.border),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _toIdx - _fromIdx + 1,
              separatorBuilder: (_, __) => const Divider(color: AppTheme.border, height: 1),
              itemBuilder: (context, index) {
                final classIdx = _fromIdx + index;
                if (classIdx >= _classOptions.length) return const SizedBox.shrink();
                final label = _classOptions[classIdx];
                final prefix = _getClassPrefix(label);

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      Wrap(
                        spacing: 8,
                        children: _sectionOptions.map((s) {
                          final item = '$prefix-$s';
                          final isSelected = _classList.contains(item);
                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  final classSections = _classList
                                      .where((c) => c.startsWith('$prefix-'))
                                      .toList();
                                  if (classSections.length <= 1) {
                                    _snack(context.tr('selectAtLeastOneSecMsg'));
                                    return;
                                  }
                                  _classList.remove(item);
                                } else {
                                  _classList.add(item);
                                  _sortClassList();
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 32,
                              height: 32,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: isSelected ? AppTheme.primaryLight : Colors.grey.shade200,
                                shape: BoxShape.circle,
                              ),
                              child: Text(
                                s,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? AppTheme.primary : Colors.grey.shade700,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 16),
        _sectionLabel(context.tr('academicYearStartsLabel')),
        _segmented(['April', 'June'], _yearStart, (v) => setState(() => _yearStart = v)),
        const SizedBox(height: 16),
        _sectionLabel(context.tr('workingDaysLabel')),
        _segmented(['Mon-Sat', 'Mon-Fri'], _workingDays, (v) => setState(() => _workingDays = v)),
        const SizedBox(height: 16),
        _sectionLabel('${context.tr('periodsPerDayLabel')}  ($_periods)'),
        Slider(
          value: _periods.toDouble(), min: 4, max: 10, divisions: 6,
          label: '$_periods', activeColor: AppTheme.primary,
          onChanged: widget.editing ? (v) => setState(() => _periods = v.round()) : null,
        ),
        const SizedBox(height: 8),
        _intDropdown(context.tr('periodDurationLabel'), _duration, _durations, suffix: ' min',
            onChanged: (v) => setState(() => _duration = v)),
        const SizedBox(height: 12),
        _intDropdown(context.tr('lunchAfterPeriodLabel'), _lunch.clamp(1, maxLunch),
            List.generate(maxLunch, (i) => i + 1), prefix: context.tr('afterPeriodPrefixEdit'), suffix: context.tr('afterPeriodSuffixEdit'),
            onChanged: (v) => setState(() => _lunch = v)),
        const SizedBox(height: 20),
        if (widget.editing) _saveBtn(context, _saving, _save),
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
        _snack(context.tr('settingsUpdated'), success: true);
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
        _sectionLabel(context.tr('feeFrequencyLabel')),
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
            labelText: context.tr('feeDueDateLabel'),
            prefixIcon: const Icon(Icons.calendar_today_outlined),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
          items: List.generate(28, (i) => i + 1)
              .map((n) => DropdownMenuItem(value: n, child: Text(_dueDateText(context, n))))
              .toList(),
          onChanged: widget.editing ? (v) { if (v != null) setState(() => _dueDate = v); } : null,
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(context.tr('lateFeeApplicableLabel'),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          Switch(value: _lateEnabled, activeColor: AppTheme.primary,
              onChanged: widget.editing ? (v) => setState(() => _lateEnabled = v) : null),
        ]),
        if (_lateEnabled) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _lateCtrl,
            keyboardType: TextInputType.number,
            readOnly: !widget.editing,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: '${context.tr('lateFeePerDayEditLabel')} (₹)',
              prefixIcon: const Icon(Icons.currency_rupee_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _sectionLabel('${context.tr('reminderDaysBeforeLabel')}  ($_reminder ${context.tr('daysLower')})'),
        Slider(value: _reminder.toDouble(), min: 1, max: 14, divisions: 13,
            label: '$_reminder', activeColor: AppTheme.primary,
            onChanged: widget.editing ? (v) => setState(() => _reminder = v.round()) : null),
        const SizedBox(height: 20),
        if (widget.editing) _saveBtn(context, _saving, _save),
        const SizedBox(height: 32),
      ]),
    );
  }

  String _dueDateText(BuildContext context, int n) {
    final code = Provider.of<LocaleProvider>(context, listen: false).code;
    if (code == 'hi') {
      return 'महीने की $n तारीख';
    }
    return '${_ordinal(n)} of month';
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
    if (_whatsapp) {
      final wa = _waCtrl.text.trim();
      if (wa.isEmpty) {
        _snack('WhatsApp number is required.');
        return;
      }
      if (wa.length != 10 || int.tryParse(wa) == null) {
        _snack(context.tr('mustBe10Digits'));
        return;
      }
    }
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
        _snack(context.tr('settingsUpdated'), success: true);
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
        _toggleRow(context.tr('whatsAppNotificationsLabel'), _whatsapp,
            (v) => setState(() => _whatsapp = v)),
        if (_whatsapp) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _waCtrl,
            keyboardType: TextInputType.phone,
            maxLength: 10,
            readOnly: !widget.editing,
            decoration: InputDecoration(
              labelText: context.tr('whatsappNumberLabel'),
              prefixText: '+91 ',
              prefixIcon: const Icon(Icons.chat_outlined),
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
          ),
        ],
        const SizedBox(height: 16),
        _sectionLabel(context.tr('preferredLanguageLabel')),
        Wrap(spacing: 8, children: _langs.map((l) {
          final sel = l == _lang;
          return ChoiceChip(
            label: Text(context.tr('lang$l')),
            selected: sel,
            selectedColor: AppTheme.primaryLight,
            onSelected: widget.editing ? (_) => setState(() => _lang = l) : null,
          );
        }).toList()),
        const SizedBox(height: 16),
        _toggleRow(context.tr('busServiceAvailableLabel'), _bus, (v) => setState(() => _bus = v)),
        if (_bus) ...[
          const SizedBox(height: 12),
          _sectionLabel('${context.tr('numberOfRoutesLabel')}  ($_routes)'),
          Slider(value: _routes.clamp(1, 50).toDouble(), min: 1, max: 50,
              activeColor: AppTheme.primary,
              onChanged: widget.editing ? (v) => setState(() => _routes = v.round()) : null),
        ],
        const SizedBox(height: 20),
        if (widget.editing) _saveBtn(context, _saving, _save),
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

Widget _saveBtn(BuildContext context, bool saving, VoidCallback onSave) => SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : const Icon(Icons.save_outlined),
        label: Text(saving ? context.tr('savingLabel') : context.tr('saveSettingsLabel')),
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(context.tr('recentChanges'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
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
                    _formatChangeLog(context, log),
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

String _formatChangeLog(BuildContext context, Map<String, dynamic> log) {
  final field = log['field']?.toString() ?? '';
  final changedBy = log['changedBy']?.toString() ?? 'owner';
  
  final translatedField = _translateField(context, field);
  final author = changedBy == 'owner' ? context.trRole('owner') : changedBy;
  
  return context.tr('changeLogEntry')
      .replaceAll('{field}', translatedField)
      .replaceAll('{author}', author);
}

String _translateField(BuildContext context, String field) {
  switch (field) {
    case 'schoolName':
      return context.tr('schoolNameLabel');
    case 'logoUrl':
      return context.tr('logoLabel');
    case 'phone':
      return context.tr('phoneLabel');
    case 'email':
      return context.tr('emailLabel');
    case 'principalName':
      return context.tr('principalNameLabel');
    case 'establishedYear':
      return context.tr('establishedYearEditLabel');
    case 'tagline':
      return context.tr('schoolTaglineEditLabel');
    case 'website':
      return context.tr('websiteLabel');
    case 'schoolType':
      return context.tr('schoolTypeLabel');
    case 'board':
      return context.tr('boardLabel');
    case 'address':
      return context.tr('fullAddressLabel');
    case 'city':
      return context.tr('cityLabel');
    case 'state':
      return context.tr('stateLabel');
    case 'pinCode':
      return context.tr('pinCodeLabel');
    default:
      return field;
  }
}

extension _SnackExt on State {
  void _snack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: success ? AppTheme.success : AppTheme.danger,
    ));
  }
}
