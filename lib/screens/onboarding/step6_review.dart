import 'package:flutter/material.dart';
import '../../models/school_onboarding.dart';
import '../../theme.dart';

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
          title: 'Basic Info',
          stepIndex: 0,
          onEdit: onEditStep,
          children: [
            if (data.logoUrl.isNotEmpty)
              Center(
                child: CircleAvatar(
                  radius: 36,
                  backgroundImage: NetworkImage(data.logoUrl),
                ),
              ),
            if (data.logoUrl.isNotEmpty) const SizedBox(height: 10),
            _row('School Name', data.schoolName),
            _row('Type', data.schoolType),
            _row('Board', data.board),
            _row('Phone', data.phone),
            _row('Email', data.email),
            _row('Principal', data.principalName),
            if (data.establishedYear.isNotEmpty)
              _row('Est. Year', data.establishedYear),
          ],
        ),
        _card(
          title: 'Address',
          stepIndex: 1,
          onEdit: onEditStep,
          children: [
            _row('Address', data.address),
            _row('City', data.city),
            _row('State', data.state),
            _row('PIN Code', data.pinCode),
            if (data.website.isNotEmpty) _row('Website', data.website),
          ],
        ),
        _card(
          title: 'Academic Setup',
          stepIndex: 2,
          onEdit: onEditStep,
          children: [
            _row('Classes', 'Class ${data.classesFrom} to ${data.classesTo}'),
            _row('Sections', data.sectionsPerClass.join(', ')),
            _row('Total Classes', '${data.classList.length}'),
            _row('Academic Year', 'Starts in ${data.academicYearStart}'),
            _row('Working Days', data.workingDays),
            _row('Periods/Day', '${data.periodsPerDay}'),
            _row('Period Duration', '${data.periodDuration} min'),
            _row('Lunch After', 'Period ${data.lunchAfterPeriod}'),
          ],
        ),
        _card(
          title: 'Fee Settings',
          stepIndex: 3,
          onEdit: onEditStep,
          children: [
            _row('Frequency', data.feeFrequency),
            _row('Due Date', '${data.feeDueDate}${_ordinal(data.feeDueDate)} of month'),
            _row('Late Fee', data.lateFeeEnabled ? '₹${data.lateFeePerDay}/day' : 'Not applicable'),
            _row('Reminder', '${data.reminderDaysBefore} days before due'),
          ],
        ),
        _card(
          title: 'Communication',
          stepIndex: 4,
          onEdit: onEditStep,
          children: [
            _row('WhatsApp', data.whatsappEnabled
                ? 'Enabled (+91 ${data.schoolWhatsapp})'
                : 'Disabled'),
            _row('Language', data.preferredLanguage),
            _row('Bus Service', data.busServiceAvailable
                ? 'Yes (${data.busRouteCount} routes)'
                : 'No'),
            if (data.schoolTagline.isNotEmpty)
              _row('Tagline', '"${data.schoolTagline}"'),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.success.withOpacity(0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.success.withOpacity(0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.check_circle_outline, color: AppTheme.success, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Review everything above. Tap "Complete Setup" to save your school configuration.',
                style: TextStyle(color: AppTheme.success, fontSize: 13),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _card({
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
            color: AppTheme.primary.withOpacity(0.06),
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
              label: const Text('Edit', style: TextStyle(fontSize: 12)),
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
