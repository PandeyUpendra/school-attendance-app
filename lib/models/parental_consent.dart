import 'package:cloud_firestore/cloud_firestore.dart';

/// Current consent version. Bump this string when the privacy notice changes
/// to trigger re-consent for all existing students.
const kCurrentConsentVersion = 'v1.0';

/// A single data-processing scope the guardian explicitly opts into or out of.
class ConsentScope {
  final String dataType;  // e.g. 'attendance', 'academic_records', 'fees', 'photos'
  final String purpose;   // human-readable purpose
  final bool   optedIn;

  const ConsentScope({
    required this.dataType,
    required this.purpose,
    required this.optedIn,
  });

  Map<String, dynamic> toJson() => {
    'dataType': dataType,
    'purpose':  purpose,
    'optedIn':  optedIn,
  };

  factory ConsentScope.fromJson(Map<String, dynamic> j) => ConsentScope(
    dataType: j['dataType'] as String? ?? '',
    purpose:  j['purpose']  as String? ?? '',
    optedIn:  j['optedIn']  as bool?   ?? true,
  );
}

/// The method used to obtain consent.
enum ConsentMethod {
  otpVerified,    // Guardian verified SMS OTP during enrollment
  inPersonSigned, // Paper form signed in-person; coordinator marks it
}

extension ConsentMethodLabel on ConsentMethod {
  String get label {
    switch (this) {
      case ConsentMethod.otpVerified:    return 'OTP Verified';
      case ConsentMethod.inPersonSigned: return 'In-Person Signed';
    }
  }

  String get value {
    switch (this) {
      case ConsentMethod.otpVerified:    return 'otp_verified';
      case ConsentMethod.inPersonSigned: return 'in_person_signed';
    }
  }

  static ConsentMethod fromValue(String v) {
    switch (v) {
      case 'in_person_signed': return ConsentMethod.inPersonSigned;
      default:                 return ConsentMethod.otpVerified;
    }
  }
}

/// Parental consent record for a student's data processing.
///
/// Stored at: `schools/{sid}/students/{studentDocId}/consents/{consentId}`
class ParentalConsent {
  final String   id;            // Firestore document ID (auto-generated)
  final String   studentId;     // Student doc ID, e.g. Class_9-A__1
  final String   guardianName;
  final String   guardianPhone;
  final String?  guardianEmail;
  final String   consentVersion; // e.g. 'v1.0' — must match kCurrentConsentVersion for active
  final Timestamp consentedAt;
  final ConsentMethod method;
  final String?  ipAddress;      // best-effort, optional
  final String?  otpVerificationId;
  final List<ConsentScope> scopes;
  final Timestamp? withdrawnAt;  // null = still active
  final String?  withdrawnReason;

  const ParentalConsent({
    this.id = '',
    required this.studentId,
    required this.guardianName,
    required this.guardianPhone,
    this.guardianEmail,
    required this.consentVersion,
    required this.consentedAt,
    required this.method,
    this.ipAddress,
    this.otpVerificationId,
    required this.scopes,
    this.withdrawnAt,
    this.withdrawnReason,
  });

  /// True when this record is an active, current-version consent.
  bool get isActive =>
      withdrawnAt == null && consentVersion == kCurrentConsentVersion;

  /// True when the consent was given but the version is outdated.
  bool get isStale =>
      withdrawnAt == null && consentVersion != kCurrentConsentVersion;

  Map<String, dynamic> toJson() => {
    'studentId':           studentId,
    'guardianName':        guardianName,
    'guardianPhone':       guardianPhone,
    if (guardianEmail != null) 'guardianEmail': guardianEmail,
    'consentVersion':      consentVersion,
    'consentedAt':         consentedAt,
    'method':              method.value,
    if (ipAddress != null)            'ipAddress':            ipAddress,
    if (otpVerificationId != null)    'otpVerificationId':    otpVerificationId,
    'scopes':              scopes.map((s) => s.toJson()).toList(),
    if (withdrawnAt != null)          'withdrawnAt':          withdrawnAt,
    if (withdrawnReason != null)      'withdrawnReason':      withdrawnReason,
  };

  factory ParentalConsent.fromDoc(String docId, Map<String, dynamic> j) =>
      ParentalConsent(
        id:                docId,
        studentId:         j['studentId']           as String?   ?? '',
        guardianName:      j['guardianName']         as String?   ?? '',
        guardianPhone:     j['guardianPhone']         as String?   ?? '',
        guardianEmail:     j['guardianEmail']         as String?,
        consentVersion:    j['consentVersion']        as String?   ?? '',
        consentedAt:       j['consentedAt']            as Timestamp? ?? Timestamp.now(),
        method:            ConsentMethodLabel.fromValue(j['method'] as String? ?? ''),
        ipAddress:         j['ipAddress']             as String?,
        otpVerificationId: j['otpVerificationId']     as String?,
        scopes:            ((j['scopes'] as List?) ?? [])
                               .map((e) => ConsentScope.fromJson(Map<String, dynamic>.from(e as Map)))
                               .toList(),
        withdrawnAt:       j['withdrawnAt']           as Timestamp?,
        withdrawnReason:   j['withdrawnReason']       as String?,
      );

  /// Default scope list shown to guardians — all opted-in by default.
  static List<ConsentScope> defaultScopes() => [
    const ConsentScope(
      dataType: 'attendance',
      purpose:  'Track daily presence and generate attendance reports',
      optedIn:  true,
    ),
    const ConsentScope(
      dataType: 'academic_records',
      purpose:  'Store exam marks, grades, and report cards',
      optedIn:  true,
    ),
    const ConsentScope(
      dataType: 'fees',
      purpose:  'Record and communicate fee payments and dues',
      optedIn:  true,
    ),
    const ConsentScope(
      dataType: 'photos',
      purpose:  'Store profile photo for identification in school records',
      optedIn:  true,
    ),
    const ConsentScope(
      dataType: 'communication',
      purpose:  'Send notifications, homework alerts and announcements',
      optedIn:  true,
    ),
  ];
}
