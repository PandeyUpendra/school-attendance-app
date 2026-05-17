import 'package:flutter/material.dart';
import '../../models/school_onboarding.dart';

class Step2Address extends StatefulWidget {
  final SchoolOnboarding initial;
  final void Function(SchoolOnboarding) onChanged;

  const Step2Address({
    super.key,
    required this.initial,
    required this.onChanged,
  });

  @override
  State<Step2Address> createState() => Step2AddressState();
}

class Step2AddressState extends State<Step2Address> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _addressCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _websiteCtrl;

  String _state = '';

  static const _states = [
    'Andhra Pradesh', 'Arunachal Pradesh', 'Assam', 'Bihar', 'Chhattisgarh',
    'Goa', 'Gujarat', 'Haryana', 'Himachal Pradesh', 'Jharkhand', 'Karnataka',
    'Kerala', 'Madhya Pradesh', 'Maharashtra', 'Manipur', 'Meghalaya',
    'Mizoram', 'Nagaland', 'Odisha', 'Punjab', 'Rajasthan', 'Sikkim',
    'Tamil Nadu', 'Telangana', 'Tripura', 'Uttar Pradesh', 'Uttarakhand',
    'West Bengal',
    'Andaman and Nicobar Islands', 'Chandigarh',
    'Dadra and Nagar Haveli and Daman and Diu', 'Delhi',
    'Jammu and Kashmir', 'Ladakh', 'Lakshadweep', 'Puducherry',
  ];

  @override
  void initState() {
    super.initState();
    final d = widget.initial;
    _addressCtrl = TextEditingController(text: d.address);
    _cityCtrl = TextEditingController(text: d.city);
    _pinCtrl = TextEditingController(text: d.pinCode);
    _websiteCtrl = TextEditingController(text: d.website);
    _state = _states.contains(d.state) ? d.state : '';
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    _cityCtrl.dispose();
    _pinCtrl.dispose();
    _websiteCtrl.dispose();
    super.dispose();
  }

  void _notify() {
    widget.onChanged(widget.initial.copyWith(
      address: _addressCtrl.text.trim(),
      city: _cityCtrl.text.trim(),
      state: _state,
      pinCode: _pinCtrl.text.trim(),
      website: _websiteCtrl.text.trim(),
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
          TextFormField(
            controller: _addressCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: _deco('Full Address *', Icons.location_on_outlined),
            onChanged: (_) => _notify(),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _cityCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _deco('City *', Icons.location_city_outlined),
            onChanged: (_) => _notify(),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _state.isEmpty ? null : _state,
            decoration: _deco('State *', Icons.map_outlined),
            isExpanded: true,
            items: _states
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) {
              setState(() => _state = v ?? '');
              _notify();
            },
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: _deco('PIN Code *', Icons.pin_drop_outlined)
                .copyWith(counterText: ''),
            onChanged: (_) => _notify(),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return 'Required';
              if (!RegExp(r'^\d{6}$').hasMatch(s)) return 'Enter a valid 6-digit PIN';
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _websiteCtrl,
            keyboardType: TextInputType.url,
            decoration: _deco('School Website (optional)', Icons.language_outlined),
            onChanged: (_) => _notify(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  InputDecoration _deco(String label, IconData icon) => InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        isDense: true,
      );
}
