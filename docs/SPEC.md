# SPEC — Full Feature List

Status: ✅ done | 🔲 pending | 🚧 partial

---

## Roles

| Feature | Status |
|---------|--------|
| Role selection screen (Coordinator / Teacher) | ✅ |
| Teacher: pick self from saved teacher list | ✅ |
| Coordinator: direct dashboard access | ✅ |
| Switch Role from any home screen | ✅ |
| PIN / password protection for Coordinator role | 🔲 |
| Google Sign-In (AuthService skeleton exists) | 🔲 |

---

## Coordinator Dashboard

| Feature | Status |
|---------|--------|
| Feature tile grid (all sections) | ✅ |
| Assign Duties screen | 🚧 (placeholder) |

---

## Teacher Management

| Feature | Status |
|---------|--------|
| List teachers | ✅ |
| Add teacher (name, subject, email, phone) | ✅ |
| Class Teacher toggle + section field (gated) | ✅ |
| Assign class to class teacher | ✅ |
| Edit teacher | ✅ |
| Delete teacher (+ remove from timetable) | ✅ |
| Teacher profile screen (view own details) | ✅ |

---

## Bell & Class Settings

| Feature | Status |
|---------|--------|
| Set number of bells | ✅ |
| Per-bell duration (Bell 1 propagates to all) | ✅ |
| First bell start time (12h picker) | ✅ |
| Auto-cascade start times | ✅ |
| Single lunch bell (insertable, own duration) | ✅ |
| Bell numbering skips lunch | ✅ |
| Class list: add / rename / delete | ✅ |

---

## Timetable

| Feature | Status |
|---------|--------|
| Editor grid (class × bell) | ✅ |
| Aggregated cell (no day selector on grid) | ✅ |
| Cell shows teacher avatar + name + subject + day dots | ✅ |
| Multi-day selection when assigning | ✅ |
| Custom subject per slot (overrides default) | ✅ |
| Clash detection (same teacher, same day+bell, different class) | ✅ |
| Clear slot (single bell, all days) | ✅ |
| Teacher view (My Timetable, read-only, day selector) | ✅ |
| Print / export timetable to PDF | 🔲 |
| Substitute teacher assignment | 🔲 |

---

## Attendance

| Feature | Status |
|---------|--------|
| Mark Present / Leave / Absent per student | ✅ |
| Mark All Present (one tap) | ✅ |
| Student photo in attendance list | ✅ |
| Save attendance with confirmation summary | ✅ |
| Attendance stored per class per day | ✅ |
| View past attendance records | 🔲 |
| Attendance report / export | 🔲 |
| Notify parents on absence | 🔲 |
| Monthly attendance summary per student | 🔲 |

---

## Students

| Feature | Status |
|---------|--------|
| Add student (roll, name, father, mother, phone, photo, fee) | ✅ |
| Edit student | ✅ |
| Delete student | ✅ |
| Student list with search | ✅ |
| Student profile page | ✅ |
| Direct call from profile | ✅ |
| WhatsApp from profile | ✅ |
| Fee status (Paid / Partial / Pending) | ✅ |
| Fee payment history | 🔲 |
| Fee due reminder / notification | 🔲 |
| Bulk import students (CSV) | 🔲 |
| Student ID card generation | 🔲 |
| Transfer / promote students to next class | 🔲 |

---

## Home Screens

| Feature | Status |
|---------|--------|
| Class teacher: Take Attendance direct (no picker) | ✅ |
| Class teacher: Student List direct (with edit rights) | ✅ |
| Regular teacher: Take Attendance via class picker | ✅ |
| Regular teacher: My Timetable | ✅ |
| Regular teacher: Student List via class picker (read-only) | ✅ |

---

## Notifications & Communication

| Feature | Status |
|---------|--------|
| Direct call to parent | ✅ |
| WhatsApp to parent | ✅ |
| In-app messaging / announcements | 🔲 |
| Push notifications (FCM) | 🔲 |

---

## Infrastructure

| Feature | Status |
|---------|--------|
| Local storage (SharedPreferences) | ✅ |
| Firestore cloud sync | 🔲 |
| Multi-school / multi-branch support | 🔲 |
| Offline-first with sync queue | 🔲 |
| Data backup / restore | 🔲 |
