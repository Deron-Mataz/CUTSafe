import 'package:flutter/material.dart';
import '../models/report_model.dart';
import '../services/firebase_service.dart';

/// Powers the Security "Reports" experience. Mirrors the subset of
/// CUTPulseAdmin.Controllers.ReportsController that is NOT restricted to
/// [Authorize(Policy = "AdministratorOnly")] — i.e. everything a Security
/// user is actually allowed to do:
///   • view reports + timeline
///   • change status / priority
///   • dismiss
///   • close the underlying incident (ActionCloseIncident)
///
/// Deliberately NOT implemented (backend-restricted to AdministratorOnly,
/// or explicitly marked internal-only):
///   • Assign / Unassign (administrator-only report assignment)
///   • ActionDeletePost / ActionDisableUser / ActionLockGroup (admin-only)
///   • AddNote / notes sub-collection (backend docs: "never exposed to
///     mobile users")
class ReportProvider extends ChangeNotifier {
  final _svc = FirebaseService.instance;

  List<ReportModel> _reports = [];
  bool _loading = false;
  String? _error;

  List<ReportModel> get reports => _reports;
  bool get isLoading => _loading;
  String? get error => _error;

  List<ReportModel> get pendingReview =>
      _reports.where((r) => r.statusEnum == ReportStatus.pendingReview).toList();
  List<ReportModel> get underInvestigation => _reports
      .where((r) => r.statusEnum == ReportStatus.underInvestigation)
      .toList();
  List<ReportModel> get resolved =>
      _reports.where((r) => r.statusEnum == ReportStatus.resolved).toList();
  List<ReportModel> get dismissed =>
      _reports.where((r) => r.statusEnum == ReportStatus.dismissed).toList();

  int get pendingCount => pendingReview.length;
  int get openCount => _reports.where((r) => r.isOpen).length;

  ReportProvider() {
    _svc.reportsStream().listen((list) {
      _reports = list;
      notifyListeners();
    }, onError: _onErr);
  }

  Stream<ReportModel?> reportStream(String id) => _svc.reportStream(id);
  Stream<List<ReportTimelineEvent>> timelineStream(String id) =>
      _svc.reportTimelineStream(id);

  Future<String?> updateStatus(String id, String status,
      {required String actorId, required String actorName}) async {
    try {
      await _svc.updateReportStatus(id, status,
          actorId: actorId, actorName: actorName);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> updatePriority(String id, String priority,
      {required String actorId, required String actorName}) async {
    try {
      await _svc.updateReportPriority(id, priority,
          actorId: actorId, actorName: actorName);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> dismiss(String id,
      {required String actorId, required String actorName}) async {
    try {
      await _svc.dismissReport(id, actorId: actorId, actorName: actorName);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> closeIncident(String reportId, String incidentId,
      {required String actorId, required String actorName}) async {
    try {
      await _svc.actionCloseIncidentForReport(reportId, incidentId,
          actorId: actorId, actorName: actorName);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  void _onErr(Object e) {
    _error = e.toString();
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
