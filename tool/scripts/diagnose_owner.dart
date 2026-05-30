import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../lib/firebase_options.dart';

Future<void> main() async {
  print('━━━ Diagnostic START ━━━');
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    final db = FirebaseFirestore.instance;

    final docRef = db.collection('allowed_users').doc('mandvishal@gmail.com');
    final docSnap = await docRef.get();

    if (docSnap.exists) {
      print('🔍 FOUND existing document for mandvishal@gmail.com!');
      print('📄 Data: ${docSnap.data()}');
      
      print('🗑️ Deleting conflicting document...');
      await docRef.delete();
      print('✅ Deleted successfully!');
    } else {
      print('🔍 NO existing document for mandvishal@gmail.com.');
    }

    print('\n📄 List of all registered owners in allowed_users:');
    final ownersSnap = await db.collection('allowed_users').where('role', isEqualTo: 'owner').get();
    if (ownersSnap.docs.isEmpty) {
      print('  (No owners found)');
    } else {
      for (final doc in ownersSnap.docs) {
        print('  • ${doc.id} => ${doc.data()}');
      }
    }

  } catch (e, st) {
    print('❌ ERROR: $e\n$st');
  }
  print('━━━ Diagnostic END ━━━');
}
