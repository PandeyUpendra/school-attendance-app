class SchoolOnboarding {
  String schoolName;
  String logoUrl;
  String schoolType;
  String board;
  String address;
  String city;
  String state;
  String pinCode;
  String phone;
  String email;
  String principalName;
  String establishedYear;
  String website;
  int classesFrom;
  int classesTo;
  List<String> sectionsPerClass;
  List<String> classList;
  String academicYearStart;
  String workingDays;
  int periodsPerDay;
  int periodDuration;
  int lunchAfterPeriod;
  String feeFrequency;
  int feeDueDate;
  bool lateFeeEnabled;
  int lateFeePerDay;
  int reminderDaysBefore;
  bool whatsappEnabled;
  String schoolWhatsapp;
  String preferredLanguage;
  bool busServiceAvailable;
  int busRouteCount;
  String schoolTagline;
  bool isCompleted;
  int currentStep;

  SchoolOnboarding({
    this.schoolName = '',
    this.logoUrl = '',
    this.schoolType = 'Private',
    this.board = 'CBSE',
    this.address = '',
    this.city = '',
    this.state = '',
    this.pinCode = '',
    this.phone = '',
    this.email = '',
    this.principalName = '',
    this.establishedYear = '',
    this.website = '',
    this.classesFrom = 1,
    this.classesTo = 10,
    this.sectionsPerClass = const ['A'],
    this.classList = const [],
    this.academicYearStart = 'April',
    this.workingDays = 'Mon-Sat',
    this.periodsPerDay = 8,
    this.periodDuration = 45,
    this.lunchAfterPeriod = 4,
    this.feeFrequency = 'Monthly',
    this.feeDueDate = 10,
    this.lateFeeEnabled = false,
    this.lateFeePerDay = 0,
    this.reminderDaysBefore = 7,
    this.whatsappEnabled = false,
    this.schoolWhatsapp = '',
    this.preferredLanguage = 'English',
    this.busServiceAvailable = false,
    this.busRouteCount = 0,
    this.schoolTagline = '',
    this.isCompleted = false,
    this.currentStep = 0,
  });

  SchoolOnboarding copyWith({
    String? schoolName,
    String? logoUrl,
    String? schoolType,
    String? board,
    String? address,
    String? city,
    String? state,
    String? pinCode,
    String? phone,
    String? email,
    String? principalName,
    String? establishedYear,
    String? website,
    int? classesFrom,
    int? classesTo,
    List<String>? sectionsPerClass,
    List<String>? classList,
    String? academicYearStart,
    String? workingDays,
    int? periodsPerDay,
    int? periodDuration,
    int? lunchAfterPeriod,
    String? feeFrequency,
    int? feeDueDate,
    bool? lateFeeEnabled,
    int? lateFeePerDay,
    int? reminderDaysBefore,
    bool? whatsappEnabled,
    String? schoolWhatsapp,
    String? preferredLanguage,
    bool? busServiceAvailable,
    int? busRouteCount,
    String? schoolTagline,
    bool? isCompleted,
    int? currentStep,
  }) => SchoolOnboarding(
    schoolName: schoolName ?? this.schoolName,
    logoUrl: logoUrl ?? this.logoUrl,
    schoolType: schoolType ?? this.schoolType,
    board: board ?? this.board,
    address: address ?? this.address,
    city: city ?? this.city,
    state: state ?? this.state,
    pinCode: pinCode ?? this.pinCode,
    phone: phone ?? this.phone,
    email: email ?? this.email,
    principalName: principalName ?? this.principalName,
    establishedYear: establishedYear ?? this.establishedYear,
    website: website ?? this.website,
    classesFrom: classesFrom ?? this.classesFrom,
    classesTo: classesTo ?? this.classesTo,
    sectionsPerClass: sectionsPerClass ?? List.from(this.sectionsPerClass),
    classList: classList ?? List.from(this.classList),
    academicYearStart: academicYearStart ?? this.academicYearStart,
    workingDays: workingDays ?? this.workingDays,
    periodsPerDay: periodsPerDay ?? this.periodsPerDay,
    periodDuration: periodDuration ?? this.periodDuration,
    lunchAfterPeriod: lunchAfterPeriod ?? this.lunchAfterPeriod,
    feeFrequency: feeFrequency ?? this.feeFrequency,
    feeDueDate: feeDueDate ?? this.feeDueDate,
    lateFeeEnabled: lateFeeEnabled ?? this.lateFeeEnabled,
    lateFeePerDay: lateFeePerDay ?? this.lateFeePerDay,
    reminderDaysBefore: reminderDaysBefore ?? this.reminderDaysBefore,
    whatsappEnabled: whatsappEnabled ?? this.whatsappEnabled,
    schoolWhatsapp: schoolWhatsapp ?? this.schoolWhatsapp,
    preferredLanguage: preferredLanguage ?? this.preferredLanguage,
    busServiceAvailable: busServiceAvailable ?? this.busServiceAvailable,
    busRouteCount: busRouteCount ?? this.busRouteCount,
    schoolTagline: schoolTagline ?? this.schoolTagline,
    isCompleted: isCompleted ?? this.isCompleted,
    currentStep: currentStep ?? this.currentStep,
  );

  Map<String, dynamic> toJson() => {
    'schoolName': schoolName,
    'logoUrl': logoUrl,
    'schoolType': schoolType,
    'board': board,
    'address': address,
    'city': city,
    'state': state,
    'pinCode': pinCode,
    'phone': phone,
    'email': email,
    'principalName': principalName,
    'establishedYear': establishedYear,
    'website': website,
    'classesFrom': classesFrom,
    'classesTo': classesTo,
    'sectionsPerClass': sectionsPerClass,
    'classList': classList,
    'academicYearStart': academicYearStart,
    'workingDays': workingDays,
    'periodsPerDay': periodsPerDay,
    'periodDuration': periodDuration,
    'lunchAfterPeriod': lunchAfterPeriod,
    'feeFrequency': feeFrequency,
    'feeDueDate': feeDueDate,
    'lateFeeEnabled': lateFeeEnabled,
    'lateFeePerDay': lateFeePerDay,
    'reminderDaysBefore': reminderDaysBefore,
    'whatsappEnabled': whatsappEnabled,
    'schoolWhatsapp': schoolWhatsapp,
    'preferredLanguage': preferredLanguage,
    'busServiceAvailable': busServiceAvailable,
    'busRouteCount': busRouteCount,
    'schoolTagline': schoolTagline,
    'isCompleted': isCompleted,
    'currentStep': currentStep,
  };

  factory SchoolOnboarding.fromJson(Map<String, dynamic> j) => SchoolOnboarding(
    schoolName: j['schoolName'] as String? ?? '',
    logoUrl: j['logoUrl'] as String? ?? '',
    schoolType: j['schoolType'] as String? ?? 'Private',
    board: j['board'] as String? ?? 'CBSE',
    address: j['address'] as String? ?? '',
    city: j['city'] as String? ?? '',
    state: j['state'] as String? ?? '',
    pinCode: j['pinCode'] as String? ?? '',
    phone: j['phone'] as String? ?? '',
    email: j['email'] as String? ?? '',
    principalName: j['principalName'] as String? ?? '',
    establishedYear: j['establishedYear'] as String? ?? '',
    website: j['website'] as String? ?? '',
    classesFrom: j['classesFrom'] as int? ?? 1,
    classesTo: j['classesTo'] as int? ?? 10,
    sectionsPerClass: List<String>.from(j['sectionsPerClass'] as List? ?? ['A']),
    classList: List<String>.from(j['classList'] as List? ?? []),
    academicYearStart: j['academicYearStart'] as String? ?? 'April',
    workingDays: j['workingDays'] as String? ?? 'Mon-Sat',
    periodsPerDay: j['periodsPerDay'] as int? ?? 8,
    periodDuration: j['periodDuration'] as int? ?? 45,
    lunchAfterPeriod: j['lunchAfterPeriod'] as int? ?? 4,
    feeFrequency: j['feeFrequency'] as String? ?? 'Monthly',
    feeDueDate: j['feeDueDate'] as int? ?? 10,
    lateFeeEnabled: j['lateFeeEnabled'] as bool? ?? false,
    lateFeePerDay: j['lateFeePerDay'] as int? ?? 0,
    reminderDaysBefore: j['reminderDaysBefore'] as int? ?? 7,
    whatsappEnabled: j['whatsappEnabled'] as bool? ?? false,
    schoolWhatsapp: j['schoolWhatsapp'] as String? ?? '',
    preferredLanguage: j['preferredLanguage'] as String? ?? 'English',
    busServiceAvailable: j['busServiceAvailable'] as bool? ?? false,
    busRouteCount: j['busRouteCount'] as int? ?? 0,
    schoolTagline: j['schoolTagline'] as String? ?? '',
    isCompleted: j['isCompleted'] as bool? ?? false,
    currentStep: j['currentStep'] as int? ?? 0,
  );

  static List<String> generateClassList(
      int from, int to, List<String> sections) {
    final list = <String>[];
    for (int c = from; c <= to; c++) {
      for (final s in sections) {
        list.add('$c-$s');
      }
    }
    return list;
  }
}
