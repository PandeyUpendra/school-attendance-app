# Architecture Guide

## Repository Pattern

### Why

`StudentService` (and similar services) previously mixed two concerns:

| Concern | Example |
|---|---|
| **Business logic** | Validate duplicate roll before adding a student |
| **Data access** | `_students.where('className', …).get()` |

The Repository pattern separates them: a thin **Repository** layer owns all Firestore calls; the **Service** layer owns orchestration and validation.

---

### Layers

```
┌─────────────────────────────────┐
│           UI Screens            │  lib/screens/
└────────────────┬────────────────┘
                 │ calls
┌────────────────▼────────────────┐
│          Service Layer          │  lib/services/
│                                 │
│  • Business-rule validation     │
│  • Multi-repo orchestration     │
│  • Cross-collection operations  │
└────────────────┬────────────────┘
                 │ delegates data access via abstract interface
┌────────────────▼────────────────┐
│        Repository Layer         │  lib/repositories/
│                                 │
│  • Intent-level methods         │
│    (fetchByClass, upsert, …)    │
│  • No business logic            │
│  • Swappable implementations    │
└────────────────┬────────────────┘
                 │ production         │ tests
┌───────────────▼──┐   ┌────────────▼──────────────┐
│  Firestore impl  │   │  In-memory fake (no Fiber) │
│  (cloud_firestore│   │  student_repository_fake   │
│   SDK)           │   └───────────────────────────-┘
└──────────────────┘
```

---

### File Conventions

| File | Purpose |
|---|---|
| `lib/repositories/{domain}_repository.dart` | Abstract interface + Firestore production implementation |
| `lib/repositories/{domain}_repository_fake.dart` | In-memory fake — used in unit tests only, no Firebase |

---

### Template: `StudentRepository`

#### Abstract interface (`student_repository.dart`)

```dart
abstract class StudentRepository {
  Future<List<Student>> fetchByClass(String className, String section,
      {String? teacherId});
  Future<Student?> fetchByRoll(String className, String section, int roll);
  Future<void> upsert(Student s);
  Future<void> delete(String id);
  Stream<List<Student>> watchByClass(String className, String section);
  // … see full file for remarks, deletion requests, etc.
}
```

**Rules for interface methods**

* Use *intent* words: `fetch`, `upsert`, `delete`, `watch` — not `get`, `set`, `query`, `snapshot`.
* Parameters describe the domain, not Firestore primitives.  Pass `className` and `roll`, not a `DocumentReference`.
* The `id` returned by any `fetch*` call is opaque to callers — it is the Firestore document ID, populated by the implementation, and is only used to pass back to `delete(id)`.

#### Firestore implementation (`student_repository.dart`)

* Lives in the **same file** as the abstract class (one import for callers).
* Reads `AuthService.currentSchoolId` lazily (dynamic getter), so mid-session school switches are transparent.
* Always sets `student.id = doc.id` when building Student objects from Firestore snapshots — this keeps `delete(student.id)` reliable regardless of what the document stores in its `'id'` field.

#### In-memory fake (`student_repository_fake.dart`)

* Implements the same interface with plain Dart maps — no Flutter, no Firebase.
* Exposes `seed([students])`, `clear()`, and `studentCount` as test utilities.
* Stream methods (`watchByClass`, `watchAll`) emit a single snapshot via `Stream.fromFuture` — sufficient for unit tests; swap in a `StreamController` if reactive behaviour is needed.

---

### Service Contract

A Service that has been migrated to use a Repository **must**:

1. Accept a `StudentRepository` (or other repo type) in the constructor.
2. Default to the Firestore implementation:
   ```dart
   factory StudentService([StudentRepository? repo]) {
     if (repo != null) return StudentService._(repo);
     return _instance ??= StudentService._(FirestoreStudentRepository());
   }
   ```
3. Keep all validation / orchestration in the Service — the Repository must remain logic-free.
4. Document any Firestore collections it still accesses directly (pre-migration debt).

---

### Writing Unit Tests

```dart
// No Firebase.initializeApp() needed!
final repo    = FakeStudentRepository();
final service = StudentService(repo);   // fresh non-singleton instance

repo.seed([Student(roll: 1, name: 'Alice', className: 'Class 6')]);

test('addStudent prevents duplicate rolls', () async {
  await service.addStudent(student: Student(roll: 1, name: 'Bob', className: 'Class 6'));
  final error = await service.addStudent(student: Student(roll: 1, name: 'Carol', className: 'Class 6'));
  expect(error, contains('already exists'));
});
```

See `test/student_service_test.dart` for the full test file (10 cases).

---

### Migration Roadmap

Apply the same pattern to each remaining service in separate PRs:

| PR | Service | Repository |
|---|---|---|
| ✅ Done | `StudentService` | `StudentRepository` |
| Next | `TimetableService` | `TimetableRepository` |
| Next | `FeeService` | `FeeRepository` |
| Next | `StudentService` (attendance methods) | `AttendanceRepository` |

Do **not** migrate all services at once — one per PR keeps diffs reviewable and allows targeted rollback.
