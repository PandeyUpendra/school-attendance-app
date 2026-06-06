import 'package:cloud_firestore/cloud_firestore.dart';

import 'auth_service.dart';
import 'base_firestore_service.dart';

/// Per-school, user-manageable option lists for dropdown fields.
///
/// Every manageable dropdown in the app is identified by a stable [fieldKey]
/// (e.g. `'fee_mode'`, `'leave_type'`). The screen supplies a list of built-in
/// *seed* options; this service layers the school's customisations on top:
///
///   effective = (seeds − removed) ++ (added − removed)
///
/// Only the deltas are stored, so evolving the seed defaults in code still
/// reaches existing schools. Documents live at:
///
///   schools/{sid}/dropdown_options/{fieldKey}  →  { added: [...], removed: [...] }
///
/// A small in-memory cache avoids a round-trip per rebuild; it is invalidated
/// on every mutation.
class DropdownOptionsService extends BaseFirestoreService {
  static final DropdownOptionsService _instance = DropdownOptionsService._();
  DropdownOptionsService._();
  factory DropdownOptionsService() => _instance;

  // fieldKey → {added, removed}
  final Map<String, ({List<String> added, List<String> removed})> _cache = {};

  String get _sid => AuthService.currentSchoolId;

  CollectionReference _col() =>
      db.collection('schools').doc(_sid).collection('dropdown_options');

  Future<({List<String> added, List<String> removed})> _loadDeltas(
      String fieldKey) async {
    final cached = _cache[fieldKey];
    if (cached != null) return cached;
    try {
      final doc  = await _col().doc(fieldKey).get();
      final data = doc.data() as Map<String, dynamic>?;
      final deltas = (
        added:   _stringList(data?['added']),
        removed: _stringList(data?['removed']),
      );
      _cache[fieldKey] = deltas;
      return deltas;
    } catch (_) {
      // Offline / permission error — fall back to seeds only.
      return (added: <String>[], removed: <String>[]);
    }
  }

  static List<String> _stringList(dynamic raw) =>
      raw is List ? raw.map((e) => '$e').toList() : <String>[];

  /// Returns the effective option list: seeds with the school's removals taken
  /// out, followed by its custom additions (de-duplicated, order preserved).
  Future<List<String>> getOptions(
      String fieldKey, List<String> seeds) async {
    final d = await _loadDeltas(fieldKey);
    final removed = d.removed.toSet();
    final result = <String>[];
    final seen   = <String>{};
    for (final s in seeds) {
      if (removed.contains(s) || !seen.add(s)) continue;
      result.add(s);
    }
    for (final a in d.added) {
      if (removed.contains(a) || !seen.add(a)) continue;
      result.add(a);
    }
    return result;
  }

  /// Adds a custom option (no-op if it is already an effective seed/addition).
  Future<void> addOption(
      String fieldKey, String value, List<String> seeds) async {
    final v = value.trim();
    if (v.isEmpty) return;
    final d = await _loadDeltas(fieldKey);

    final added   = [...d.added];
    final removed = [...d.removed]..remove(v); // un-remove if it was hidden
    // Only track as an addition when it isn't already a built-in seed.
    if (!seeds.contains(v) && !added.contains(v)) added.add(v);

    await _persist(fieldKey, added: added, removed: removed);
  }

  /// Removes an option. Seeds are hidden via the `removed` list; custom
  /// additions are dropped from `added`.
  Future<void> removeOption(
      String fieldKey, String value, List<String> seeds) async {
    final v = value.trim();
    if (v.isEmpty) return;
    final d = await _loadDeltas(fieldKey);

    final added   = [...d.added]..remove(v);
    final removed = [...d.removed];
    if (seeds.contains(v) && !removed.contains(v)) removed.add(v);

    await _persist(fieldKey, added: added, removed: removed);
  }

  Future<void> _persist(String fieldKey,
      {required List<String> added, required List<String> removed}) async {
    _cache[fieldKey] = (added: added, removed: removed);
    await _col().doc(fieldKey).set({'added': added, 'removed': removed});
  }

  /// Clears the in-memory cache (e.g. on logout / school switch).
  void clearCache() => _cache.clear();
}
