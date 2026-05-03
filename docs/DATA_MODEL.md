# DATA MODEL

> Current storage: **SharedPreferences** (local/offline).
> Firestore structure below mirrors this for when cloud sync is added.

---

## SharedPreferences keys

| Key | Type | Description |
|-----|------|-------------|
| `tt_teachers` | JSON string | Array of Teacher objects |
| `tt_settings` | JSON string | Bell + class config |
| `tt_data` | JSON string | Full timetable grid |
| `students_list` | JSON string | Array of Student objects |
| `attendance_<class>_<YYYY-M-D>` | JSON string | Daily attendance map |

---

## Teacher

```json
{
  "id": "uuid-string",
  "name": "Ramesh Kumar",
  "subject": "Mathematics",
  "email": "ramesh@school.in",
  "phone": "9876543210",
  "isClassTeacher": true,
  "classTeacherOf": "Class 9",
  "section": "A"
}
```

**Firestore:** `schools/{schoolId}/teachers/{teacherId}`

---

## Settings

```json
{
  "numberOfBells": 8,
  "firstBellTime": "08:00",
  "classes": ["Class 6", "Class 7", "Class 8", "Class 9", "Class 10"],
  "bells": [
    { "duration": 45, "isLunch": false, "startMinutes": 480 },
    { "duration": 45, "isLunch": false, "startMinutes": 525 },
    { "duration": 30, "isLunch": true,  "startMinutes": 570 },
    { "duration": 45, "isLunch": false, "startMinutes": 600 }
  ]
}
```

- `startMinutes` = minutes from midnight (computed, not user-entered)
- `numberOfBells` = count of **non-lunch** bells only
- Lunch bell is inserted at any position; has its own duration

**Firestore:** `schools/{schoolId}/settings/timetable`

---

## Timetable

Shape: `className → day → bell(1-indexed int) → TimetableEntry`

```json
{
  "Class 9": {
    "Monday": {
      "1": { "teacherId": "uuid-1", "subject": null },
      "2": { "teacherId": "uuid-2", "subject": "English Grammar" }
    },
    "Wednesday": {
      "1": { "teacherId": "uuid-1", "subject": null }
    }
  }
}
```

- `subject: null` → use teacher's default subject
- `subject: "..."` → overrides teacher's default for this specific slot
- Bell index is 1-based; lunch bell has no index (skipped in numbering)

**Firestore:** `schools/{schoolId}/timetable/{className}/days/{day}/bells/{bellIndex}`

---

## Student

```json
{
  "roll": 12,
  "name": "Ananya Singh",
  "className": "Class 9",
  "fatherName": "Suresh Singh",
  "motherName": "Priya Singh",
  "phone": "9123456789",
  "photoPath": "/data/user/0/.../image.jpg",
  "feeStatus": "Paid"
}
```

- `feeStatus`: `"Paid"` | `"Pending"` | `"Partial"`
- `roll` is unique **within** a class
- `photoPath` is a local file path (device storage)

**Firestore:** `schools/{schoolId}/students/{roll_className}` (or auto-id)

---

## Attendance

Key: `attendance_Class 9_2026-4-19`

```json
{
  "12": "Present",
  "13": "Absent",
  "14": "Leave"
}
```

- Keys are roll numbers (strings)
- Values: `"Present"` | `"Absent"` | `"Leave"`
- One document per class per day
- Backward compat: old `true`/`false` bool values → `"Present"`/`"Absent"`

**Firestore:** `schools/{schoolId}/attendance/{className}_{date}/rolls/{roll}`
