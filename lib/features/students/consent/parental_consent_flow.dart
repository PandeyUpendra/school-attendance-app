import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_strings.dart';
import '../../../models/parental_consent.dart';
import '../../../services/consent_service.dart';
import '../../../theme.dart';
import '../../../shared/utils/privacy_notice.dart';
import '../../../shared/utils/validators.dart';
import '../../../shared/widgets/email_text_form_field.dart';

/// Multi-step parental consent flow.
///
/// Steps:
///   0 → Guardian details form
///   1 → Privacy notice review (bilingual)
///   2 → Scope selection
///   3 → OTP send + entry  (or in-person signing)
///   4 → Success
///
/// [studentDocId] is the Firestore doc ID e.g. "Class_9-A__1".
/// [studentName]  is shown in headings for context.
/// [guardianPhone] / [guardianName] may be pre-filled from student record.
///
/// Returns [ParentalConsent] on Navigator.pop when completed, or null if skipped.
class ParentalConsentFlow extends StatefulWidget {
  final String  studentDocId;
  final String  studentName;
  final String? prefillGuardianName;
  final String? prefillGuardianPhone;
  final String? prefillGuardianEmail;
  /// When true, the flow is launched in "re-consent" mode (version bump).
  final bool    isReConsent;

  const ParentalConsentFlow({
    super.key,
    required this.studentDocId,
    required this.studentName,
    this.prefillGuardianName,
    this.prefillGuardianPhone,
    this.prefillGuardianEmail,
    this.isReConsent = false,
  });

  @override
  State<ParentalConsentFlow> createState() => _ParentalConsentFlowState();
}

class _ParentalConsentFlowState extends State<ParentalConsentFlow> {
  final _svc      = ConsentService();
  final _pageCtrl = PageController();

  int _step = 0;

  // Step 0 — guardian details
  final _formKey      = GlobalKey<FormState>();
  final _nameCtrl     = TextEditingController();
  final _phoneCtrl    = TextEditingController();
  final _emailCtrl    = TextEditingController();

  // Step 1 — language toggle
  String _lang = 'en';

  // Step 2 — scopes
  late List<ConsentScope> _scopes;

  // Step 3 — OTP flow
  _ConsentMethod _method    = _ConsentMethod.otp;
  bool   _otpSending        = false;
  bool   _otpSent           = false;
  String _verificationId    = '';
  final _otpCtrl            = TextEditingController();
  bool   _verifying         = false;
  String? _otpError;

  // Step 3 — in-person
  bool _inPersonConfirmed   = false;

  bool _submitting          = false;
  ParentalConsent? _result;

  @override
  void initState() {
    super.initState();
    _nameCtrl.text  = widget.prefillGuardianName  ?? '';
    _phoneCtrl.text = widget.prefillGuardianPhone ?? '';
    _emailCtrl.text = widget.prefillGuardianEmail ?? '';
    _scopes         = ParentalConsent.defaultScopes();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _otpCtrl.dispose();
    _pageCtrl.dispose();
    super.dispose();
  }

  // ── Navigation ─────────────────────────────────────────────────────────────

