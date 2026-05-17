import 'package:flutter/material.dart';
import '../../models/school_onboarding.dart';
import '../../theme.dart';

class Step3Academic extends StatefulWidget {
  final SchoolOnboarding initial;
  final void Function(SchoolOnboarding) onChanged;

  const Step3Academic({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<Step3Academic> createState() => Step3AcademicState();
}

class Step3AcademicState extends State<Step3Academic> {
  late int _from;
  late int _to;
  late List<String> _sections;
  late String _yearStart;
  late String _workingDays;
  late int _periods;
  late int _duration;
  late int _lunch;

  bool _validated = false;

  static const _sectionOptions = ['A', 'B', 'C', 'D', 'E'];
  static const _durations = [35, 40, 45, 50];

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _from = d.classesFrom.clamp(1, 12);
    _to = d.classesTo.clamp(1, 12);
    _sections = List.from(d.sectionsPerClass.isNotEmpty ? d.sectionsPerClass : ['A']);
    _yearStart = d.academicYearStart;
    _workingDays = d.workingDays;
    _periods = d.periodsPerDay.clamp(4, 10);
    _duration = _durations.contains(d.periodDuration) ? d.periodDuration : 45;
    _lunch = d.lunchAfterPeriod;
  }

  void _notify() {
    final classList = SchoolOnboarding.generateClassList(_from, _to, _sections);
    widget.onChanged(widget.initial.copyWith(
      classesFrom: _from,
      classesTo: _to,
      sectionsPerClass: List.from(_sections),
      classList: classList,
      academicYearStart: _yearStart,
      workingDays: _workingDays,
      periodsPerDay: _periods,
      periodDuration: _duration,
      lunchAfterPeriod: _lunch.clamp(1, _periods),
    ));
  }

  bool validate() {
    setState(() => _validated = true);
    if (_to < _from) return false;
    if (_sections.isEmpty) return false;
    return true;
  }

  String? get _rangeError {
    if (!_validated) return null;
    if (_to < _from) return 'Class To must be ≥ Class From';
    return null;
  }

  String? get _sectionError {
    if (!_validated) return null;
    if (_sections.isEmpty) return 'Select at least one section';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final maxLunch = _periods.clamp(1, 10);
    if (_lunch > maxLunch) {
      _lunch = maxLunch;
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _label('Class Range *'),
        Row(children: [
          Expanded(child: _classDropdown('From', _from, (v) {
            setState(() => _from = v);
            if (_to < v) setState(() => _to = v);
            _notify();
          })),
          const SizedBox(width: 12),
          Expanded(child: _classDropdown('To', _to, (v) {
            setState(() => _to = v);
            _notify();
          })),
        ]),
        if (_rangeError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_rangeError!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
          ),
        const SizedBox(height: 18),
        _label('Sections per Class *'),
        Wrap(
          spacing: 8,
          children: _sectionOptions.map((s) {
            final sel = _sections.contains(s);
            return FilterChip(
              label: Text('Section $s'),
              selected: sel,
              selectedColor: AppTheme.primaryLight,
              checkmarkColor: AppTheme.primary,
              onSelected: (v) {
                setState(() {
                  if (v) {
                    _sections.add(s);
                    _sections.sort();
                  } else {
                    _sections.remove(s);
                  }
                });
                _notify();
              },
            );
          }).toList(),
        ),
        if (_sectionError != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_sectionError!, style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
          ),
        if (_sections.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Classes: ${SchoolOnboarding.generateClassList(_from, _to, _sections).join(", ")}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
        const SizedBox(height: 18),
        _label('Academic Year Starts *'),
        _segmented(
          options: const ['April', 'June'],
          selected: _yearStart,
          onSelect: (v) {
            setState(() => _yearStart = v);
            _notify();
          },
        ),
        const SizedBox(height: 18),
        _label('Working Days *'),
        _segmented(
          options: const ['Mon-Sat', 'Mon-Fri'],
          selected: _workingDays,
          onSelect: (v) {
            setState(() => _workingDays = v);
            _notify();
          },
        ),
        const SizedBox(height: 18),
        _label('Periods Per Day *  ($_periods)'),
        Row(children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            color: AppTheme.primary,
            onPressed: _periods > 4 ? () { setState(() => _periods--); _notify(); } : null,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(activeTrackColor: AppTheme.primary),
              child: Slider(
                value: _periods.toDouble(),
                min: 4, max: 10, divisions: 6,
                label: '$_periods',
                activeColor: AppTheme.primary,
                onChanged: (v) { setState(() => _periods = v.round()); _notify(); },
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: AppTheme.primary,
            onPressed: _periods < 10 ? () { setState(() => _periods++); _notify(); } : null,
          ),
        ]),
        const SizedBox(height: 18),
        _dropdownInt(
          label: 'Period Duration *',
          value: _duration,
          items: _durations,
          suffix: ' min',
          onChanged: (v) { setState(() => _duration = v); _notify(); },
        ),
        const SizedBox(height: 14),
        _dropdownInt(
          label: 'Lunch Break After Period *',
          value: _lunch.clamp(1, maxLunch),
          items: List.generate(maxLunch, (i) => i + 1),
          prefix: 'After period ',
          onChanged: (v) { setState(() => _lunch = v); _notify(); },
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      );

  Widget _classDropdown(String label, int value, void Function(int) onChanged) {
    return DropdownButtonFormField<int>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      items: List.generate(12, (i) => i + 1)
          .map((n) => DropdownMenuItem(value: n, child: Text('Class $n')))
          .toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }

  Widget _segmented({
    required List<String> options,
    required String selected,
    required void Function(String) onSelect,
  }) {
    return Row(
      children: options.map((o) {
        final sel = o == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelect(o),
            child: Container(
              margin: EdgeInsets.only(right: o == options.last ? 0 : 8),
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: sel ? AppTheme.primary : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: sel ? AppTheme.primary : Colors.grey.shade300),
              ),
              child: Text(
                o,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: sel ? Colors.white : Colors.black87,
                  fontWeight: sel ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _dropdownInt({
    required String label,
    required int value,
    required List<int> items,
    required void Function(int) onChanged,
    String prefix = '',
    String suffix = '',
  }) {
    return DropdownButtonFormField<int>(
      value: items.contains(value) ? value : items.first,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      ),
      items: items
          .map((n) => DropdownMenuItem(value: n, child: Text('$prefix$n$suffix')))
          .toList(),
      onChanged: (v) { if (v != null) onChanged(v); },
    );
  }
}
