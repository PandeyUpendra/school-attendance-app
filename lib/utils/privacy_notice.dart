/// Bilingual privacy notice strings for parental consent.
///
/// When the privacy notice content changes, bump [kCurrentConsentVersion]
/// in parental_consent.dart to trigger fresh consent from all guardians.
library privacy_notice;

// ── English ───────────────────────────────────────────────────────────────────

const kPrivacyNoticeTitleEn = 'Parental Consent & Privacy Notice';

const kPrivacyNoticeBodyEn = '''
PRIVACY NOTICE — STUDENT DATA PROCESSING

This notice explains how we collect, use, and protect information about your child.

━━━━━━━━━━━━━━━━━━━━━━━━
WHAT DATA WE COLLECT
━━━━━━━━━━━━━━━━━━━━━━━━
• Student name, roll number, class, date of birth, gender
• Parent/guardian name, phone number, and email address
• Daily attendance records (Present / Absent / Leave)
• Exam marks, grades, and report cards
• Fee payment history and outstanding dues
• Profile photograph (if provided)
• Emergency contact information

━━━━━━━━━━━━━━━━━━━━━━━━
WHY WE COLLECT IT
━━━━━━━━━━━━━━━━━━━━━━━━
• Academic records — to track learning progress and issue report cards
• Communication — to notify you about attendance, homework, and announcements
• Fees — to record payments and send reminders for pending dues
• Safety — to contact you quickly in emergencies

━━━━━━━━━━━━━━━━━━━━━━━━
WHO HAS ACCESS
━━━━━━━━━━━━━━━━━━━━━━━━
• Class teacher — attendance and academic records only
• Subject teachers — marks and assignment data only
• Coordinator — all records for administrative purposes
• Principal — school-wide oversight
• Parent/Guardian — your child's records via Guardian Portal only

Data is NOT shared with third parties or used for advertising.

━━━━━━━━━━━━━━━━━━━━━━━━
YOUR RIGHTS
━━━━━━━━━━━━━━━━━━━━━━━━
• Right to withdraw consent at any time from the Guardian Portal
• Right to request deletion of your child's data (contact school admin)
• Right to view all data we hold about your child
• Right to correct inaccurate information

Withdrawing consent will flag the student record for admin review.
The school may be required to retain certain records (e.g. attendance)
under government regulations even after withdrawal.

━━━━━━━━━━━━━━━━━━━━━━━━
DATA STORAGE & SECURITY
━━━━━━━━━━━━━━━━━━━━━━━━
All data is stored securely on Google Firebase infrastructure with
encryption at rest and in transit. Access is controlled by role-based
permissions. Data is retained for the duration of enrollment plus
one academic year after leaving.

━━━━━━━━━━━━━━━━━━━━━━━━
CONTACT / GRIEVANCES
━━━━━━━━━━━━━━━━━━━━━━━━
For questions, complaints, or to exercise your rights, contact
the school administration. A grievance must be resolved within 30 days.

By completing this consent, you confirm you have read and understood
this notice and agree to the processing of your child's data as described.
''';

// ── Hindi ─────────────────────────────────────────────────────────────────────

const kPrivacyNoticeTitleHi = 'अभिभावक सहमति एवं गोपनीयता सूचना';

