import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/syllabus.dart';
import 'auth_service.dart';
import 'base_firestore_service.dart';
import 'audit_log_service.dart';

class SyllabusService extends BaseFirestoreService {
  static final SyllabusService _instance = SyllabusService._();
  SyllabusService._();
  factory SyllabusService() => _instance;

  String get _sid => AuthService.currentSchoolId;

  CollectionReference<Map<String, dynamic>> get _templates =>
      schoolCollection(_sid, 'syllabus_templates');

  CollectionReference<Map<String, dynamic>> get _coverage =>
      schoolCollection(_sid, 'syllabus_coverage');

  // Normalization helper
  String _docId(String className, String subject) {
    final cleanClass = className.replaceAll(' ', '_');
    final cleanSub = subject.replaceAll(' ', '_');
    return '${cleanClass}_$cleanSub';
  }

  Future<SyllabusTemplate> getTemplate(String className, String subject) async {
    final id = _docId(className, subject);
    final doc = await _templates.doc(id).get();
    
    if (doc.exists && doc.data() != null) {
      return SyllabusTemplate.fromDoc(id, doc.data()!);
    }
    
    // Return a default seeded template if none exists in database
    return SyllabusTemplate(
      id: id,
      className: className,
      subject: subject,
      chapters: _getDefaultChapters(subject),
    );
  }

  Future<void> saveTemplate(SyllabusTemplate template) async {
    final id = _docId(template.className, template.subject);
    final data = template.toJson();
    await _templates.doc(id).set(data);

    AuditService.emit(
      action: 'save_template',
      entity: 'syllabus_template',
      entityId: id,
      after: data,
    );
  }

  Future<SyllabusCoverage> getCoverage(String className, String subject) async {
    final id = _docId(className, subject);
    final doc = await _coverage.doc(id).get();

    if (doc.exists && doc.data() != null) {
      return SyllabusCoverage.fromDoc(id, doc.data()!);
    }

    return SyllabusCoverage(
      id: id,
      className: className,
      subject: subject,
      completedChapterIds: [],
      lastUpdatedBy: '',
    );
  }

  Future<void> saveCoverage(SyllabusCoverage coverage) async {
    final id = _docId(coverage.className, coverage.subject);
    final data = coverage.toJson();
    await _coverage.doc(id).set(data);

    AuditService.emit(
      action: 'save_coverage',
      entity: 'syllabus_coverage',
      entityId: id,
      after: data,
    );
  }

