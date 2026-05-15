class RolePermissionService {
  static const _hierarchy = {
    'admin':        ['owner', 'ownerPrincipal'],
    'owner':        ['principal'],
    'ownerPrincipal': ['principal', 'coordinator'],
    'principal':    ['coordinator'],
    'coordinator':  ['teacher'],
    'teacher':      ['guardian'],
  };

  List<String> getAllowedToCreate(String myRole) =>
      _hierarchy[myRole] ?? const [];

  bool canCreate(String myRole, String targetRole) =>
      getAllowedToCreate(myRole).contains(targetRole);

  static String roleDisplayName(String role) {
    switch (role) {
      case 'owner':          return 'Owner';
      case 'ownerPrincipal': return 'Owner-Principal';
      case 'principal':      return 'Principal';
      case 'coordinator':    return 'Coordinator';
      case 'teacher':        return 'Teacher';
      case 'guardian':       return 'Guardian';
      case 'admin':          return 'Admin';
      default:               return role;
    }
  }
}