  void _goTo(int page) {
    setState(() => _step = page);
    _pageCtrl.animateToPage(page,
        duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
  }

  void _next() => _goTo(_step + 1);

  bool _validateStep0() {
    if (!_formKey.currentState!.validate()) return false;
    final phone = _phoneCtrl.text.trim();
    if (!phone.startsWith('+') || phone.length < 10) {
      _showError(context.tr('enterPhoneE164'));
      return false;
    }
    return true;
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  // ── OTP flow ───────────────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    setState(() { _otpSending = true; _otpError = null; });
    try {
      final vid = await _svc.sendOtp(phoneNumber: _phoneCtrl.text.trim());
      if (!mounted) return;
      if (vid.startsWith('__auto__:')) {
        // Auto-retrieval completed
        final code = vid.substring(9);
        _otpCtrl.text = code;
        _verificationId = vid;
        setState(() { _otpSent = true; _otpSending = false; });
      } else {
        setState(() {
          _verificationId = vid;
          _otpSent        = true;
          _otpSending     = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _otpSending = false; _otpError = e.toString(); });
    }
  }

  Future<void> _verifyOtp() async {
    final code = _otpCtrl.text.trim();
    if (code.length < 4) {
      setState(() => _otpError = context.tr('enterFullOtp'));
      return;
    }
    setState(() { _verifying = true; _otpError = null; });
    try {
      await _svc.verifyOtp(
        verificationId: _verificationId,
        smsCode:        code,
      );
      if (!mounted) return;
      await _submitConsent(
        method:            ConsentMethod.otpVerified,
        otpVerificationId: _verificationId,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _verifying = false; _otpError = e.toString(); });
    }
  }

  Future<void> _submitInPersonConsent() async {
    await _submitConsent(method: ConsentMethod.inPersonSigned);
  }

  Future<void> _submitConsent({
    required ConsentMethod method,
    String? otpVerificationId,
  }) async {
    setState(() { _submitting = true; _verifying = false; });
    try {
      final consent = await _svc.createConsent(
        studentDocId:      widget.studentDocId,
        guardianName:      _nameCtrl.text.trim(),
        guardianPhone:     _phoneCtrl.text.trim(),
        guardianEmail:     _emailCtrl.text.trim().isEmpty
                               ? null
                               : _emailCtrl.text.trim(),
        method:            method,
        otpVerificationId: otpVerificationId,
        scopes:            _scopes,
      );
      if (!mounted) return;
      setState(() { _result = consent; _submitting = false; });
      _goTo(4);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showError('${context.tr('couldNotSaveConsent')} $e');
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0 || _step == 4,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _step > 0 && _step < 4) {
          _goTo(_step - 1);
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(
          title: Text(widget.isReConsent ? context.tr('renewConsent') : context.tr('parentalConsent')),
          leading: _step == 0
              ? CloseButton(onPressed: () => Navigator.pop(context, null))
              : _step == 4
                  ? const SizedBox.shrink()
                  : BackButton(onPressed: () => _goTo(_step - 1)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: _StepProgress(step: _step, total: 5),
          ),
        ),
        body: PageView(
          controller:  _pageCtrl,
          physics:     const NeverScrollableScrollPhysics(),
          onPageChanged: (i) => setState(() => _step = i),
          children: [
            _GuardianDetailsStep(
              formKey:    _formKey,
              nameCtrl:   _nameCtrl,
              phoneCtrl:  _phoneCtrl,
              emailCtrl:  _emailCtrl,
              studentName: widget.studentName,
              onNext: () { if (_validateStep0()) _next(); },
            ),
            _PrivacyNoticeStep(
              lang:   _lang,
              onLangToggle: (l) => setState(() => _lang = l),
              onNext: _next,
            ),
            _ScopeSelectionStep(
              scopes:   _scopes,
              onChange: (updated) => setState(() => _scopes = updated),
              onNext:   _next,
            ),
            _OtpStep(
              method:           _method,
              onMethodChanged:  (m) => setState(() => _method = m),
              phoneNumber:      _phoneCtrl.text.trim(),
              otpSending:       _otpSending,
              otpSent:          _otpSent,
              verifying:        _verifying || _submitting,
              otpError:         _otpError,
              otpCtrl:          _otpCtrl,
              inPersonConfirmed: _inPersonConfirmed,
              onInPersonToggle: (v) => setState(() => _inPersonConfirmed = v),
              onSendOtp:        _sendOtp,
              onVerifyOtp:      _verifyOtp,
              onInPersonSubmit: _submitInPersonConsent,
            ),
            _SuccessStep(
              consent:  _result,
              onDone:   () => Navigator.pop(context, _result),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Step 0: Guardian Details ───────────────────────────────────────────────────

class _GuardianDetailsStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  final TextEditingController phoneCtrl;
  final TextEditingController emailCtrl;
  final String  studentName;
  final VoidCallback onNext;

  const _GuardianDetailsStep({
    required this.formKey,
    required this.nameCtrl,
    required this.phoneCtrl,
    required this.emailCtrl,
    required this.studentName,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _StepHeader(
            icon: Icons.person_outline,
            title: context.tr('guardianDetailsTitle'),
            subtitle: '${context.tr('consentRecordFor')} $studentName',
          ),
          const SizedBox(height: 28),
          _Field(
            controller: nameCtrl,
            label:  context.tr('guardianNameLabel'),
            icon:   Icons.badge_outlined,
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? context.tr('validationRequired') : null,
          ),
          const SizedBox(height: 16),
          _Field(
            controller: phoneCtrl,
            label:   context.tr('phoneE164Label'),
            icon:    Icons.phone_outlined,
            keyboard: TextInputType.phone,
            validator: (v) {
              if (v == null || v.trim().isEmpty) return context.tr('validationRequired');
              if (!v.trim().startsWith('+') || v.trim().length < 10) {
                return context.tr('useE164Format');
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          EmailTextFormField(
            controller: emailCtrl,
            isOptional: true,
            validator: Validators.optionalEmail,
            decoration: InputDecoration(
              labelText:    context.tr('emailOptionalLabel'),
              prefixIcon:   const Icon(Icons.email_outlined, color: AppTheme.primary),
              border:       OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10)),
              filled:       true,
              fillColor:    Colors.white,
            ),
          ),
          const SizedBox(height: 32),
          _NextButton(label: context.tr('continueLabel'), onPressed: onNext),
        ]),
      ),
    );
  }
}

// ── Step 1: Privacy Notice ────────────────────────────────────────────────────

class _PrivacyNoticeStep extends StatelessWidget {
  final String lang;
  final void Function(String) onLangToggle;
  final VoidCallback onNext;

  const _PrivacyNoticeStep({
    required this.lang,
    required this.onLangToggle,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _StepHeader(
            icon: Icons.privacy_tip_outlined,
            title: context.tr('privacyNotice'),
            subtitle: context.tr('pleaseReadBeforeConsent'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Text('${context.tr('languageColon')} ', style: const TextStyle(fontSize: 13)),
            ChoiceChip(
              label: const Text('English'),
              selected: lang == 'en',
              onSelected: (_) => onLangToggle('en'),
              selectedColor: AppTheme.primary,
              labelStyle: TextStyle(
                  color: lang == 'en' ? Colors.white : null),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('हिंदी'),
              selected: lang == 'hi',
              onSelected: (_) => onLangToggle('hi'),
              selectedColor: AppTheme.primary,
              labelStyle: TextStyle(
                  color: lang == 'hi' ? Colors.white : null),
            ),
          ]),
          const SizedBox(height: 8),
        ]),
      ),
      Expanded(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SelectableText(
            privacyNoticeBody(lang),
            style: const TextStyle(fontSize: 13, height: 1.6),
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(20),
        child: _NextButton(label: context.tr('haveReadNotice'), onPressed: onNext),
      ),
    ]);
  }
}

// ── Step 2: Scope Selection ───────────────────────────────────────────────────

class _ScopeSelectionStep extends StatelessWidget {
  final List<ConsentScope> scopes;
  final void Function(List<ConsentScope>) onChange;
  final VoidCallback onNext;