const kPrivacyNoticeBodyHi = '''
गोपनीयता सूचना — छात्र डेटा प्रसंस्करण

यह सूचना बताती है कि हम आपके बच्चे के बारे में जानकारी कैसे एकत्र करते हैं, उपयोग करते हैं और सुरक्षित रखते हैं।

━━━━━━━━━━━━━━━━━━━━━━━━
हम क्या डेटा एकत्र करते हैं
━━━━━━━━━━━━━━━━━━━━━━━━
• छात्र का नाम, रोल नंबर, कक्षा, जन्म तिथि, लिंग
• माता-पिता/अभिभावक का नाम, फोन नंबर और ईमेल पता
• दैनिक उपस्थिति रिकॉर्ड (उपस्थित / अनुपस्थित / अवकाश)
• परीक्षा अंक, ग्रेड और रिपोर्ट कार्ड
• शुल्क भुगतान इतिहास और बकाया राशि
• प्रोफाइल फोटो (यदि प्रदान की गई हो)
• आपातकालीन संपर्क जानकारी

━━━━━━━━━━━━━━━━━━━━━━━━
हम इसे क्यों एकत्र करते हैं
━━━━━━━━━━━━━━━━━━━━━━━━
• शैक्षणिक रिकॉर्ड — सीखने की प्रगति को ट्रैक करने और रिपोर्ट कार्ड जारी करने के लिए
• संचार — उपस्थिति, गृहकार्य और सूचनाओं के बारे में आपको सूचित करने के लिए
• शुल्क — भुगतान दर्ज करने और बकाया शुल्क की याद दिलाने के लिए
• सुरक्षा — आपातकाल में आपसे जल्दी संपर्क करने के लिए

━━━━━━━━━━━━━━━━━━━━━━━━
किसकी पहुँच है
━━━━━━━━━━━━━━━━━━━━━━━━
• कक्षा शिक्षक — केवल उपस्थिति और शैक्षणिक रिकॉर्ड
• विषय शिक्षक — केवल अंक और असाइनमेंट डेटा
• समन्वयक — प्रशासनिक उद्देश्यों के लिए सभी रिकॉर्ड
• प्रधानाचार्य — स्कूल-स्तरीय निगरानी
• माता-पिता/अभिभावक — केवल गार्जियन पोर्टल के माध्यम से अपने बच्चे के रिकॉर्ड

डेटा को तृतीय पक्षों के साथ साझा नहीं किया जाता है और विज्ञापन के लिए उपयोग नहीं किया जाता है।

━━━━━━━━━━━━━━━━━━━━━━━━
आपके अधिकार
━━━━━━━━━━━━━━━━━━━━━━━━
• कभी भी गार्जियन पोर्टल से सहमति वापस लेने का अधिकार
• अपने बच्चे का डेटा हटाने का अनुरोध करने का अधिकार (स्कूल प्रशासन से संपर्क करें)
• हमारे पास आपके बच्चे के बारे में सभी डेटा देखने का अधिकार
• गलत जानकारी सुधारने का अधिकार

सहमति वापस लेने पर छात्र रिकॉर्ड को व्यवस्थापक समीक्षा के लिए चिह्नित किया जाएगा।
सरकारी नियमों के तहत स्कूल को कुछ रिकॉर्ड (जैसे उपस्थिति) वापसी के बाद भी
बनाए रखने की आवश्यकता हो सकती है।

━━━━━━━━━━━━━━━━━━━━━━━━
डेटा संग्रहण और सुरक्षा
━━━━━━━━━━━━━━━━━━━━━━━━
सभी डेटा Google Firebase इंफ्रास्ट्रक्चर पर एन्क्रिप्शन के साथ सुरक्षित रूप से
संग्रहीत है। पहुँच भूमिका-आधारित अनुमतियों द्वारा नियंत्रित की जाती है।
डेटा नामांकन की अवधि और स्कूल छोड़ने के एक शैक्षणिक वर्ष बाद तक बनाए रखा जाता है।

━━━━━━━━━━━━━━━━━━━━━━━━
संपर्क / शिकायत
━━━━━━━━━━━━━━━━━━━━━━━━
प्रश्नों, शिकायतों या अपने अधिकारों का उपयोग करने के लिए स्कूल प्रशासन से संपर्क करें।
शिकायत का समाधान 30 दिनों के भीतर किया जाना चाहिए।

इस सहमति को पूरा करके, आप पुष्टि करते हैं कि आपने यह सूचना पढ़ी और समझी है,
और वर्णित अनुसार अपने बच्चे के डेटा के प्रसंस्करण के लिए सहमति देते हैं।
''';

// ── Helper ────────────────────────────────────────────────────────────────────

String privacyNoticeBody(String langCode) =>
    langCode == 'hi' ? kPrivacyNoticeBodyHi : kPrivacyNoticeBodyEn;
