import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/validators.dart';

/// A wrapper around [TextFormField] specifically for email inputs.
///
/// It disables autocorrect and suggestions to prevent keyboard glitches,
/// and it validates the input as soon as the user leaves the field (on blur).
class EmailTextFormField extends StatefulWidget {
  final TextEditingController controller;
  final bool enabled;
  final bool readOnly;
  final int? maxLength;
  final TextInputAction textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final InputDecoration decoration;
  final String? Function(String?)? validator;
  final bool isOptional;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;

  const EmailTextFormField({
    super.key,
    required this.controller,
    this.enabled = true,
    this.readOnly = false,
    this.maxLength,
    this.textInputAction = TextInputAction.next,
    this.onFieldSubmitted,
    this.onChanged,
    required this.decoration,
    this.validator,
    this.isOptional = false,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  State<EmailTextFormField> createState() => _EmailTextFormFieldState();
}

class _EmailTextFormFieldState extends State<EmailTextFormField> {
  late final FocusNode _focusNode;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      if (!_touched) {
        setState(() {
          _touched = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      enableSuggestions: false,
      enabled: widget.enabled,
      readOnly: widget.readOnly,
      maxLength: widget.maxLength,
      maxLengthEnforcement: widget.maxLength != null
          ? MaxLengthEnforcement.enforced
          : MaxLengthEnforcement.none,
      textInputAction: widget.textInputAction,
      onFieldSubmitted: widget.onFieldSubmitted,
      onChanged: widget.onChanged,
      inputFormatters: widget.inputFormatters,
      textCapitalization: widget.textCapitalization,
      autovalidateMode: _touched ? AutovalidateMode.always : AutovalidateMode.disabled,
      validator: widget.validator ??
          (widget.isOptional ? Validators.optionalEmail : Validators.email),
      decoration: widget.decoration,
    );
  }
}
