import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/school_contact.dart';

class ContactService {
  static final _db = FirebaseFirestore.instance;
  static final _contacts = _db.collection('school_contacts');

  static final ContactService _instance = ContactService._();
  ContactService._();
  factory ContactService() => _instance;

  Stream<List<SchoolContact>> getContacts() {
    return _contacts.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return SchoolContact.fromJson(doc.data());
      }).toList();
    });
  }

  Future<void> saveContact(SchoolContact contact) async {
    await _contacts.doc(contact.id).set(contact.toJson());
  }

  Future<void> deleteContact(String id) async {
    await _contacts.doc(id).delete();
  }
}
