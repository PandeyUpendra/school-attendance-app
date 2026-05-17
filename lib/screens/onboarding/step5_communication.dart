import 'package:flutter/material.dart';
import '../../models/school_onboarding.dart';
import '../../theme.dart';

class Step5Communication extends StatefulWidget {
  final SchoolOnboarding initial;
  final void Function(SchoolOnboarding) onChanged;

  const Step5Communication({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<Step5Communication> createState() => Step5CommunicationState();
}

class Step5CommunicationState extends State<Step5Communication> {
  late bool _whatsapp;
  late bool _bus;
  late String _language;
  late int _routes;
  late final TextEditingController _waCtrl;
  late final TextEditingController _taglineCtrl;

  final _formKey = GlobalKey<FormState>();

  static const _langs = ['English', 'Hindi', 'Both'];

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _whatsapp = d.whatsappEnabled;
    _bus = d.busServiceAvailable;
    _language = _langs.contains(d.preferredLanguage) ? d.preferredLanguage : 'English';
    _routes = d.busRouteCount.clamp(0, 50);
    _waCtrl = TextEditingController(text: d.schoolWhatsapp);
    _taglineCtrl = TextEditingController(text: d.schoolTagline);
  }

  @override
  void dispose() {
    _waCtrl.dispose();
    _taglineCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(widget.initial.copyWith(
      whatsappEnabled: _whatsapp,
      schoolWhatsapp: _waCtrl.text.trim(),
      preferredLanguage: _language,
      busServiceAvailable: _bus,
      busRouteCount: _routes,
      schoolTagline: _taglineCtrl.text.trim(),
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
          _toggleRow('WhatsApp Notifications', _whatsapp, (v) {
            setState(() => _whatsapp = v);
            _notify();
          }),
          if (_whatsapp) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _waCtrl,
              keyboardType: TextInputType.phone,
              maxLength: 10,
              decoration: InputDecoration(
                labelText: 'School WhatsApp Number *',
                prefixText: '+91 ',
                prefixIcon: const Icon(Icons.chat_outlined),
                counterText: '',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                isDense: true,
              ),
              onChanged: (_) => _notify(),
              validator: _whatsapp
                  ? (v) {
                      final s = (v ?? '').trim();
                      if (s.isEmpty) return 'Required';
                      if (!RegExp(r'^\d{10}$').hasMatch(s)) return 'Enter valid 10-digit number';
                      return null;
                    }
                  : null,
            ),
          ],
          const SizedBox(height: 18),
          _label('Preferred Language *'),
          Wrap(
            spacing: 8,
            children: _langs.map((l) {
              final sel = l == _language;
              return ChoiceChip(
                label: Text(l),
                selected: sel,
                selectedColor: AppTheme.primaryLight,
                onSelected: (_) {
                  setState(() => _language = l);
                  _notify();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          _toggleRow('Bus Service Available', _bus, (v) {
            setState(() => _bus = v);
            _notify();
          }),
          if (_bus) ...[
            const SizedBox(height: 12),
            _label('Number of Routes  ($_routes)'),
            Row(children: [
              IconButton(
                icon: const Icon(Icons.remove_circle_outline),
                color: AppTheme.primary,
                onPressed: _routes > 1 ? () { setState(() => _routes--); _notify(); } : null,
              ),
              Expanded(
                child: Slider(
                  value: _routes.clamp(1, 50).toDouble(),
                  min: 1, max: 50, divisions: 49,
                  label: '$_routes',
                  activeColor: AppTheme.primary,
                  onChanged: (v) { setState(() => _routes = v.round()); _notify(); },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_outline),
                color: AppTheme.primary,
                onPressed: _routes < 50 ? () { setState(() => _routes++); _notify(); } : null,
              ),
            ]),
          ],
          const SizedBox(height: 18),
          TextFormField(
            controller: _taglineCtrl,
            textCapitalization: TextCapitalization.sentences,
            maxLength: 100,
            decoration: InputDecoration(
              labelText: 'School Tagline (optional)',
              prefixIcon: const Icon(Icons.format_quote_outlined),
              counterText: '',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              isDense: true,
            ),
            onChanged: (_) => _notify(),
          ),
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

  Widget _toggleRow(String label, bool value, void Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        Switch(
          value: value,
          activeColor: AppTheme.primary,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
