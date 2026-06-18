/// Common announcement titles → editable default message templates.
///
/// Selecting a title in an announcement composer pre-fills the title and message
/// fields with the matching template; both stay editable so the author can tweak
/// the wording before sending. Ordered most-common first.
const Map<String, String> kAnnouncementTemplates = {
  'Staff Meeting':
      'Dear Principal, Coordinators, and Staff members,\n\n'
      'A general staff meeting is scheduled on [Date] at [Time] in the [Venue/Conference Room] '
      'to discuss [Topics/Academic Agenda]. All teaching and non-teaching staff are required '
      'to attend. Please come prepared with your progress reports.\n\n'
      'Regards,\nSchool Owner',
  'Policy & Regulations Update':
      'Dear Staff,\n\n'
      'Please note that a revised policy regarding [Policy Topic, e.g., leaves / code of conduct / school timings] '
      'will come into effect from [Date]. Kindly review the detailed guidelines sent to your email '
      'and ensure compliance.\n\n'
      'Regards,\nSchool Owner',
  'Performance & Planning Review':
      'Dear Principal and Coordinators,\n\n'
      'A performance review and academic planning meeting will be held on [Date] at [Time] '
      'to evaluate syllabus progress, student performance, and upcoming exam readiness. '
      'Please bring your respective reports.\n\n'
      'Regards,\nSchool Owner',
  'Salary & Benefits Update':
      'Dear Staff,\n\n'
      'This is to inform you that the salaries and bonuses for the month of [Month/Year] '
      'have been disbursed. We sincerely thank you all for your dedication, hard work, '
      'and continuous contribution to our school\'s progress.\n\n'
      'Regards,\nSchool Owner',
  'Infrastructure & Facility Upgrades':
      'Dear Staff,\n\n'
      'We are pleased to announce the upgrade/addition of [Facility/Equipment, e.g., computer lab / smartboards / library] '
      'starting from [Date]. Coordinators, please coordinate with teachers to schedule orientation and class usage slots.\n\n'
      'Regards,\nSchool Owner',
  'Appreciation & Recognition':
      'Dear Team,\n\n'
      'I want to express my heartfelt appreciation to the Principal, coordinators, teachers, and support staff '
      'for the outstanding execution of [Event Name, e.g., Annual Sports Day / School Exhibition]. '
      'Your teamwork and dedication made it a grand success.\n\n'
      'Regards,\nSchool Owner',
  'New Appointment / Promotion':
      'Dear Staff,\n\n'
      'We are pleased to announce the appointment/promotion of [Name] as the new [Role/Designation, e.g., Principal / Head Coordinator] '
      'starting from [Date]. Let us congratulate them and extend our full support in their new role.\n\n'
      'Regards,\nSchool Owner',
  'Calendar & Holiday Adjustment':
      'Dear Staff,\n\n'
      'Please note that [Date] will be a working day for all staff members to compensate for [Reason/Holiday]. '
      'We will follow the timetable of [Day Name]. Your cooperation in this matter is highly appreciated.\n\n'
      'Regards,\nSchool Owner',
};
