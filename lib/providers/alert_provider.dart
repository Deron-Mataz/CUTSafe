import 'package:flutter/material.dart';
import '../models/alert_model.dart';
import '../models/group_model.dart';
import '../services/firebase_service.dart';

class AlertProvider extends ChangeNotifier {
  final _svc = FirebaseService.instance;

  List<AlertModel>  _alerts  = [];
  List<UpdateModel> _updates = [];
  bool    _loading = false;
  String? _error;

  final Set<String> _myReports  = {};
  final Set<String> _myConfirms = {};

  List<AlertModel>  get alerts    => _alerts;
  List<UpdateModel> get updates   => _updates;
  bool              get isLoading => _loading;
  String?           get error     => _error;

  List<AlertModel> get activeSOS =>
      _alerts.where((a) => a.isSOSActive).toList();

  bool hasReported (String id) => _myReports.contains(id);
  bool hasConfirmed(String id) => _myConfirms.contains(id);

  AlertProvider() {
    _svc.alertsStream().listen((list) {
      _alerts = list.map((a) => a.copyWith(
        isReported:  _myReports.contains(a.id),
        isConfirmed: _myConfirms.contains(a.id),
      )).toList();
      notifyListeners();
      _svc.deleteExpiredSOS();
    }, onError: _onErr);

    _svc.updatesStream().listen((list) {
      _updates = list;
      notifyListeners();
    }, onError: _onErr);
  }

  Future<String?> postAlert({
    required String userId,
    required String userName,
    String?         userPhotoUrl,
    required String title,
    required String description,
    String?         location,
    double?         latitude,
    double?         longitude,
    required AlertCategory category,
    List<String>    imageUrls = const [],
    String?         videoUrl,
  }) async {
    _busy(true);
    try {
      await _svc.postAlert(AlertModel(
        id: '', userId: userId, userName: userName, userPhotoUrl: userPhotoUrl,
        title: title, description: description, location: location,
        latitude: latitude, longitude: longitude, category: category,
        createdAt: DateTime.now(), imageUrls: imageUrls, videoUrl: videoUrl,
      ));
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _busy(false);
    }
  }

  Future<void> reportAlert(String id, String uid) async {
    _myReports.add(id);
    notifyListeners();
    try {
      await _svc.reportAlert(id, uid);
    } catch (e) {
      _myReports.remove(id);
      _onErr(e);
    }
  }

  Future<void> confirmAlert(String id, String uid) async {
    _myConfirms.add(id);
    notifyListeners();
    try {
      await _svc.confirmAlert(id, uid);
    } catch (e) {
      _myConfirms.remove(id);
      _onErr(e);
    }
  }

  Future<void> deleteAlert(String id) async {
    try { await _svc.deleteAlert(id); }
    catch (e) { _onErr(e); }
  }

  Future<String?> triggerSOS({
    required String uid,
    required String userName,
    String?         userPhotoUrl,
    required double latitude,
    required double longitude,
    required String address,
  }) async {
    _busy(true);
    try {
      final id = await _svc.triggerSOS(
        uid: uid, userName: userName, userPhotoUrl: userPhotoUrl,
        latitude: latitude, longitude: longitude, address: address,
      );
      return id;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    } finally {
      _busy(false);
    }
  }

  Future<void> markSOSSafe(String alertId) async {
    try { await _svc.markSOSSafe(alertId); }
    catch (e) { _onErr(e); }
  }

  // ── SECURITY EXTENSIONS ──────────────────────────────────────────
  // Mirrors backend SosController (CanRespondToSOS) and DispatchController
  // (Security may update their OWN assigned incident's dispatchStatus).
  // Kept on AlertProvider — not a separate provider — because these
  // actions operate on the exact same AlertModel/alerts stream the rest
  // of this provider already manages; splitting it out would just be
  // duplicated plumbing around the same data.

  /// Security marks an ACTIVE SOS as being responded to.
  Future<String?> markSOSResponding(String alertId, String responderName) async {
    try { await _svc.markSOSResponding(alertId, responderName); return null; }
    catch (e) { return e.toString(); }
  }

  /// Security closes out an SOS that has already been marked SAFE.
  Future<String?> resolveSOS(String alertId) async {
    try { await _svc.resolveSOS(alertId); return null; }
    catch (e) { return e.toString(); }
  }

  /// dispatchStatus: 'assigned' | 'accepted' | 'completed'. Only valid for
  /// an incident already assigned to the calling officer — enforcement of
  /// "own incidents only" mirrors DispatchController.UpdateStatus and is
  /// additionally checked by Firestore rules server-side.
  Future<String?> updateDispatchStatus(String alertId, String dispatchStatus) async {
    try { await _svc.updateDispatchStatus(alertId, dispatchStatus); return null; }
    catch (e) { return e.toString(); }
  }

  /// Mirrors IncidentsController.UpdateStatus (CanUpdateIncidents).
  Future<String?> updateIncidentStatus(String alertId, String status) async {
    try { await _svc.updateIncidentStatus(alertId, status); return null; }
    catch (e) { return e.toString(); }
  }

  Future<String?> postUpdate({
    required String userId,
    required String userName,
    String?         userPhotoUrl,
    required String content,
    String?         location,
    List<String>    imageUrls = const [],
    String?         videoUrl,
  }) async {
    _busy(true);
    try {
      await _svc.postUpdate(UpdateModel(
        id: '', userId: userId, userName: userName, userPhotoUrl: userPhotoUrl,
        content: content, location: location, createdAt: DateTime.now(),
        imageUrls: imageUrls, videoUrl: videoUrl,
      ));
      return null;
    } catch (e) {
      return e.toString();
    } finally {
      _busy(false);
    }
  }

  Future<void> deleteUpdate(String id) async {
    try { await _svc.deleteUpdate(id); }
    catch (e) { _onErr(e); }
  }

  void _busy(bool v)    { _loading = v; notifyListeners(); }
  void _onErr(Object e) { _error = e.toString(); notifyListeners(); }
  void clearError()     { _error = null; notifyListeners(); }
}
