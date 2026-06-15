import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../models/school_onboarding.dart';
import '../../services/location_service.dart';
import '../../theme.dart';

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
  bool _isLoadingLocation = false;

  Future<void> _pickLocation() async {
    setState(() => _isLoadingLocation = true);
    try {
      final loc = await LocationService.getCurrentLocation();
      setState(() {
        _addressCtrl.text = loc.address;
        _cityCtrl.text = loc.city;
        _pinCtrl.text = loc.pinCode;
        if (loc.state.isNotEmpty) {
          _state = loc.state;
        }
      });
      _notify();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location loaded successfully.'), backgroundColor: AppTheme.success),
        );
      }
    } catch (e) {
      if (mounted) {
        LocationService.handleLocationError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingLocation = false);
      }
    }
  }

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
          InkWell(
            onTap: _isLoadingLocation ? null : _pickLocation,
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.15)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _isLoadingLocation
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.primary),
                        )
                      : const Icon(Icons.my_location_outlined, color: AppTheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    _isLoadingLocation ? 'Fetching location...' : 'Use Current Location',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.primary,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _addressCtrl,
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
            decoration: _deco('${context.tr('fullAddressLabel')} *', Icons.location_on_outlined),
            onChanged: (_) => _notify(),
            validator: (v) => (v ?? '').trim().isEmpty ? context.tr('validationRequired') : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _cityCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: _deco('${context.tr('cityLabel')} *', Icons.location_city_outlined),
            onChanged: (_) => _notify(),
            validator: (v) => (v ?? '').trim().isEmpty ? context.tr('validationRequired') : null,
          ),
          const SizedBox(height: 14),
          DropdownButtonFormField<String>(
            value: _state.isEmpty ? null : _state,
            decoration: _deco('${context.tr('stateLabel')} *', Icons.map_outlined),
            isExpanded: true,
            items: _states
                .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                .toList(),
            onChanged: (v) {
              setState(() => _state = v ?? '');
              _notify();
            },
            validator: (v) => (v == null || v.isEmpty) ? context.tr('validationRequired') : null,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _pinCtrl,
            keyboardType: TextInputType.number,
            maxLength: 6,
            decoration: _deco('${context.tr('pinCodeLabel')} *', Icons.pin_drop_outlined)
                .copyWith(counterText: ''),
            onChanged: (_) => _notify(),
            validator: (v) {
              final s = (v ?? '').trim();
              if (s.isEmpty) return context.tr('validationRequired');
              if (!RegExp(r'^\d{6}$').hasMatch(s)) return context.tr('validPin6');
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _websiteCtrl,
            keyboardType: TextInputType.url,
            decoration: _deco(context.tr('schoolWebsiteLabel'), Icons.language_outlined),
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