  const _ScopeSelectionStep({
    required this.scopes,
    required this.onChange,
    required this.onNext,
  });

  static const _icons = {
    'attendance':        Icons.calendar_today_outlined,
    'academic_records':  Icons.school_outlined,
    'fees':              Icons.receipt_long_outlined,
    'photos':            Icons.photo_outlined,
    'communication':     Icons.notifications_outlined,
  };

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
        child: _StepHeader(
          icon: Icons.checklist_outlined,
          title: context.tr('chooseConsents'),
          subtitle: context.tr('chooseConsentsSub'),
        ),
      ),
      Expanded(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: scopes.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final s = scopes[i];
            final required = s.dataType == 'attendance' ||
                             s.dataType == 'academic_records';
            return CheckboxListTile(
              title: Text(
                _labelFor(context, s.dataType),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(s.purpose,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              secondary: Icon(
                _icons[s.dataType] ?? Icons.data_usage_outlined,
                color: AppTheme.primary,
              ),
              value:    required ? true : s.optedIn,
              tristate: false,
              controlAffinity: ListTileControlAffinity.trailing,
              activeColor: AppTheme.primary,
              onChanged: required
                  ? null // required scopes cannot be unchecked
                  : (v) {
                      final updated = List<ConsentScope>.from(scopes);
                      updated[i] = ConsentScope(
                        dataType: s.dataType,
                        purpose:  s.purpose,
                        optedIn:  v ?? false,
                      );
                      onChange(updated);
                    },
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.all(20),
        child: _NextButton(label: context.tr('confirmSelection'), onPressed: onNext),
      ),
    ]);
  }

