import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';

enum AuthStatus { idle, loading, authenticated, error }

class AuthProvider extends ChangeNotifier {
  final AuthService _service = AuthService();

  AppUser? _user;
  AuthStatus _status = AuthStatus.idle;
  String? _errorMessage;

  AppUser? get user => _user;
  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  Future<void> signIn(String email, String password) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      _user = await _service.signInWithEmail(email, password);
      _status = AuthStatus.authenticated;
      // Feature 4: Init notifications and save FCM token after login.
      NotificationService.init(_user?.uid).catchError((_) {});
    } catch (e) {
      _user = null;
      _status = AuthStatus.error;
      _errorMessage = _friendlyError(e);
    }

    notifyListeners();
  }

  Future<void> signOut() async {
    await _service.signOut();
    _user = null;
    _status = AuthStatus.idle;
    notifyListeners();
  }

  String _friendlyError(Object e) {
    final msg = e.toString();
    if (msg.contains('user-not-found') ||
        msg.contains('wrong-password') ||
        msg.contains('invalid-credential')) {
      return 'Invalid email or password.';
    }
    if (msg.contains('too-many-requests')) {
      return 'Too many attempts. Please try again later.';
    }
    if (msg.contains('network-request-failed')) {
      return 'No internet connection.';
    }
    if (msg.contains('User record not found')) {
      return 'Account exists but has no school profile. Contact your admin.';
    }
    return 'Sign-in failed. Please try again.';
  }
}
