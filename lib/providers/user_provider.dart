import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import '../services/firebase_service.dart';

class UserProvider extends ChangeNotifier {
  final _svc = FirebaseService.instance;

  UserModel? _user;
  bool    _loading = false;
  String? _error;

  // FIX: main.dart previously routed straight to LoginScreen the instant
  // the widget tree built, because the Firebase auth listener resolves
  // asynchronously — LoginScreen was effectively acting as the splash
  // screen. authResolved starts false and flips true the moment the
  // FIRST auth-state event (null or a user) has been received, so
  // main.dart can show a real SplashScreen until then.
  bool _authResolved = false;
  bool get authResolved => _authResolved;

  UserModel? get user       => _user;
  bool       get isLoading  => _loading;
  String?    get error      => _error;

  bool get isLoggedIn => _user != null;
  bool get isAccountDisabled => _user?.isDisabled ?? false;

  UserProvider() {
    _svc.authState.listen(_onAuthChanged);
  }

  Future<void> _onAuthChanged(User? fbUser) async {
    if (fbUser == null) {
      _user = null;
      _authResolved = true;
      notifyListeners();
      return;
    }

    UserModel? profile = await _svc.getUser(fbUser.uid);
    if (profile == null) {
      profile = UserModel(
        id: fbUser.uid,
        name: fbUser.displayName ?? fbUser.email?.split('@').first ?? 'User',
        email: fbUser.email ?? '',
        campus: 'Bloemfontein Campus',
        photoUrl: fbUser.photoURL,
        createdAt: DateTime.now(),
      );
      await _svc.saveUser(profile);
    }

    _user = profile;
    _authResolved = true;
    notifyListeners();

    if (!profile.isDisabled) {
      await _svc.setOnline(fbUser.uid, true);
    }

    _svc.userStream(fbUser.uid).listen((fresh) {
      if (fresh == null) return;
      final wasEnabled = !(_user?.isDisabled ?? false);
      _user = fresh;
      notifyListeners();
      if (wasEnabled && fresh.isDisabled) {
        signOut();
      }
    });
  }

  Future<String?> signIn(String email, String password) async {
    _busy(true);
    try {
      await _svc.signIn(email, password);
      return null;
    } on FirebaseAuthException catch (e) {
      return _msg(e.code);
    } catch (e) {
      return e.toString();
    } finally {
      _busy(false);
    }
  }

  Future<String?> signUp({
    required String email, required String password,
    required String name, required String campus,
  }) async {
    _busy(true);
    try {
      final uid = await _svc.signUp(email, password);
      final u = UserModel(id: uid, name: name.trim(), email: email.trim(),
          campus: campus, createdAt: DateTime.now());
      await _svc.saveUser(u);
      _user = u;
      notifyListeners();
      return null;
    } on FirebaseAuthException catch (e) {
      return _msg(e.code);
    } catch (e) {
      return e.toString();
    } finally {
      _busy(false);
    }
  }

  Future<void> signOut() async {
    if (_user != null) await _svc.setOnline(_user!.id, false);
    await _svc.signOut();
    _user = null;
    notifyListeners();
  }

  Future<String?> sendPasswordReset(String email) async {
    try {
      await _svc.resetPassword(email);
      return null;
    } on FirebaseAuthException catch (e) {
      return _msg(e.code);
    }
  }

  Future<String?> updateProfile({String? name, String? campus, File? photoFile}) async {
    if (_user == null) return 'Not logged in';
    _busy(true);
    try {
      String? newPhotoUrl = _user!.photoUrl;
      if (photoFile != null) {
        newPhotoUrl = await _svc.uploadProfilePhoto(_user!.id, photoFile);
      }
      final updated = _user!.copyWith(
        name: (name?.trim().isNotEmpty == true) ? name!.trim() : _user!.name,
        campus: campus, photoUrl: newPhotoUrl,
      );
      await _svc.saveUser(updated);
      _user = updated;
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _busy(false);
    }
  }

  /// NEW: Facebook-style cover/background photo.
  Future<String?> updateCoverPhoto(File file) async {
    if (_user == null) return 'Not logged in';
    _busy(true);
    try {
      final url = await _svc.uploadCoverPhoto(_user!.id, file);
      _user = _user!.copyWith(coverPhotoUrl: url);
      notifyListeners();
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _busy(false);
    }
  }

  Future<void> reload() async {
    if (_user == null) return;
    final fresh = await _svc.getUser(_user!.id);
    if (fresh != null) { _user = fresh; notifyListeners(); }
  }

  Future<void> saveEmergencyContacts(List<EmergencyContact> contacts) async {
    if (_user == null) return;
    final updated = _user!.copyWith(emergencyContacts: contacts);
    await _svc.saveUser(updated);
    _user = updated;
    notifyListeners();
  }

  void _busy(bool v) { _loading = v; notifyListeners(); }

  String _msg(String code) {
    const m = {
      'user-not-found': 'No account found with this email.',
      'wrong-password': 'Incorrect password.',
      'invalid-credential': 'Invalid email or password.',
      'email-already-in-use': 'This email is already registered.',
      'weak-password': 'Password must be at least 6 characters.',
      'invalid-email': 'Please enter a valid email address.',
      'too-many-requests': 'Too many attempts. Try again later.',
      'network-request-failed': 'No internet connection.',
    };
    return m[code] ?? 'Something went wrong. Please try again.';
  }
}
