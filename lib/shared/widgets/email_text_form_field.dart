import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:account_picker/account_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../theme.dart';
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
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    super.dispose();
  }

  /// Reset validation state when the text is cleared externally
  /// (e.g. after a successful account creation).
  void _onTextChanged() {
    if (widget.controller.text.isEmpty && _touched) {
      setState(() {
        _touched = false;
      });
    }
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
      } else {
        _saveEmail(widget.controller.text);
      }
      if (!_touched) {
        setState(() {
          _touched = true;
        });
      }
    }
  }

  Future<List<String>> _getSavedEmails() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final recent = prefs.getStringList('recent_emails') ?? [];
      final lastEmail = prefs.getString('auth_email');
      final cachedAdmins = prefs.getStringList('cached_root_admins') ?? [];
      
      final allEmails = <String>{};
      
      // 1. Last logged-in email
      if (lastEmail != null && lastEmail.isNotEmpty) {
        allEmails.add(lastEmail.trim().toLowerCase());
      }
      // 2. Recent emails
      for (var e in recent) {
        final clean = e.trim().toLowerCase();
        if (clean.isNotEmpty) {
          allEmails.add(clean);
        }
      }
      // 3. Cached admins
      for (var e in cachedAdmins) {
        final clean = e.trim().toLowerCase();
        if (clean.isNotEmpty) {
          allEmails.add(clean);
        }
      }
      return allEmails.toList();
    } catch (e) {
      debugPrint('Error loading saved emails: $e');
      return [];
    }
  }

  Future<void> _saveEmail(String email) async {
    final clean = email.trim().toLowerCase();
    if (clean.isEmpty || !clean.contains('@')) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final recent = prefs.getStringList('recent_emails') ?? [];
      
      // Remove if already exists so we can move it to the top
      recent.remove(clean);
      recent.insert(0, clean);
      
      // Limit to top 8 recent emails
      if (recent.length > 8) {
        recent.removeRange(8, recent.length);
      }
      await prefs.setStringList('recent_emails', recent);
    } catch (e) {
      debugPrint('Error saving email: $e');
    }
  }

  Future<void> _showDeviceEmailPicker() async {
    if (!Platform.isAndroid) return;
    if (Platform.environment.containsKey('FLUTTER_TEST')) return;
    try {
      final emails = await _getSavedEmails();
      bool chosen = false;
      if (emails.isEmpty) {
        chosen = await _triggerNativePicker();
      } else {
        if (!mounted) return;
        chosen = await _showThemedEmailSheet(emails);
      }
      if (!chosen && mounted) {
        _focusNode.unfocus();
      }
    } catch (e) {
      debugPrint('Failed to pick email: $e');
      if (mounted) {
        _focusNode.unfocus();
      }
    }
  }

  Future<bool> _triggerNativePicker() async {
    final emailResult = await AccountPicker.emailHint();
    if (emailResult != null) {
      final selectedEmail = emailResult.email;
      _selectEmail(selectedEmail);
      await _saveEmail(selectedEmail);
      return true;
    }
    return false;
  }

  void _selectEmail(String email) {
    widget.controller.text = email;
    if (widget.onChanged != null) {
      widget.onChanged!(email);
    }
    // Move cursor to the end
    widget.controller.selection = TextSelection.fromPosition(
      TextPosition(offset: email.length),
    );
  }

  Future<bool> _showThemedEmailSheet(List<String> emails) async {
    final chosen = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          color: Colors.white,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Text(
                    'Choose an account',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ),
                const Divider(),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: emails.length,
                    itemBuilder: (context, index) {
                      final email = emails[index];
                      return ListTile(
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.alternate_email,
                            color: AppTheme.primary,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          email,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        onTap: () {
                          _selectEmail(email);
                          _saveEmail(email);
                          Navigator.pop(context, true);
                        },
                      );
                    },
                  ),
                ),
                const Divider(),
                ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.account_box_outlined,
                      color: AppTheme.accent,
                      size: 20,
                    ),
                  ),
                  title: const Text(
                    'Choose from device accounts',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.accent,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context, false);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );

    if (chosen == true) {
      return true;
    } else if (chosen == false) {
      await Future.delayed(const Duration(milliseconds: 150));
      return await _triggerNativePicker();
    }
    return false;
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
