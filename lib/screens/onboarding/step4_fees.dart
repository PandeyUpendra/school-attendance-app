import 'package:flutter/material.dart';
import '../../models/school_onboarding.dart';
import '../../theme.dart';

class Step4Fees extends StatefulWidget {
  final SchoolOnboarding initial;
  final void Function(SchoolOnboarding) onChanged;

  const Step4Fees({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<Step4Fees> createState() => Step4FeesState();
}

class Step4FeesState extends State<Step4Fees> {
  late String _frequency;
  late int _dueDate;
  late bool _lateEnabled;
  late int _reminderDays;

  late final TextEditingController _lateCtrl;
  final _formKey = GlobalKey<FormState>();

  static const _frequencies = ['Monthly', 'Quarterly', 'Half-Yearly', 'Annually'];

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _frequency = _frequencies.contains(d.feeFrequency) ? d.feeFrequency : 'Monthly';
    _dueDate = d.feeDueDate.clamp(1, 28);
    _lateEnabled = d.lateFeeEnabled;
    _reminderDays = d.reminderDaysBefore.clamp(1, 14);
    _lateCtrl = TextEditingController(
        text: d.lateFeePerDay > 0 ? '${d.lateFeePerDay}' : '');
  }

  @override
  void dispose() {
    _lateCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(widget.initial.copyWith(
      feeFrequency: _frequency,
      feeDueDate: _dueDate,
      lateFeeEnabled: _lateEnabled,
      lateFeePerDay: int.tryParse(_lateCtrl.text) ?? 0,
      reminderDaysBefore: _reminderDays,
    ));
  }

  bool validate() => _formKey.currentState?.validate() ?? false;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _label('Fee Frequency *'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _frequencies.map((f) {
              final sel = f == _frequency;
              return ChoiceChip(
                label: Text(f),
                selected: sel,
                selectedColor: AppTheme.primaryLight,
                onSelected: (_) {
                  setState(() => _frequency = f);
                  _notify();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          _label('Fee Due Date *'),
          DropdownButtonFormField<int>(
            value: _dueDate,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.calendar_today_outlined),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
            items: List.generate(28, (i) => i + 1)
                .map((n) => DropdownMenuItem(value: n, child: Text('${_ordinal(n)} of every month')))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _dueDate = v);
                _notify();
              }
            },
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Late Fee Applicable',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              Switch(
                value: _lateEnabled,
                activeColor: AppTheme.primary,
                onChanged: (v) {
                  setState(() => _lateEnabled = v);
                  _notify();
                },
              ),
            ],
          ),
          if (_lateEnabled) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _lateCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Late Fee Per Day (₹) *',
                prefixIcon: const Icon(Icons.currency_rupee_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              onChanged: (_) => _notify(),
              validator: _lateEnabled
                  ? (v) {
                      final n = int.tryParse(v ?? '');
                      if (n == null || n <= 0) return 'Enter a valid amount';
                      return null;
                    }
                  : null,
            ),
          ],
          const SizedBox(height: 18),
          _label('Reminder Days Before Due  ($_reminderDays days)'),
          Row(children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              color: AppTheme.primary,
              onPressed: _reminderDays > 1
                  ? () { setState(() => _reminderDays--); _notify(); }
                  : null,
            ),
            Expanded(
              child: Slider(
                value: _reminderDays.toDouble(),
                min: 1, max: 14, divisions: 13,
                label: '$_reminderDays',
                activeColor: AppTheme.primary,
                onChanged: (v) { setState(() => _reminderDays = v.round()); _notify(); },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline),
              color: AppTheme.primary,
              onPressed: _reminderDays < 14
                  ? () { setState(() => _reminderDays++); _notify(); }
                  : null,
            ),
          ]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      );

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    switch (n % 10) {
      case 1: return '${n}st';
      case 2: return '${n}nd';
      case 3: return '${n}rd';
      default: return '${n}th';
    }
  }
}
