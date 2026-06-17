import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:school_app/firebase_options.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Diagnose Roll 1', () async {
    print('━━━ Roll 1 Diagnostic (Test) START ━━━');
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
      final db = FirebaseFirestore.instance;

      print('🔍 Fetching all schools...');
      final schoolsSnap = await db.collection('schools').get();
      print('Found ${schoolsSnap.docs.length} schools.');

      for (final schoolDoc in schoolsSnap.docs) {
        final schoolId = schoolDoc.id;
        print('\nSchool ID: $schoolId');

        final studentsSnap = await db.collection('schools').doc(schoolId).collection('students').get();
        print('Total student documents: ${studentsSnap.docs.length}');

        for (final doc in studentsSnap.docs) {
          final data = doc.data();
          final roll = data['roll'];
          final name = data['name'];

          if (roll == 1 || roll == '1' || doc.id.contains('_1') || doc.id.endsWith('_1')) {
            print('  🔴 FOUND STUDENT WITH ROLL 1 (or matching ID):');
            print('     Doc ID: ${doc.id}');
            print('     Name: $name');
            print('     Class: ${data['className']}, Section: ${data['section']}');
            print('     Roll: $roll');
            print('     deletionPending: ${data['deletionPending']}');
            print('     promoted: ${data['promoted']}');
            print('     Full Data: $data');

            final consentsSnap = await doc.reference.collection('consents').get();
            print('     Consents count: ${consentsSnap.docs.length}');
            for (final cDoc in consentsSnap.docs) {
              print('       • Consent Doc ID: ${cDoc.id} => ${cDoc.data()}');
            }
          }
        }
      }
    } catch (e, st) {
      print('❌ ERROR: $e\n$st');
    }
    print('━━━ Roll 1 Diagnostic (Test) END ━━━');
  });
}
