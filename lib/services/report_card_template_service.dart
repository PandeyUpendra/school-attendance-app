import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/report_card_template.dart';
import '../data/template_seeds.dart';
import 'auth_service.dart';

/// CRUD service for report card templates.
///
/// Firestore path: schools/{sid}/report_card_templates/{templateId}
///
/// Rules:
///   • System presets (isSystemPreset == true) cannot be edited or deleted.
///     Clone them first with [cloneTemplate].
///   • [seedDefaultTemplates] is idempotent — safe to call on every app start;
///     it no-ops if presets already exist.
class ReportCardTemplateService {
  static final _db = FirebaseFirestore.instance;

  static final ReportCardTemplateService _instance =
      ReportCardTemplateService._();
  ReportCardTemplateService._();
  factory ReportCardTemplateService() => _instance;

  // ── Helpers ────────────────────────────────────────────────────────────────

  String get _sid => AuthService.currentSchoolId;

  CollectionReference _col(String schoolId) => _db
      .collection('schools')
      .doc(schoolId)
      .collection('report_card_templates');

  ReportCardTemplate _fromDoc(DocumentSnapshot d) =>
      ReportCardTemplate.fromDoc(
          d.id, Map<String, dynamic>.from(d.data() as Map));

  // ── Read ───────────────────────────────────────────────────────────────────

  Future<List<ReportCardTemplate>> getTemplates() async {
    final snap =
        await _col(_sid).orderBy('name').get();
    return snap.docs.map(_fromDoc).toList();
  }

  Stream<List<ReportCardTemplate>> watchTemplates() =>
      _col(_sid)
          .orderBy('name')
          .snapshots()
          .map((s) => s.docs.map(_fromDoc).toList());

  Future<ReportCardTemplate?> getTemplate(String templateId) async {
    final doc = await _col(_sid).doc(templateId).get();
    if (!doc.exists) return null;
    return _fromDoc(doc);
  }

  // ── Create ─────────────────────────────────────────────────────────────────

  Future<String> createTemplate(ReportCardTemplate template) async {
    final ref = await _col(_sid).add(template.toJson());
    return ref.id;
  }

  // ── Update ─────────────────────────────────────────────────────────────────

  /// Throws [StateError] if you attempt to update a system preset.
  Future<void> updateTemplate(ReportCardTemplate template) async {
    if (template.isSystemPreset) {
      throw StateError(
          'System presets cannot be edited directly. Clone first.');
    }
    await _col(_sid).doc(template.id).set(template.toJson());
  }

  // ── Delete ─────────────────────────────────────────────────────────────────

  /// Throws [StateError] if you attempt to delete a system preset.
  Future<void> deleteTemplate(String templateId) async {
    final t = await getTemplate(templateId);
    if (t == null) return;
    if (t.isSystemPreset) {
      throw StateError('System presets cannot be deleted.');
    }
    await _col(_sid).doc(templateId).delete();
  }

  // ── Clone ──────────────────────────────────────────────────────────────────

  /// Clones [source] into a new editable (non-preset) template.
  Future<ReportCardTemplate> cloneTemplate(ReportCardTemplate source) async {
    final clone = source.copyWith(
      id:             '',
      name:           'Copy of ${source.name}',
      isSystemPreset: false,
      createdAt:      DateTime.now(),
    );
    final newId = await createTemplate(clone);
    return clone.copyWith(id: newId);
  }

  // ── Seed defaults ──────────────────────────────────────────────────────────

  /// Seeds the 3 default system presets for [schoolId] if none exist yet.
  /// [brandName] is used as the headerText so no school name is hardcoded.
  /// Safe to call multiple times — idempotent.
  Future<void> seedDefaultTemplates({
    required String schoolId,
    required String brandName,
  }) async {
    final existing = await _col(schoolId).limit(1).get();
    if (existing.docs.isNotEmpty) return; // already seeded

    final batch = _db.batch();
    for (final seed in kTemplateSeedData) {
      final data = Map<String, dynamic>.from(seed);
      data['headerText'] = brandName;
      data['createdAt']  = Timestamp.fromDate(DateTime.now());
      batch.set(_col(schoolId).doc(), data);
    }
    await batch.commit();
  }
}
