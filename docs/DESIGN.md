# DESIGN — Colors, Fonts, Rules

## Color Palette (by section)

| Section | Primary | Use |
|---------|---------|-----|
| Coordinator Dashboard | `Colors.indigo` | AppBar, tiles |
| Timetable Editor | `Colors.indigo` | AppBar, grid header |
| Teacher Management | `Colors.teal` (list) / `Colors.indigo` (mgmt) | AppBar |
| Attendance | `Colors.red` | AppBar, strip, FAB |
| Student List | `Colors.teal` | AppBar, search bar |
| Student Profile | `Colors.teal` | AppBar, header |
| Teacher Home | `Colors.red` | AppBar |
| My Timetable | `Colors.indigo` | AppBar, header |

## Teacher / Timetable Color Palette (cycled by index)

```dart
static const _palette = [
  Color(0xFF009688), // teal
  Color(0xFF3F51B5), // indigo
  Color(0xFFFF9800), // orange
  Color(0xFFE91E63), // pink
  Color(0xFF9C27B0), // purple
  Color(0xFF4CAF50), // green
  Color(0xFFF44336), // red
  Color(0xFF795548), // brown
  Color(0xFF00BCD4), // cyan
  Color(0xFF673AB7), // deep purple
];
```

## Attendance Status Colors

| Status | Color |
|--------|-------|
| Present | `Colors.green` |
| Leave | `Colors.orange` |
| Absent | `Colors.red` |

## Fee Status Colors

| Status | Color |
|--------|-------|
| Paid | `Colors.green` |
| Partial | `Colors.orange` |
| Pending | `Colors.red` |

---

## Typography

- App uses default **Material / Roboto** font (no custom font declared)
- AppBar titles: `fontSize: 17–18, fontWeight: bold`
- AppBar subtitles: `fontSize: 12, color: Colors.white70`
- Section headers: `fontSize: 11–12, fontWeight: w600–w700, letterSpacing: 0.8, color: grey.shade500`
- Body labels: `fontSize: 15, fontWeight: w500–w600`
- Captions / metadata: `fontSize: 11–13, color: grey.shade500`

---

## Layout Rules

- **Background**: `Colors.white` on all body screens
- **Scaffold bg**: always `Colors.white`
- **Dividers**: `Divider(height: 1, indent: 70–80)` between list items
- **Cards / tiles**: no `Card` widget — use `InkWell` + `Padding` directly (WhatsApp-inspired flat list style)
- **Border radius**: 8–12px for chips/buttons, 20px for pill chips, 10px for text fields
- **Elevation**: `AppBar(elevation: 0)` everywhere (flat, no shadow)
- **Bottom sheet handle**: 40×4px grey.shade300 rounded container, 8px vertical margin

## Spacing

- List tile padding: `EdgeInsets.symmetric(horizontal: 16, vertical: 10–13)`
- Section header padding: `EdgeInsets.fromLTRB(16, 14–20, 16, 4)`
- FAB: `FloatingActionButton.extended` for primary actions

## Chips / Badges

```dart
// Section header
Text(title, style: TextStyle(fontSize: 11, fontWeight: w700,
    color: grey.shade500, letterSpacing: 0.8))

// Status pill (fee, attendance)
Container(
  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(
    color: color.withOpacity(0.1),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: color.withOpacity(0.4)),
  ),
)
```

## Grid (Timetable)

- Corner header: `Colors.indigo.shade800`
- Column headers: `Colors.indigo.shade700`
- Even rows: `Colors.indigo.shade50`
- Odd rows: `Colors.white`
- Cell with teacher: `color.withOpacity(0.14)` bg, `color.withOpacity(0.35)` border
- Empty cell: grey.shade50/white bg, grey.shade200 border

## Icons — Key Usage

| Action | Icon |
|--------|------|
| Save / confirm | `Icons.check` |
| Mark all present | `Icons.done_all` |
| Edit | `Icons.edit_outlined` |
| Delete / remove | `Icons.delete_outline` |
| Add person | `Icons.person_add` |
| Call | `Icons.call` |
| WhatsApp / message | `Icons.chat_outlined` |
| Refresh | `Icons.refresh` |
| Switch role | `Icons.switch_account_outlined` |
| Timetable | `Icons.calendar_month_outlined` |
| Attendance | `Icons.fact_check_outlined` |
| Students | `Icons.people_outline` |
