/// Helpers for normalising class names across the app (#101).
///
/// Class names entered or fetched from Firestore may have inconsistent casing,
/// spacing or separators (e.g. "class 9-A", "Class 9 - A", "9 A", "class_9_a").
/// All comparisons and Firestore document IDs should go through [ClassName] so
/// that mismatches between the attendance doc key, the timetable entry, and the
/// student record never produce phantom-absent problems.
abstract class ClassName {
  ClassName._();

  /// Normalises [raw] to the canonical display form used across the app.
  ///
  /// Rules:
  ///   - Trim surrounding whitespace.
  ///   - Replace underscores with spaces (Firestore keys → display).
  ///   - Collapse runs of whitespace to a single space.
  ///   - Title-case the first word only ("class" → "Class").
  ///   - Normalise the separator between class number and section:
  ///     "9 A" / "9-A" / "9 - A" → "9-A" (no spaces around dash when section ≤ 2 chars).
  ///
  /// Examples:
  ///   canonical("class 9-a")   → "Class 9-A"
  ///   canonical("class_9_a")   → "Class 9 A"
  ///   canonical("9 A")         → "9 A"
  ///   canonical("CLASS 9 - A") → "Class 9-A"
  ///   canonical("Class 10")    → "Class 10"
  static String canonical(String raw) {
    // 1. Basic cleanup
    var s = raw.trim().replaceAll('_', ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ');

    // 2. Title-case the leading "class" keyword if present
    if (s.toLowerCase().startsWith('class ')) {
      s = 'Class ${s.substring(6)}';
    }

    // 3. Normalise " - " or " -" or "- " between number and short section
    //    e.g. "9 - A" → "9-A", "9 A" stays "9 A" (no dash present).
    s = s.replaceAllMapped(
      RegExp(r'(\d)\s*-\s*([A-Za-z]{1,2})\b'),
      (m) => '${m[1]}-${m[2]!.toUpperCase()}',
    );

    // 4. Upper-case a lone trailing section letter after a space
    //    e.g. "Class 9 a" → "Class 9 A"
    s = s.replaceAllMapped(
      RegExp(r'(\d) ([A-Za-z]{1,2})$'),
      (m) => '${m[1]} ${m[2]!.toUpperCase()}',
    );

    return s;
  }

  /// Returns a Firestore-safe document-key representation of [name].
  ///
  /// Replaces spaces with underscores and converts to lowercase so that
  /// "Class 9-A" → "class_9-a" (consistent with the existing key pattern
  /// used by [TimetableService]).
  static String toFirestoreKey(String name) =>
      canonical(name).toLowerCase().replaceAll(' ', '_');

  /// Returns true when [a] and [b] refer to the same class after normalisation.
  static bool same(String a, String b) => canonical(a) == canonical(b);
}
