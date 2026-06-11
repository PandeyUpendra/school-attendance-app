/// Common announcement titles → editable default message templates.
///
/// Selecting a title in an announcement composer pre-fills the title and message
/// fields with the matching template; both stay editable so the author can tweak
/// the wording before sending. Ordered most-common first.
const Map<String, String> kAnnouncementTemplates = {
  'Holiday Notice':
      'Dear all, the school will remain closed on [date] on account of [occasion]. '
      'Regular classes will resume on [date]. Wishing everyone a happy holiday.',
  'Exam Schedule':
      'The [exam name] examinations will be held from [start date] to [end date]. '
      'The detailed datesheet is attached. Students are advised to prepare accordingly.',
  'Fee Reminder':
      'This is a gentle reminder that the school fee for [period] is due by [date]. '
      'Kindly clear any pending dues at the earliest to avoid a late fee.',
  'Parent Meeting':
      'A Parent-Teacher Meeting is scheduled on [date] from [time] to [time]. '
      'Parents are requested to attend to discuss their ward’s progress.',
  'Sports Day':
      'Our Annual Sports Day will be held on [date] at [venue]. '
      'All students are encouraged to participate. Parents are warmly invited to attend.',
  'School Reopening':
      'The school will reopen on [date] after the [break name] break. '
      'Classes will follow the regular timetable. We look forward to welcoming everyone back.',
  'Result Declaration':
      'The results for [exam/term] will be declared on [date]. '
      'Report cards will be available [where/how]. Please reach out for any clarification.',
  'PTM Reminder':
      'Reminder: the Parent-Teacher Meeting is on [date] at [time]. '
      'Your presence is important for your ward’s progress. Thank you.',
};
