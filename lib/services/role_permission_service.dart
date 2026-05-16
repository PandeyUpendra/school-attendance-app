class RolePermissionService {
  static const _hierarchy = {
    'admin':       ['owner'],
    'owner':       ['principal'],
    'principal':   ['coordinator'],
    'coordinator': ['teacher'],
    'teacher':     ['guardian'],
  };

  List<String> getAllowedToCreate(String myRole) =>
      _hierarchy[myRole] ?? const [];

  bool canCreate(String myRole, String targetRole) =>
      getAllowedToCreate(myRole).contains(targetRole);

  static String roleDisplayName(String role) {
    switch (role) {
      case 'owner':       return 'Owner';
      case 'principal':   return 'Principal';
      case 'coordinator': return 'Coordinator';
      case 'teacher':     return 'Teacher';
      case 'guardian':    return 'Guardian';
      case 'admin':       return 'Admin';
      default:            return role;
    }
  }
}
