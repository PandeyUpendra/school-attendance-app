import 'package:flutter/material.dart';
import '../../theme.dart';

/// Shared helpers for the owner / owner-principal "Staff" directory pages, which
/// list every staff role (teacher, coordinator, principal, …) with their role
/// label and account status. Kept in one place so both owner home variants stay
/// in sync.

/// Sorts staff by role importance (principal → coordinator → teacher → other),
/// then alphabetically by name (falling back to email).
int staffByRoleThenName(Map<String, dynamic> a, Map<String, dynamic> b) {
  int rank(String r) {
    switch (r) {
      case 'principal':
      case 'ownerPrincipal': return 0;
      case 'coordinator':    return 1;
      case 'teacher':
      case 'subjectTeacher': return 2;
      default:               return 3;
    }
  }
  final ra = rank(a['role'] as String? ?? '');
  final rb = rank(b['role'] as String? ?? '');
  if (ra != rb) return ra.compareTo(rb);
  final na = (a['name'] as String? ?? '').isNotEmpty
      ? a['name'] as String : a['email'] as String? ?? '';
  final nb = (b['name'] as String? ?? '').isNotEmpty
      ? b['name'] as String : b['email'] as String? ?? '';
  return na.toLowerCase().compareTo(nb.toLowerCase());
}

/// Normalises the raw allowed_users status into 'active' | 'pending' | 'inactive'.
String staffStatusOf(Map<String, dynamic> u) {
  final s = (u['status'] as String? ?? 'active').toLowerCase();
  if (s == 'pending') return 'pending';
  if (s == 'disabled' || s == 'inactive') return 'inactive';
  return 'active';
}

String staffRoleLabel(String role) {
  switch (role) {
    case 'teacher':        return 'Teacher';
    case 'subjectTeacher': return 'Subject Teacher';
    case 'coordinator':    return 'Coordinator';
    case 'principal':      return 'Principal';
    case 'ownerPrincipal': return 'Owner-Principal';
    case 'owner':          return 'Owner';
    case 'admin':          return 'Admin';
    default:               return role.isEmpty ? 'Staff' : role;
  }
}

Color staffRoleColor(String role) {
  switch (role) {
    case 'principal':
    case 'ownerPrincipal': return AppTheme.accent;
    case 'coordinator':    return AppTheme.primaryMid;
    case 'owner':
    case 'admin':          return AppTheme.primaryDark;
    default:               return AppTheme.primary;
  }
}

Color staffStatusColor(String status) {
  switch (status) {
    case 'pending':  return AppTheme.warning;
    case 'inactive': return AppTheme.danger;
    default:         return AppTheme.success;
  }
}

/// Small coloured chip showing a staff member's role.
class StaffRolePill extends StatelessWidget {
  final String role;
  const StaffRolePill({super.key, required this.role});
  @override
  Widget build(BuildContext context) {
    final c = staffRoleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6)),
      child: Text(staffRoleLabel(role),
          style: TextStyle(
              fontSize: 9, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

/// Small coloured chip showing a staff member's account status.
class StaffStatusPill extends StatelessWidget {
  final String status; // 'active' | 'pending' | 'inactive'
  const StaffStatusPill({super.key, required this.status});
  @override
  Widget build(BuildContext context) {
    final c = staffStatusColor(status);
    final label =
        status.isEmpty ? 'Active' : status[0].toUpperCase() + status.substring(1);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: c.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: c)),
    );
  }
}
