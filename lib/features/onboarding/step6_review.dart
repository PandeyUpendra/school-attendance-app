import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../../l10n/app_strings.dart';
import '../../models/school_onboarding.dart';
import '../../theme.dart';

/// Localised label for a fee frequency (stored value stays English).
String _localizedFreq(BuildContext c, String f) => switch (f) {
      'Quarterly' => c.tr('freqQuarterly'),
      'Half-Yearly' => c.tr('freqHalfYearly'),
      'Annually' => c.tr('freqAnnually'),
      _ => c.tr('freqMonthly'),
    };

/// Localised label for a preferred-language choice (stored value stays English).
String _localizedLang(BuildContext c, String l) => switch (l) {
      'Hindi' => c.tr('langHindi'),
      'Both' => c.tr('langBoth'),
      _ => c.tr('langEnglish'),
    };

class Step6Review extends StatelessWidget {
  final SchoolOnboarding data;
  final void Function(int step) onEditStep;

  const Step6Review({
    super.key,
    required this.data,
    required this.onEditStep,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card(
          context: context,
          title: context.tr('obStepBasicInfo'),
          stepIndex: 0,
          onEdit: onEditStep,
          children: [
            if (data.logoUrl.isNotEmpty)
              Center(
                child: CircleAvatar(
                  radius: 36,
                  backgroundImage: CachedNetworkImageProvider(data.logoUrl),
                ),
              ),
            if (data.logoUrl.isNotEmpty) const SizedBox(height: 10),
            _row(context.tr('schoolNameLabel'), data.schoolName),
            _row(context.tr('rvType'), data.schoolType),
            _row(context.tr('boardLabel'), data.board),
            _row(context.tr('phone'), data.phone),
            _row(context.tr('email'), data.email),
            _row(context.tr('rvPrincipal'), data.principalName),
            if (data.establishedYear.isNotEmpty)
              _row(context.tr('rvEstYear'), data.establishedYear),
          ],
        ),
        _card(
          context: context,
          title: context.tr('obStepAddress'),
          stepIndex: 1,
          onEdit: onEditStep,
          children: [
            _row(context.tr('obStepAddress'), data.address),
            _row(context.tr('cityLabel'), data.city),
            _row(context.tr('stateLabel'), data.state),
            _row(context.tr('pinCodeLabel'), data.pinCode),
            if (data.website.isNotEmpty) _row(context.tr('rvWebsite'), data.website),
          ],
        ),
        _card(
          context: context,
          title: context.tr('obStepAcademic'),
          stepIndex: 2,
          onEdit: onEditStep,
          children: [
            _row(context.tr('classesColon'), 'Class ${data.classesFrom} to ${data.classesTo}'),
            _row(context.tr('sectionsPerClass'), data.sectionsPerClass.join(', ')),
            _row(context.tr('rvTotalClasses'), '${data.classList.length}'),
            _row(context.tr('rvAcademicYear'), '${context.tr('startsInPrefix')} ${data.academicYearStart}'),
            _row(context.tr('workingDaysLabel'), data.workingDays),
            _row(context.tr('rvPeriodsDay'), '${data.periodsPerDay}'),
            _row(context.tr('periodDurationLabel'), '${data.periodDuration} min'),
            _row(context.tr('rvLunchAfter'), '${context.tr('periodWord')} ${data.lunchAfterPeriod}'),
          ],
        ),
        _card(
          context: context,
          title: context.tr('feeSettings'),
          stepIndex: 3,
          onEdit: onEditStep,
          children: [
            _row(context.tr('rvFrequency'), _localizedFreq(context, data.feeFrequency)),
            _row(context.tr('rvDueDate'), '${data.feeDueDate}${_ordinal(data.feeDueDate)} ${context.tr('ofMonth')}'),
            _row(context.tr('rvLateFee'), data.lateFeeEnabled ? '₹${data.lateFeePerDay}${context.tr('perDaySuffix')}' : context.tr('notApplicable')),
            _row(context.tr('rvReminder'), '${data.reminderDaysBefore} ${context.tr('daysBeforeDue')}'),
          ],
        ),
        _card(
          context: context,
          title: context.tr('obStepCommunication'),
          stepIndex: 4,
          onEdit: onEditStep,
          children: [
            _row('WhatsApp', data.whatsappEnabled
                ? '${context.tr('enabledWord')} (+91 ${data.schoolWhatsapp})'
                : context.tr('disabledWord')),
            _row(context.tr('language'), _localizedLang(context, data.preferredLanguage)),
            _row(context.tr('rvBusService'), data.busServiceAvailable
                ? '${context.tr('yesWord')} (${data.busRouteCount} ${context.tr('routesWord')})'
                : context.tr('noWordCap')),
            if (data.schoolTagline.isNotEmpty)
              _row(context.tr('rvTagline'), '"${data.schoolTagline}"'),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.success.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.success.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.tr('reviewFooter'),
                style: const TextStyle(color: AppTheme.success, fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _card({
    required BuildContext context,
    required String title,
    required int stepIndex,
    required void Function(int) onEdit,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.primary.withValues(alpha: 0.06),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppTheme.primary)),
            const Spacer(),
            TextButton.icon(
              onPressed: () => onEdit(stepIndex),
              icon: const Icon(Icons.edit_outlined, size: 14),
              label: Text(context.tr('editBtn'), style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
        ),
      ]),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 110,
          child: Text(label,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ),
      ]),
    );
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return 'th';
    switch (n % 10) {
      case 1: return 'st';
      case 2: return 'nd';
      case 3: return 'rd';
      default: return 'th';
    }
  }
}
