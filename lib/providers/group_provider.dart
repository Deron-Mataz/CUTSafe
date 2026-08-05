import 'package:flutter/material.dart';
import '../models/group_model.dart';
import '../services/firebase_service.dart';

class GroupProvider extends ChangeNotifier {
  final _svc = FirebaseService.instance;

  List<GroupModel> _groups  = [];
  bool    _loading = false;
  String? _error;

  List<GroupModel> get groups    => _groups;
  bool             get isLoading => _loading;
  String?          get error     => _error;

  List<GroupModel> myGroups(String uid) =>
      _groups.where((g) => g.memberIds.contains(uid)).toList();

  /// Excludes groups the user is currently banned from — mirrors backend
  /// AdminGroupModel.BannedIds enforcement.
  List<GroupModel> discoverGroups(String uid) => _groups
      .where((g) => !g.memberIds.contains(uid) && !g.bannedIds.contains(uid))
      .toList();

  GroupProvider() {
    _svc.groupsStream().listen((list) {
      _groups = list;
      notifyListeners();
    }, onError: _onErr);
  }

  Future<String?> createGroup({
    required String    adminId,
    required String    adminName,
    required String    name,
    required String    description,
    required GroupType type,
  }) async {
    _busy(true);
    try {
      final id = await _svc.createGroup(GroupModel(
        id: '', name: name.trim(), description: description.trim(),
        adminId: adminId, adminName: adminName, type: type,
        memberIds: [adminId], createdAt: DateTime.now(),
      ));
      return id;
    } catch (e) {
      _onErr(e);
      return null;
    } finally {
      _busy(false);
    }
  }

  Future<String?> joinGroup(String gid, String uid) async {
    try { await _svc.joinGroup(gid, uid); return null; }
    catch (e) { return e.toString(); }
  }

  Future<String?> leaveGroup(String gid, String uid) async {
    try { await _svc.leaveGroup(gid, uid); return null; }
    catch (e) { return e.toString(); }
  }

  Future<String?> requestJoin(String gid, String uid, String name) async {
    try { await _svc.sendJoinRequest(gid, uid, name); return null; }
    catch (e) { return e.toString(); }
  }

  Future<String?> deleteGroup(String gid) async {
    try { await _svc.deleteGroup(gid); return null; }
    catch (e) { return e.toString(); }
  }

  /// Temporary removal — mirrors a lightweight version of admin-dashboard
  /// moderation. The user is removed from memberIds; rejoin flows through
  /// the normal join/join-request path afterward.
  Future<String?> timeoutUser(String gid, String uid) async {
    try { await _svc.removeUser(gid, uid); return null; }
    catch (e) { return e.toString(); }
  }

  /// Permanent removal — adds to bannedIds so the user cannot rejoin
  /// without an explicit admin approval, even for open groups.
  Future<String?> banUser(String gid, String uid) async {
    try { await _svc.banUser(gid, uid); return null; }
    catch (e) { return e.toString(); }
  }

  void _busy(bool v)    { _loading = v; notifyListeners(); }
  void _onErr(Object e) { _error = e.toString(); notifyListeners(); }
  void clearError()     { _error = null; notifyListeners(); }
}
