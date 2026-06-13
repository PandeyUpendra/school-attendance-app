import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:account_picker/account_picker.dart';
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
  bool _hasAutoPrompted = false;

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
    if (_focusNode.hasFocus) {
      if (widget.controller.text.isEmpty &&
          Platform.isAndroid &&
          widget.enabled &&
          !widget.readOnly &&
          !_hasAutoPrompted) {
        _hasAutoPrompted = true;
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted && _focusNode.hasFocus && widget.controller.text.isEmpty) {
            _showDeviceEmailPicker();
          }
        });
      }
    } else {
      if (widget.controller.text.isEmpty) {
        _hasAutoPrompted = false;
      }
      if (!_touched) {
        setState(() {
          _touched = true;
        });
      }
    }
  }

  Future<void> _showDeviceEmailPicker() async {
    if (!Platform.isAndroid) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final emailResult = await AccountPicker.emailHint();
      if (emailResult != null && emailResult.email != null) {
        widget.controller.text = emailResult.email!;
        if (widget.onChanged != null) {
          widget.onChanged!(emailResult.email!);
        }
        // Move cursor to the end
        widget.controller.selection = TextSelection.fromPosition(
          TextPosition(offset: emailResult.email!.length),
        );
      }
    } catch (e) {
      debugPrint('Failed to pick email: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool showPickerIcon = Platform.isAndroid && widget.enabled && !widget.readOnly;
    final updatedDecoration = widget.decoration.copyWith(
      suffixIcon: showPickerIcon
          ? IconButton(
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: 'Select email from device',
              onPressed: _showDeviceEmailPicker,
            )
          : widget.decoration.suffixIcon,
    );

    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: TextInputType.emailAddress,
      autocorrect: false,
      enableSuggestions: true,
      autofillHints: const [AutofillHints.email],
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
      decoration: updatedDecoration,
    );
  }
}
