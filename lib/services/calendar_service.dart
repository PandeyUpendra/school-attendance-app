import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/calendar_event.dart';

class CalendarService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  late final CollectionReference _eventsRef;
  late final DocumentReference _settingsRef;

  CalendarService() {
    _eventsRef = _db.collection('calendar_events');
    _settingsRef = _db.collection('settings').doc('calendar');
  }

  // Get calendar settings (including state and overrides)
  Stream<Map<String, dynamic>> getCalendarSettings() {
    return _settingsRef.snapshots().map((doc) => doc.data() as Map<String, dynamic>? ?? {});
  }

  // Set selected state
  Future<void> setSelectedState(String state) async {
    await _settingsRef.set({'selectedState': state}, SetOptions(merge: true));
  }

  // Update holiday override
  Future<void> updateOverride(String holidayKey, Map<String, dynamic> overrideData) async {
    await _settingsRef.set({
      'overrides': {
        holidayKey: overrideData
      }
    }, SetOptions(merge: true));
  }

  // Stream of custom school events
  Stream<List<CalendarEvent>> getCustomEvents() {
    return _eventsRef.snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        return CalendarEvent.fromMap(doc.data() as Map<String, dynamic>, doc.id);
      }).toList();
    });
  }

  Future<void> addEvent(CalendarEvent event) async {
    await _eventsRef.add(event.toMap());
  }

  Future<void> updateEvent(CalendarEvent event) async {
    await _eventsRef.doc(event.id).update(event.toMap());
  }

  Future<void> deleteEvent(String id) async {
    await _eventsRef.doc(id).delete();
  }

  // Helper to get all holidays (National + State + Custom)
  // For simplicity, we can define national and state holidays here or in a separate file.
  
  static Map<String, List<Map<String, dynamic>>> getNationalHolidays(int year) {
    return {
      'National': [
        {'title': 'Republic Day', 'month': 1, 'day': 26},
        {'title': 'Vasant Panchami', 'month': 2, 'day': 2}, // Added for testing
        {'title': 'Independence Day', 'month': 8, 'day': 15},
        {'title': 'Gandhi Jayanti', 'month': 10, 'day': 2},
        {'title': 'Christmas', 'month': 12, 'day': 25},
      ]
    };
  }

  static Map<String, List<Map<String, dynamic>>> getStateHolidays(String state, int year) {
    // Sample data for various Indian states
    final data = {
      'Maharashtra': [
        {'title': 'Maharashtra Day', 'month': 5, 'day': 1},
        {'title': 'Ganesh Chaturthi', 'month': 9, 'day': 19},
        {'title': 'Gudi Padwa', 'month': 3, 'day': 22},
        {'title': 'Shivaji Jayanti', 'month': 2, 'day': 19}, // Added for testing
      ],
      'Delhi': [
        {'title': 'Statehood Day', 'month': 1, 'day': 25},
        {'title': 'Maha Shivratri', 'month': 2, 'day': 18},
      ],
      'Uttar Pradesh': [
        {'title': 'Ambedkar Jayanti', 'month': 4, 'day': 14},
        {'title': 'Ram Navami', 'month': 3, 'day': 30},
        {'title': 'Ravidas Jayanti', 'month': 2, 'day': 5}, // Added for testing
      ],
      'Karnataka': [
        {'title': 'Karnataka Rajyotsava', 'month': 11, 'day': 1},
        {'title': 'Ugadi', 'month': 3, 'day': 22},
      ],
      'Tamil Nadu': [
        {'title': 'Pongal', 'month': 1, 'day': 15},
        {'title': 'Tamil New Year', 'month': 4, 'day': 14},
      ],
      'West Bengal': [
        {'title': 'Poila Baisakh', 'month': 4, 'day': 15},
        {'title': 'Durga Puja', 'month': 10, 'day': 20},
        {'title': 'Saraswati Puja', 'month': 2, 'day': 14}, // Added for testing
      ],
      'Punjab': [
        {'title': 'Vaisakhi', 'month': 4, 'day': 14},
        {'title': 'Guru Nanak Jayanti', 'month': 11, 'day': 27},
      ],
      'Gujarat': [
        {'title': 'Gujarat Day', 'month': 5, 'day': 1},
        {'title': 'Navratri', 'month': 10, 'day': 15},
      ],
      'Rajasthan': [
        {'title': 'Rajasthan Day', 'month': 3, 'day': 30},
        {'title': 'Teej', 'month': 8, 'day': 19},
      ],
    };
    return {state: data[state] ?? []};
  }
}
