import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
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
  // Index into _classOptions (0 = Playgroup, 1 = Pre-Nursery, 2 = Nursery, 3 = LKG, 4 = UKG, 5 = Class 1 … 16 = Class 12)
  late int _fromIdx;
  late int _toIdx;
  late List<String> _sections;
  late List<String> _classList;
  late String _yearStart;
  late String _workingDays;
  late int _periods;
  late int _duration;
  late int _lunch;

  bool _validated = false;

  static const _sectionOptions = ['A', 'B', 'C', 'D', 'E'];
  static const _seniorSectionOptions = [
    'Sci', 'Sci-A', 'Sci-B',
    'Com', 'Com-A', 'Com-B',
    'Arts', 'Arts-A', 'Arts-B',
  ];
  static const _durations = [35, 40, 45, 50];

  static const _classOptions = [
    'Playgroup', 'Pre-Nursery', 'Nursery', 'LKG', 'UKG',
    'Class 1', 'Class 2', 'Class 3', 'Class 4', 'Class 5', 'Class 6',
    'Class 7', 'Class 8', 'Class 9', 'Class 10', 'Class 11', 'Class 12',
  ];
  static const _prePrimary = ['Playgroup', 'Pre-Nursery', 'Nursery', 'LKG', 'UKG'];

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    // Prefer label-based fields first, falling back to legacy integer index calculation
    _fromIdx = _classOptions.indexOf(d.classesFromLabel ?? '');
    if (_fromIdx < 0) {
      if (d.classesFrom <= 0) {
        _fromIdx = 2; // default to Nursery (index 2 in new list)
      } else {
        _fromIdx = (d.classesFrom + 4).clamp(0, _classOptions.length - 1);
      }
    }
    _toIdx = _classOptions.indexOf(d.classesToLabel ?? '');
    if (_toIdx < 0) {
      if (d.classesTo <= 0) {
        _toIdx = 2; // Nursery
      } else {
        _toIdx = (d.classesTo + 4).clamp(0, _classOptions.length - 1);
      }
    }
    _sections = List.from(d.sectionsPerClass.isNotEmpty ? d.sectionsPerClass : ['A']);
    _classList = List.from(d.classList);
    if (_classList.isEmpty) {
      _classList = _generateClassList();
    } else {
      _sortClassList();
    }
    _yearStart = d.academicYearStart;
    _workingDays = d.workingDays;
    _periods = d.periodsPerDay.clamp(4, 10);
    _duration = _durations.contains(d.periodDuration) ? d.periodDuration : 45;
    _lunch = d.lunchAfterPeriod;
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
        final label = _classOptions[i];
        final prefix = _getClassPrefix(label);
        final hasAny = _classList.any((item) => item.startsWith('$prefix-'));
        if (!hasAny) {
          if (label == 'Class 11' || label == 'Class 12') {
            final seniorSecs = <String>[];
            for (final s in _sections) {
              seniorSecs.addAll(['Sci-$s', 'Com-$s', 'Arts-$s']);
            }
            for (final s in seniorSecs) {
              _classList.add('$prefix-$s');
            }
          } else {
            for (final s in _sections) {
              _classList.add('$prefix-$s');
            }
          }
        }
      }

      _sortClassList();
    });
  }

  void _addGlobalSection(String s) {
    setState(() {
      for (int i = _fromIdx; i <= _toIdx; i++) {
        final label = _classOptions[i];
        final prefix = _getClassPrefix(label);
        if (label == 'Class 11' || label == 'Class 12') {
          final seniorSecs = ['Sci-$s', 'Com-$s', 'Arts-$s'];
          for (final ss in seniorSecs) {
            final item = '$prefix-$ss';
            if (!_classList.contains(item)) {
              _classList.add(item);
            }
          }
        } else {
          final item = '$prefix-$s';
          if (!_classList.contains(item)) {
            _classList.add(item);
          }
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

  void _notify() {
    final classList = List<String>.from(_classList);
    widget.onChanged(widget.initial.copyWith(
      classesFrom: _fromIdx >= 5 ? (_fromIdx - 4) : 1, // backward-compat integer
      classesTo:   _toIdx   >= 5 ? (_toIdx   - 4) : 1,
      classesFromLabel: _classOptions[_fromIdx],
      classesToLabel:   _classOptions[_toIdx],
      sectionsPerClass: List.from(_sections),
      classList: classList,
      academicYearStart: _yearStart,
      workingDays: _workingDays,
      periodsPerDay: _periods,
      periodDuration: _duration,
      lunchAfterPeriod: _lunch.clamp(1, _periods),
    ));
  }

  List<String> _generateClassList() {
    final list = <String>[];
    for (int i = _fromIdx; i <= _toIdx; i++) {
      final label = _classOptions[i];
      final prefix = _getClassPrefix(label);
      if (label == 'Class 11' || label == 'Class 12') {
        final seniorSecs = <String>[];
        for (final s in _sections) {
          seniorSecs.addAll(['Sci-$s', 'Com-$s', 'Arts-$s']);
        }
        for (final s in seniorSecs) {
          list.add('$prefix-$s');
        }
      } else {
        for (final s in _sections) {
          list.add('$prefix-$s');
        }
      }
    }
    return list;
  }

  bool validate() {
    setState(() => _validated = true);
    if (_toIdx < _fromIdx) return false;
    if (_sections.isEmpty) return false;
    return true;
  }

  String? get _rangeErrorKey {
    if (!_validated) return null;
    if (_toIdx < _fromIdx) return 'classToError';
    return null;
  }

  String? get _sectionErrorKey {
    if (!_validated) return null;
    if (_sections.isEmpty) return 'selectOneSection';
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
        _label('${context.tr('classRange')} *'),
        Row(children: [
          Expanded(child: _classDropdown(context.tr('rangeFrom'), _fromIdx, (v) {
            setState(() {
              _fromIdx = v;
              if (_toIdx < v) _toIdx = v;
            });
            _syncClassListToRange();
            _notify();
          })),
          const SizedBox(width: 12),
          Expanded(child: _classDropdown(context.tr('rangeTo'), _toIdx, (v) {
            setState(() => _toIdx = v);
            _syncClassListToRange();
            _notify();
          })),
        ]),
        if (_rangeErrorKey != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(context.tr(_rangeErrorKey!), style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
          ),
        const SizedBox(height: 18),
        _label('${context.tr('sectionsPerClass')} *'),
        Wrap(
          spacing: 8,
          children: _sectionOptions.map((s) {
            final sel = _sections.contains(s);
            return FilterChip(
              label: Text('${context.tr('sectionWord')} $s'),
              selected: sel,
              selectedColor: AppTheme.primaryLight,
              checkmarkColor: AppTheme.primary,
              onSelected: (v) {
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
                _notify();
              },
            );
          }).toList(),
        ),
        if (_sectionErrorKey != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(context.tr(_sectionErrorKey!), style: const TextStyle(color: AppTheme.danger, fontSize: 12)),
          ),
        if (_classList.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            '${context.tr('classesColon')}: ${_classList.join(", ")}',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
          ),
        ],
        if (_toIdx >= _fromIdx) ...[
          const SizedBox(height: 20),
          _label(context.tr('classWiseSectionsLabel')),
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

                final isSenior = label == 'Class 11' || label == 'Class 12';
                final currentOptions = isSenior ? _seniorSectionOptions : _sectionOptions;

                Widget buildSectionWrap() {
                  return Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: currentOptions.map((s) {
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
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text(context.tr('selectAtLeastOneSecMsg')),
                                  backgroundColor: AppTheme.danger,
                                ));
                                return;
                              }
                              _classList.remove(item);
                            } else {
                              _classList.add(item);
                              _sortClassList();
                            }
                          });
                          _notify();
                        },
                        borderRadius: BorderRadius.circular(16),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: isSenior
                              ? const EdgeInsets.symmetric(horizontal: 10, vertical: 6)
                              : EdgeInsets.zero,
                          width: isSenior ? null : 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isSelected ? AppTheme.primaryLight : Colors.grey.shade200,
                            borderRadius: BorderRadius.circular(16),
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
                  );
                }

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: isSenior
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            buildSectionWrap(),
                          ],
                        )
                      : Row(
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
                            buildSectionWrap(),
                          ],
                        ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 18),
        _label('${context.tr('academicYearStarts')} *'),
        _segmented(
          options: const ['April', 'June'],
          selected: _yearStart,
          onSelect: (v) {
            setState(() => _yearStart = v);
            _notify();
          },
        ),
        const SizedBox(height: 18),
        _label('${context.tr('workingDaysLabel')} *'),
        _segmented(
          options: const ['Mon-Sat', 'Mon-Fri'],
          selected: _workingDays,
          onSelect: (v) {
            setState(() => _workingDays = v);
            _notify();
          },
        ),
        const SizedBox(height: 18),
        _label('${context.tr('periodsPerDay')} *  ($_periods)'),
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
          label: '${context.tr('periodDurationLabel')} *',
          value: _duration,
          items: _durations,
          suffix: ' min',
          onChanged: (v) { setState(() => _duration = v); _notify(); },
        ),
        const SizedBox(height: 14),
        _dropdownInt(
          label: '${context.tr('lunchBreakAfterPeriod')} *',
          value: _lunch.clamp(1, maxLunch),
          items: List.generate(maxLunch, (i) => i + 1),
          prefix: '${context.tr('afterPeriodPrefix')} ',
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

  Widget _classDropdown(String label, int idxValue, void Function(int) onChanged) {
    return DropdownButtonFormField<int>(
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
