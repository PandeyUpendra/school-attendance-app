import 'package:flutter/material.dart';
import '../../models/school_onboarding.dart';
import '../../services/school_settings_service.dart';
import '../../theme.dart';
import 'step1_basic_info.dart';
import 'step2_address.dart';
import 'step3_academic.dart';
import 'step4_fees.dart';
import 'step5_communication.dart';
import 'step6_review.dart';

class SchoolOnboardingScreen extends StatefulWidget {
  final Widget destination;

  const SchoolOnboardingScreen({super.key, required this.destination});

  @override
  State<SchoolOnboardingScreen> createState() => _SchoolOnboardingScreenState();
}

class _SchoolOnboardingScreenState extends State<SchoolOnboardingScreen> {
  final _svc = SchoolSettingsService();
  final _pageCtrl = PageController();

  SchoolOnboarding _data = SchoolOnboarding();
  int _step = 0;
  bool _loading = true;
  bool _submitting = false;
  bool _resuming = false;

  // Step keys for validation
  final _step1Key = GlobalKey<Step1BasicInfoState>();
  final _step2Key = GlobalKey<Step2AddressState>();
  final _step3Key = GlobalKey<Step3AcademicState>();
  final _step4Key = GlobalKey<Step4FeesState>();
  final _step5Key = GlobalKey<Step5CommunicationState>();

  static const _stepTitles = [
    'Basic Info',
    'Address',
    'Academic Setup',
    'Fee Setup',
    'Communication',
    'Review & Submit',
  ];

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDraft() async {
    try {
      final draft = await _svc.getOnboardingStatus();
      if (draft.isNotEmpty) {
        final savedStep = (draft['currentStep'] as int? ?? 0).clamp(0, 5);
        setState(() {
          _data = SchoolOnboarding.fromJson(draft);
          _step = savedStep;
          _resuming = savedStep > 0;
          _loading = false;
        });
        if (savedStep > 0) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _pageCtrl.jumpToPage(savedStep);
          });
        }
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _saveDraft() async {
    try {
      await _svc.saveOnboardingDraft({
        ..._data.toJson(),
        'currentStep': _step,
      });
    } catch (_) {}
  }

  bool _validateCurrentStep() {
    switch (_step) {
      case 0: return _step1Key.currentState?.validate() ?? false;
      case 1: return _step2Key.currentState?.validate() ?? false;
      case 2: return _step3Key.currentState?.validate() ?? false;
      case 3: return _step4Key.currentState?.validate() ?? false;
      case 4: return _step5Key.currentState?.validate() ?? false;
      default: return true;
    }
  }

  Future<void> _onNext() async {
    if (!_validateCurrentStep()) return;
    await _saveDraft();
    if (_step < 5) {
      setState(() {
        _step++;
        _resuming = false;
      });
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  Future<void> _onBack() async {
    if (_step > 0) {
      setState(() {
        _step--;
        _resuming = false;
      });
      _pageCtrl.previousPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    }
  }

  void _goToStep(int step) {
    setState(() {
      _step = step;
      _resuming = false;
    });
    _pageCtrl.animateToPage(step,
        duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
  }

  Future<void> _submit() async {
    setState(() => _submitting = true);
    try {
      await _svc.completeOnboarding(_data.toJson());
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('School setup complete!'),
          backgroundColor: AppTheme.success,
        ),
      );
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => widget.destination),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger));
        setState(() => _submitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Column(children: [
          _buildHeader(),
          if (_resuming)
            Material(
              color: AppTheme.warning.withOpacity(0.12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  const Icon(Icons.restore, size: 16, color: AppTheme.warning),
                  const SizedBox(width: 8),
                  const Text('Resuming your setup…',
                      style: TextStyle(color: AppTheme.warning, fontWeight: FontWeight.w600, fontSize: 13)),
                  const Spacer(),
                  TextButton(
                    onPressed: () => setState(() => _resuming = false),
                    child: const Text('Dismiss', style: TextStyle(fontSize: 12)),
                  ),
                ]),
              ),
            ),
          Expanded(
            child: PageView(
              controller: _pageCtrl,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                Step1BasicInfo(
                  key: _step1Key,
                  initial: _data,
                  onChanged: (d) => setState(() => _data = d),
                ),
                Step2Address(
                  key: _step2Key,
                  initial: _data,
                  onChanged: (d) => setState(() => _data = d),
                ),
                Step3Academic(
                  key: _step3Key,
                  initial: _data,
                  onChanged: (d) => setState(() => _data = d),
                ),
                Step4Fees(
                  key: _step4Key,
                  initial: _data,
                  onChanged: (d) => setState(() => _data = d),
                ),
                Step5Communication(
                  key: _step5Key,
                  initial: _data,
                  onChanged: (d) => setState(() => _data = d),
                ),
                Step6Review(
                  data: _data,
                  onEditStep: _goToStep,
                ),
              ],
            ),
          ),
          _buildBottomNav(),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [AppTheme.primaryDark, AppTheme.primaryMid],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.school, color: Colors.white60, size: 16),
              const SizedBox(width: 8),
              Text(
                'SCHOOL SETUP  ·  STEP ${_step + 1} OF 6',
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
              _stepTitles[_step],
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (_step + 1) / 6,
                minHeight: 6,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    final isLast = _step == 5;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, -2)),
        ],
      ),
      child: Row(children: [
        if (_step > 0)
          Expanded(
            child: OutlinedButton.icon(
              icon: const Icon(Icons.arrow_back),
              label: const Text('Back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                side: BorderSide(color: Colors.grey.shade400),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _onBack,
            ),
          ),
        if (_step > 0) const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : Icon(isLast ? Icons.check_circle_outline : Icons.arrow_forward),
            label: Text(
              _submitting
                  ? 'Saving…'
                  : isLast
                      ? 'Complete Setup'
                      : 'Next',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isLast ? AppTheme.success : AppTheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _submitting
                ? null
                : isLast
                    ? _submit
                    : _onNext,
          ),
        ),
      ]),
    );
  }
}