  Stream<SyllabusCoverage> watchCoverage(String className, String subject) {
    final id = _docId(className, subject);
    return _coverage.doc(id).snapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        return SyllabusCoverage.fromDoc(id, doc.data()!);
      }
      return SyllabusCoverage(
        id: id,
        className: className,
        subject: subject,
        completedChapterIds: [],
        lastUpdatedBy: '',
      );
    });
  }

  Future<List<SyllabusCoverage>> getAllCoverage() async {
    final snap = await _coverage.get();
    return snap.docs
        .map((d) => SyllabusCoverage.fromDoc(d.id, d.data()))
        .toList();
  }

  List<SyllabusChapter> _getDefaultChapters(String subject) {
    switch (subject.toLowerCase()) {
      case 'mathematics':
      case 'math':
      case 'maths':
        return [
          SyllabusChapter(id: 'm1', name: 'Real Numbers', topics: ['Rational Numbers', 'Irrational Numbers', 'Decimal Representations']),
          SyllabusChapter(id: 'm2', name: 'Polynomials', topics: ['Linear Polynomials', 'Quadratic Polynomials', 'Factorisation']),
          SyllabusChapter(id: 'm3', name: 'Linear Equations', topics: ['Equations in Two Variables', 'Graphing Equations']),
          SyllabusChapter(id: 'm4', name: 'Quadratic Equations', topics: ['Roots', 'Solving by Factorisation', 'Quadratic Formula']),
          SyllabusChapter(id: 'm5', name: 'Arithmetic Progressions', topics: ['Arithmetic Sequences', 'Sum of N terms']),
          SyllabusChapter(id: 'm6', name: 'Triangles & Geometry', topics: ['Similar Triangles', 'Pythagoras Theorem']),
          SyllabusChapter(id: 'm7', name: 'Coordinate Geometry', topics: ['Distance Formula', 'Section Formula']),
          SyllabusChapter(id: 'm8', name: 'Trigonometry', topics: ['Trigonometric Ratios', 'Identities']),
          SyllabusChapter(id: 'm9', name: 'Statistics & Probability', topics: ['Mean, Median, Mode', 'Simple Probability']),
        ];
      case 'science':
      case 'physics':
      case 'chemistry':
      case 'biology':
        return [
          SyllabusChapter(id: 's1', name: 'Chemical Reactions', topics: ['Chemical Equations', 'Types of Reactions', 'Oxidation']),
          SyllabusChapter(id: 's2', name: 'Acids, Bases, and Salts', topics: ['PH Scale', 'Properties of Acids', 'Salts Preparation']),
          SyllabusChapter(id: 's3', name: 'Metals & Non-Metals', topics: ['Physical Properties', 'Chemical Properties', 'Metallurgy']),
          SyllabusChapter(id: 's4', name: 'Carbon and its Compounds', topics: ['Covalent Bonding', 'Saturated Hydrocarbons', 'Functional Groups']),
          SyllabusChapter(id: 's5', name: 'Life Processes', topics: ['Nutrition', 'Respiration', 'Transportation', 'Excretion']),
          SyllabusChapter(id: 's6', name: 'Control and Coordination', topics: ['Nervous System', 'Reflex Actions', 'Hormones in Animals']),
          SyllabusChapter(id: 's7', name: 'How do Organisms Reproduce?', topics: ['Asexual Reproduction', 'Sexual Reproduction']),
          SyllabusChapter(id: 's8', name: 'Light - Reflection & Refraction', topics: ['Spherical Mirrors', 'Refractive Index', 'Lens Formula']),
          SyllabusChapter(id: 's9', name: 'Electricity & Magnetism', topics: ['Ohms Law', 'Resistance', 'Magnetic Effects']),
        ];
      case 'english':
        return [
          SyllabusChapter(id: 'e1', name: 'Reading Comprehension', topics: ['Unseen Passages', 'Vocabulary Check']),
          SyllabusChapter(id: 'e2', name: 'Writing Skills', topics: ['Letter Writing', 'Paragraph Writing', 'Report Writing']),
          SyllabusChapter(id: 'e3', name: 'Grammar - Tenses & Verbs', topics: ['Active/Passive Voice', 'Subject-Verb Agreement']),
          SyllabusChapter(id: 'e4', name: 'Grammar - Direct & Indirect', topics: ['Reported Speech', 'Modals & Prepositions']),
          SyllabusChapter(id: 'e5', name: 'Literature - Drama', topics: ['Shakespearean Acts', 'Character Analysis']),
          SyllabusChapter(id: 'e6', name: 'Literature - Poetry', topics: ['Poetic Devices', 'Stanza Summaries']),
          SyllabusChapter(id: 'e7', name: 'Literature - Prose', topics: ['Short Stories', 'Themes & Moral Lessons']),
        ];
      default:
        return [
          SyllabusChapter(id: 'g1', name: 'Introduction & Basics', topics: ['Basic Concepts', 'Historical Context']),
          SyllabusChapter(id: 'g2', name: 'Core Principles', topics: ['Theories', 'Formulas', 'Key Guidelines']),
          SyllabusChapter(id: 'g3', name: 'Advanced Topics', topics: ['Applications', 'Case Studies']),
          SyllabusChapter(id: 'g4', name: 'Review & Assessment', topics: ['Revision Questions', 'Sample Papers']),
        ];
    }
  }
}