  String _labelFor(BuildContext context, String dt) {
    switch (dt) {
      case 'attendance':       return context.tr('scopeAttendance');
      case 'academic_records': return context.tr('scopeAcademic');
      case 'fees':             return context.tr('scopeFees');
      case 'photos':           return context.tr('scopePhotos');
      case 'communication':    return context.tr('scopeCommunication');
      default:                 return dt;
    }
  }
}

// ── Step 3: OTP / In-person ───────────────────────────────────────────────────

enum _ConsentMethod { otp, inPerson }

class _OtpStep extends StatelessWidget {
  final _ConsentMethod  method;
  final void Function(_ConsentMethod) onMethodChanged;
  final String  phoneNumber;
  final bool    otpSending;
  final bool    otpSent;
  final bool    verifying;
  final String? otpError;
  final TextEditingController otpCtrl;
  final bool    inPersonConfirmed;
  final void Function(bool) onInPersonToggle;
  final VoidCallback onSendOtp;
  final VoidCallback onVerifyOtp;
  final VoidCallback onInPersonSubmit;

  const _OtpStep({
    required this.method,
    required this.onMethodChanged,
    required this.phoneNumber,
    required this.otpSending,
    required this.otpSent,
    required this.verifying,
    required this.otpError,
    required this.otpCtrl,
    required this.inPersonConfirmed,
    required this.onInPersonToggle,
    required this.onSendOtp,
    required this.onVerifyOtp,
    required this.onInPersonSubmit,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _StepHeader(
          icon: Icons.verified_user_outlined,
          title: context.tr('verifyIdentity'),
          subtitle: context.tr('verifyIdentitySub'),
        ),
        const SizedBox(height: 24),

        // Method toggle
        Row(children: [
          Expanded(
            child: _MethodChip(
              label:    context.tr('otpViaSms'),
              icon:     Icons.sms_outlined,
              selected: method == _ConsentMethod.otp,
              onTap:    () => onMethodChanged(_ConsentMethod.otp),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _MethodChip(
              label:    context.tr('inPersonSigned'),
              icon:     Icons.draw_outlined,
              selected: method == _ConsentMethod.inPerson,
              onTap:    () => onMethodChanged(_ConsentMethod.inPerson),
            ),
          ),
        ]),
        const SizedBox(height: 24),

        if (method == _ConsentMethod.otp) ...[
          // OTP panel
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow:    [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                '${context.tr('sendingOtpTo')}\n$phoneNumber',
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              if (!otpSent) ...[
                ElevatedButton.icon(
                  onPressed: otpSending ? null : onSendOtp,
                  icon: otpSending
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_outlined),
                  label: Text(otpSending ? context.tr('sendingEllipsis') : context.tr('sendOtp')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ] else ...[
                TextField(
                  controller:   otpCtrl,
                  keyboardType: TextInputType.number,
                  maxLength:    6,
                  textAlign:    TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: context.tr('enterOtp'),
                    border:    const OutlineInputBorder(),
                    counterText: '',
                  ),
                  style: const TextStyle(
                      fontSize: 22, letterSpacing: 8, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: verifying ? null : onVerifyOtp,
                  icon: verifying
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check_circle_outline),
                  label: Text(verifying ? context.tr('verifyingEllipsis') : context.tr('verifyAndConsent')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: verifying ? null : onSendOtp,
                  child: Text(context.tr('resendOtp')),
                ),
              ],
              if (otpError != null) ...[
                const SizedBox(height: 8),
                Text(otpError!,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ]),
          ),
        ] else ...[
          // In-person panel
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(
                context.tr('inPersonHelp'),
                style: const TextStyle(fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                title: Text(
                  context.tr('inPersonConfirmText'),
                  style: const TextStyle(fontSize: 13),
                ),
                value: inPersonConfirmed,
                activeColor: AppTheme.primary,
                onChanged: (v) => onInPersonToggle(v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: inPersonConfirmed && !verifying
                    ? onInPersonSubmit
                    : null,
                icon: verifying
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.task_alt_outlined),
                label: Text(verifying ? context.tr('savingEllipsis') : context.tr('recordInPersonConsent')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.success,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ── Step 4: Success ───────────────────────────────────────────────────────────

class _SuccessStep extends StatelessWidget {
  final ParentalConsent? consent;
  final VoidCallback onDone;

  const _SuccessStep({this.consent, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: AppTheme.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.verified_outlined,
                size: 72, color: AppTheme.success),
          ),
          const SizedBox(height: 24),
          Text(
            context.tr('consentRecorded'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.primaryDark),
          ),
          const SizedBox(height: 12),
          if (consent != null)
            Text(
              '${context.tr('methodLabel')}: ${consent!.method.label}\n'
              '${context.tr('versionLabel')}: ${consent!.consentVersion}\n'
              '${context.tr('recordedLabel')}: ${_fmtDate(consent!.consentedAt.toDate())}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600, height: 1.7),
            ),
          const SizedBox(height: 8),
          Text(
            '${consent?.scopes.where((s) => s.optedIn).length ?? 0} ${context.tr('dataScopesConsentedSuffix')}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: AppTheme.success),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: onDone,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(context.tr('doneLabel'), style: const TextStyle(fontSize: 16)),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime d) =>
      '${d.day}/${d.month}/${d.year}';
}

// ── Shared small widgets ───────────────────────────────────────────────────────

class _StepProgress extends StatelessWidget {
  final int step;
  final int total;
  const _StepProgress({required this.step, required this.total});

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value:           step / (total - 1).clamp(1, total),
      backgroundColor: AppTheme.primary.withValues(alpha: 0.15),
      valueColor:      const AlwaysStoppedAnimation<Color>(AppTheme.accent),
      minHeight:       4,
    );
  }
}

class _StepHeader extends StatelessWidget {
  final IconData icon;
  final String   title;
  final String   subtitle;
  const _StepHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color:        AppTheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppTheme.primary, size: 28),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primaryDark)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
      ),
    ]);
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final IconData icon;
  final TextInputType? keyboard;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    required this.icon,
    this.keyboard,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller:   controller,
      keyboardType: keyboard,
      validator:    validator,
      decoration: InputDecoration(
        labelText:    label,
        prefixIcon:   Icon(icon, color: AppTheme.primary),
        border:       OutlineInputBorder(
            borderRadius: BorderRadius.circular(10)),
        filled:       true,
        fillColor:    Colors.white,
      ),
    );
  }
}

class _NextButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  const _NextButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon:  const Icon(Icons.arrow_forward),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _MethodChip extends StatelessWidget {
  final String   label;
  final IconData icon;
  final bool     selected;
  final VoidCallback onTap;

  const _MethodChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color:        selected ? AppTheme.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(
            color: selected ? AppTheme.primary : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(
                  color:      AppTheme.primary.withValues(alpha: 0.2),
                  blurRadius: 8,
                  offset:     const Offset(0, 2),
                )]
              : null,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: selected ? Colors.white : AppTheme.primary, size: 24),
          const SizedBox(height: 6),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize:   12,
              fontWeight: FontWeight.w600,
              color:      selected ? Colors.white : AppTheme.primary,
            ),
          ),
        ]),
      ),
    );
  }
}
