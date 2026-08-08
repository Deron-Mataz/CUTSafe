import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/user_model.dart';
import '../models/alert_model.dart';
import '../models/group_model.dart';
import '../models/settings_model.dart';
import '../models/connection_model.dart';
import '../models/report_model.dart';

class FirebaseService {
  FirebaseService._();
  static final FirebaseService instance = FirebaseService._();

  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _storage = FirebaseStorage.instance;

  CollectionReference<Map<String, dynamic>> get _users =>
      _db.collection('users');
  CollectionReference<Map<String, dynamic>> get _alerts =>
      _db.collection('alerts');
  CollectionReference<Map<String, dynamic>> get _groups =>
      _db.collection('groups');
  CollectionReference<Map<String, dynamic>> get _updates =>
      _db.collection('updates');
  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection('reports');
  CollectionReference<Map<String, dynamic>> get _announcements =>
      _db.collection('announcements');
  CollectionReference<Map<String, dynamic>> get _connections =>
      _db.collection('connectionRequests');
  DocumentReference<Map<String, dynamic>> get _settingsDoc =>
      _db.collection('settings').doc('platform');

  // ── AUTH ──────────────────────────────────────────────────────
  User? get firebaseUser => _auth.currentUser;
  String? get currentUid => _auth.currentUser?.uid;
  Stream<User?> get authState => _auth.authStateChanges();

  Future<String> signIn(String email, String password) async {
    final c = await _auth.signInWithEmailAndPassword(
        email: email.trim(), password: password);
    return c.user!.uid;
  }

  Future<String> signUp(String email, String password) async {
    final c = await _auth.createUserWithEmailAndPassword(
        email: email.trim(), password: password);
    return c.user!.uid;
  }

  Future<void> signOut() => _auth.signOut();
  Future<void> resetPassword(String e) =>
      _auth.sendPasswordResetEmail(email: e.trim());

  // ── USERS ─────────────────────────────────────────────────────
  Future<UserModel?> getUser(String uid) async {
    final doc = await _users.doc(uid).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserModel.fromMap(doc.id, doc.data()!);
  }

  Stream<UserModel?> userStream(String uid) =>
      _users.doc(uid).snapshots().map((d) => (d.exists && d.data() != null)
          ? UserModel.fromMap(d.id, d.data()!)
          : null);

  Future<List<UserModel>> getUsers(List<String> uids) async {
    if (uids.isEmpty) return [];
    final results = <UserModel>[];
    for (var i = 0; i < uids.length; i += 30) {
      final chunk =
          uids.sublist(i, (i + 30) > uids.length ? uids.length : i + 30);
      final snap =
          await _users.where(FieldPath.documentId, whereIn: chunk).get();
      results.addAll(snap.docs.map((d) => UserModel.fromMap(d.id, d.data())));
    }
    return results;
  }

  Future<void> saveUser(UserModel u) =>
      _users.doc(u.id).set(u.toMap(), SetOptions(merge: true));

  Future<String?> uploadProfilePhoto(String uid, File file) async {
    final ref = _storage.ref().child('profile_photos').child('$uid.jpg');
    final task =
        await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final rawUrl = await task.ref.getDownloadURL();
    // FIX: Firebase Storage returns the SAME download URL (same token)
    // every time you overwrite a file at the same path. CachedNetworkImage
    // (and any HTTP image cache) keys purely off the URL string, so it
    // kept serving the old cached bytes even though the file on the
    // server had actually changed — this is why re-uploading appeared to
    // "do nothing". Appending a changing cache-busting query param forces
    // every re-upload to be treated as a brand-new image.
    final url = '$rawUrl&v=${DateTime.now().millisecondsSinceEpoch}';
    await _users.doc(uid).update({'photoUrl': url});
    return url;
  }

  /// Facebook-style cover/background photo on the profile screen.
  Future<String?> uploadCoverPhoto(String uid, File file) async {
    final ref = _storage.ref().child('cover_photos').child('$uid.jpg');
    final task =
        await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final rawUrl = await task.ref.getDownloadURL();
    // FIX: same cache-busting issue as uploadProfilePhoto above — this
    // was the actual reason the cover photo appeared to never save; the
    // upload itself was succeeding, but the UI kept showing the cached
    // image for the unchanged URL.
    final url = '$rawUrl&v=${DateTime.now().millisecondsSinceEpoch}';
    await _users.doc(uid).set({'coverPhotoUrl': url}, SetOptions(merge: true));
    return url;
  }

  Future<void> broadcastSafeStatus(String uid, bool isSafe, String? message) =>
      _users.doc(uid).update({'isSafe': isSafe, 'safeMessage': message});

  // ── PRESENCE ──────────────────────────────────────────────────
  Future<void> setOnline(String uid, bool online) => _users.doc(uid).update({
        'isOnline': online,
        'lastSeen': DateTime.now().toIso8601String(),
        if (!online) 'availability': 'offline',
      });

  Future<void> heartbeat(String uid) => _users
      .doc(uid)
      .update({'isOnline': true, 'lastSeen': DateTime.now().toIso8601String()});

  // ── MEDIA UPLOADS ─────────────────────────────────────────────
  Future<String> uploadAlertImage(String alertId, int index, File file) async {
    final ref = _storage
        .ref()
        .child('alert_media')
        .child(alertId)
        .child('image_$index.jpg');
    final task =
        await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return task.ref.getDownloadURL();
  }

  Future<String> uploadAlertVideo(String alertId, File file) async {
    final ref =
        _storage.ref().child('alert_media').child(alertId).child('video.mp4');
    final task =
        await ref.putFile(file, SettableMetadata(contentType: 'video/mp4'));
    return task.ref.getDownloadURL();
  }

  Future<String> uploadChatImage(String gid, String msgId, File file) async {
    final ref =
        _storage.ref().child('chat_media').child(gid).child('${msgId}_img.jpg');
    final task =
        await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return task.ref.getDownloadURL();
  }

  Future<String> uploadChatVideo(String gid, String msgId, File file) async {
    final ref =
        _storage.ref().child('chat_media').child(gid).child('${msgId}_vid.mp4');
    final task =
        await ref.putFile(file, SettableMetadata(contentType: 'video/mp4'));
    return task.ref.getDownloadURL();
  }

  Future<String> uploadVoiceNote(String gid, String msgId, File file) async {
    final ref = _storage
        .ref()
        .child('chat_media')
        .child(gid)
        .child('${msgId}_voice.m4a');
    final task =
        await ref.putFile(file, SettableMetadata(contentType: 'audio/m4a'));
    return task.ref.getDownloadURL();
  }

  Future<String> uploadReportEvidence(
      String reportId, int index, File file) async {
    final ref = _storage
        .ref()
        .child('report_evidence')
        .child(reportId)
        .child('evidence_$index.jpg');
    final task =
        await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    return task.ref.getDownloadURL();
  }

  // ── ALERTS ────────────────────────────────────────────────────
  Stream<List<AlertModel>> alertsStream() =>
      _alerts.orderBy('createdAt', descending: true).snapshots().map((s) =>
          s.docs.map((d) => AlertModel.fromMap(d.id, d.data())).toList());

  // FIX: `.where('userId', ==).orderBy('createdAt')` needs a composite
  // index in Firestore (equality + orderBy on a different field always
  // does) — that's the "query requires an index" error, and it was
  // making the stream throw immediately after the first successful
  // snapshot in some cases. Dropped orderBy from the query and sort
  // client-side instead — no index needed at all.
  Stream<List<AlertModel>> userAlertsStream(String uid) =>
      _alerts.where('userId', isEqualTo: uid).snapshots().map((s) {
        final list =
            s.docs.map((d) => AlertModel.fromMap(d.id, d.data())).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  Stream<AlertModel?> alertStream(String id) =>
      _alerts.doc(id).snapshots().map((d) => (d.exists && d.data() != null)
          ? AlertModel.fromMap(d.id, d.data()!)
          : null);

  Future<String> postAlert(AlertModel a) async {
    final ref = await _alerts.add(a.toMap());
    return ref.id;
  }

  Future<void> updateAlertMedia(
          String id, List<String> imageUrls, String? videoUrl) =>
      _alerts.doc(id).update(
          {'imageUrls': imageUrls, if (videoUrl != null) 'videoUrl': videoUrl});

  Future<void> deleteAlert(String id) => _alerts.doc(id).delete();

  Future<void> reportAlert(String id, String uid) => _alerts.doc(id).update({
        'reportCount': FieldValue.increment(1),
        'reportedBy': FieldValue.arrayUnion([uid]),
      });

  Future<void> confirmAlert(String id, String uid) => _alerts.doc(id).update({
        'confirmCount': FieldValue.increment(1),
        'confirmedBy': FieldValue.arrayUnion([uid]),
      });

  // ── SOS ───────────────────────────────────────────────────────
  Future<String> triggerSOS({
    required String uid,
    required String userName,
    String? userPhotoUrl,
    required double latitude,
    required double longitude,
    required String address,
  }) async {
    final alert = AlertModel(
      id: '',
      userId: uid,
      userName: userName,
      userPhotoUrl: userPhotoUrl,
      title: '🚨 SOS — $userName needs help!',
      description: 'Emergency SOS triggered at $address. '
          'Please check on this person or contact security.',
      location: address,
      latitude: latitude,
      longitude: longitude,
      category: AlertCategory.sos,
      createdAt: DateTime.now(),
      isSOS: true,
      sosStatus: 'ACTIVE',
    );
    final ref = await _alerts.add(alert.toMap());
    return ref.id;
  }

  Future<void> updateSOSLocation(
          String alertId, double lat, double lng, String address) =>
      _alerts
          .doc(alertId)
          .update({'latitude': lat, 'longitude': lng, 'location': address});

  Future<void> markSOSSafe(String alertId) => _alerts.doc(alertId).update({
        'sosStatus': 'SAFE',
        'safeAt': DateTime.now().toIso8601String(),
      });

  Future<void> deleteExpiredSOS() async {
    final cutoff = DateTime.now().subtract(const Duration(hours: 24));
    final snap = await _alerts
        .where('isSOS', isEqualTo: true)
        .where('sosStatus', whereIn: ['SAFE', 'RESOLVED']).get();
    for (final doc in snap.docs) {
      final safeAt = DateTime.tryParse((doc.data()['safeAt'] as String?) ?? '');
      if (safeAt != null && safeAt.isBefore(cutoff))
        await doc.reference.delete();
    }
  }

  // ── UPDATES ──────────────────────────────────────────────────
  Stream<List<UpdateModel>> updatesStream() =>
      _updates.orderBy('createdAt', descending: true).snapshots().map((s) =>
          s.docs.map((d) => UpdateModel.fromMap(d.id, d.data())).toList());

  Stream<List<UpdateModel>> userUpdatesStream(String uid) =>
      _updates.where('userId', isEqualTo: uid).snapshots().map((s) {
        final list =
            s.docs.map((d) => UpdateModel.fromMap(d.id, d.data())).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  Future<String> postUpdate(UpdateModel u) async =>
      (await _updates.add(u.toMap())).id;

  Future<void> updateUpdateMedia(
          String id, List<String> imageUrls, String? videoUrl) =>
      _updates.doc(id).update(
          {'imageUrls': imageUrls, if (videoUrl != null) 'videoUrl': videoUrl});

  Future<void> deleteUpdate(String id) => _updates.doc(id).delete();

  // ── GROUPS ───────────────────────────────────────────────────
  Stream<List<GroupModel>> groupsStream() =>
      _groups.orderBy('createdAt', descending: true).snapshots().map((s) =>
          s.docs.map((d) => GroupModel.fromMap(d.id, d.data())).toList());

  Stream<GroupModel?> groupStream(String gid) =>
      _groups.doc(gid).snapshots().map((d) => (d.exists && d.data() != null)
          ? GroupModel.fromMap(d.id, d.data()!)
          : null);

  Future<String> createGroup(GroupModel g) async =>
      (await _groups.add(g.toMap())).id;
  Future<void> deleteGroup(String gid) => _groups.doc(gid).delete();

  Future<void> joinGroup(String gid, String uid) => _groups.doc(gid).update({
        'memberIds': FieldValue.arrayUnion([uid])
      });
  Future<void> leaveGroup(String gid, String uid) => _groups.doc(gid).update({
        'memberIds': FieldValue.arrayRemove([uid])
      });
  Future<void> banUser(String gid, String uid) => _groups.doc(gid).update({
        'memberIds': FieldValue.arrayRemove([uid]),
        'bannedIds': FieldValue.arrayUnion([uid]),
      });
  Future<void> removeUser(String gid, String uid) => _groups.doc(gid).update({
        'memberIds': FieldValue.arrayRemove([uid])
      });

  Future<String?> uploadGroupCover(String gid, File file) async {
    final ref = _storage.ref().child('group_covers').child('$gid.jpg');
    final task =
        await ref.putFile(file, SettableMetadata(contentType: 'image/jpeg'));
    final url = await task.ref.getDownloadURL();
    await _groups.doc(gid).update({'coverUrl': url});
    return url;
  }

  // ── MESSAGES ─────────────────────────────────────────────────
  Stream<List<GroupMessage>> messagesStream(String gid) => _groups
      .doc(gid)
      .collection('messages')
      .orderBy('createdAt')
      .snapshots()
      .map((s) =>
          s.docs.map((d) => GroupMessage.fromMap(d.id, d.data())).toList());

  Future<String> sendMessage(GroupMessage m) async {
    final groupSnap = await _groups.doc(m.groupId).get();
    final data = groupSnap.data();
    final isLocked = data?['isLocked'] as bool? ?? false;
    if (isLocked) {
      throw Exception('This group has been locked by an administrator. '
          'New messages cannot be sent.');
    }

    final ref =
        await _groups.doc(m.groupId).collection('messages').add(m.toMap());

    // FIX: previously the group document was never updated when a message
    // was sent — latestMessage/latestMessageAt stayed null forever, which
    // broke the "last message" preview, chat-list sorting by recency, and
    // per-user unread badges on the groups screen (they all read these
    // fields, but nothing was ever writing them). This keeps them in sync.
    final memberIds = List<String>.from((data?['memberIds'] as List?) ?? []);
    final update = <String, dynamic>{
      'latestMessage': _latestMessagePreview(m),
      'latestSenderName': m.userName,
      'latestMessageAt': m.createdAt.toIso8601String(),
    };
    for (final memberId in memberIds) {
      if (memberId == m.userId) continue; // sender doesn't badge themselves
      update['unreadCounts.$memberId'] = FieldValue.increment(1);
    }
    await _groups.doc(m.groupId).update(update);

    return ref.id;
  }

  String _latestMessagePreview(GroupMessage m) {
    switch (m.messageType) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.voice:
        return '🎤 Voice message';
      case MessageType.location:
        return '📍 Location';
      case MessageType.text:
        return m.text;
    }
  }

  // Resets the unread count for ONE user only — per-user, so one member
  // opening the chat never affects anyone else's unread badge.
  Future<void> markGroupRead(String gid, String uid) =>
      _groups.doc(gid).update({'unreadCounts.$uid': 0});

  Future<void> updateMessageMedia(String gid, String msgId, String mediaUrl,
          {String? mediaThumbnail, int? mediaDuration}) =>
      _groups.doc(gid).collection('messages').doc(msgId).update({
        'mediaUrl': mediaUrl,
        if (mediaThumbnail != null) 'mediaThumbnail': mediaThumbnail,
        if (mediaDuration != null) 'mediaDuration': mediaDuration,
      });

  // ── JOIN REQUESTS ─────────────────────────────────────────────
  Future<void> sendJoinRequest(String gid, String uid, String name) =>
      _groups.doc(gid).collection('joinRequests').doc(uid).set({
        'uid': uid,
        'userName': name,
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
      });

  Stream<List<Map<String, dynamic>>> joinRequestsStream(String gid) => _groups
      .doc(gid)
      .collection('joinRequests')
      .where('status', isEqualTo: 'pending')
      .snapshots()
      .map((s) => s.docs.map((d) => d.data()).toList());

  Future<void> approveRequest(String gid, String uid) async {
    await joinGroup(gid, uid);
    await _groups
        .doc(gid)
        .collection('joinRequests')
        .doc(uid)
        .update({'status': 'approved'});
  }

  Future<void> declineRequest(String gid, String uid) => _groups
      .doc(gid)
      .collection('joinRequests')
      .doc(uid)
      .update({'status': 'declined'});

  // ── REPORTS ────────────────────────────────────────────────────
  Future<String> submitReport({
    required String itemType,
    required String itemId,
    required String itemName,
    required String reportedById,
    required String reportedByName,
    required String reason,
    String description = '',
    List<String> evidenceUrls = const [],
  }) async {
    final now = DateTime.now().toIso8601String();
    final ref = await _reports.add({
      'itemType': itemType,
      'itemId': itemId,
      'itemName': itemName,
      'reportedById': reportedById,
      'reportedByName': reportedByName,
      'reason': reason,
      'description': description,
      'evidenceUrls': evidenceUrls,
      'status': 'pending_review',
      'priority': 'medium',
      'assignedToId': null,
      'assignedToName': null,
      'assignedAt': null,
      'createdAt': now,
      'updatedAt': now,
    });
    return ref.id;
  }

  // ── ANNOUNCEMENTS ─────────────────────────────────────────────
  Stream<List<Map<String, dynamic>>> activeAnnouncementsStream() =>
      _announcements
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  // ── SETTINGS ───────────────────────────────────────────────────
  Stream<PlatformSettings> settingsStream() =>
      _settingsDoc.snapshots().map((d) => d.exists && d.data() != null
          ? PlatformSettings.fromMap(d.data()!)
          : PlatformSettings.fallback);

  Future<PlatformSettings> getSettings() async {
    final d = await _settingsDoc.get();
    return d.exists && d.data() != null
        ? PlatformSettings.fromMap(d.data()!)
        : PlatformSettings.fallback;
  }

  // ── CONNECTIONS ────────────────────────────────────────────────
  // FIX: the original design wrote to BOTH users' `connections` arrays in
  // a single batch. That's impossible to allow safely in Firestore rules —
  // a client can only ever write to documents it owns, never another
  // user's profile doc. Redesigned so the connectionRequests collection is
  // the single source of truth: "connected" = an accepted request exists
  // between the two users. Every write here touches only the request doc,
  // and the request doc's own from/to fields make ownership checkable.
  String _reqId(String from, String to) => '${from}__$to';

  /// Sends a connection request. Doc id is directional so we can look up
  /// exactly who sent it. Also acts as the "notification" the recipient sees.
  Future<void> sendConnectionRequest({
    required String fromUid,
    required String fromName,
    String? fromPhotoUrl,
    required String toUid,
    required String toName,
    String? toPhotoUrl,
  }) =>
      _connections.doc(_reqId(fromUid, toUid)).set(ConnectionRequest(
            id: '',
            fromUid: fromUid,
            fromName: fromName,
            fromPhotoUrl: fromPhotoUrl,
            toUid: toUid,
            toName: toName,
            toPhotoUrl: toPhotoUrl,
            status: 'pending',
            createdAt: DateTime.now(),
          ).toMap());

  /// Cancels a request the current user sent (only works if still pending).
  Future<void> cancelConnectionRequest(String fromUid, String toUid) =>
      _connections.doc(_reqId(fromUid, toUid)).delete();

  /// Accept a request sent TO the current user. Only updates the single
  /// request document's status — the recipient (toUid) is the one calling
  /// this, and Firestore rules only need to check they own the `toUid`
  /// side of that one document.
  Future<void> acceptConnectionRequest(String fromUid, String toUid) =>
      _connections.doc(_reqId(fromUid, toUid)).update({'status': 'accepted'});

  Future<void> declineConnectionRequest(String fromUid, String toUid) =>
      _connections.doc(_reqId(fromUid, toUid)).update({'status': 'declined'});

  /// Removes an existing accepted connection between two users. Either
  /// side may call this — it deletes the one request doc that represents
  /// the friendship; no other user's document is touched.
  Future<void> removeConnection(String uidA, String uidB) async {
    final a = await _connections.doc(_reqId(uidA, uidB)).get();
    if (a.exists) {
      await a.reference.delete();
      return;
    }
    final b = await _connections.doc(_reqId(uidB, uidA)).get();
    if (b.exists) await b.reference.delete();
  }

  /// Checks the connection status between `me` and `other` by looking up
  /// both possible directional request docs.
  Future<ConnectionStatus> getConnectionStatus(String me, String other) async {
    final outgoing = await _connections.doc(_reqId(me, other)).get();
    if (outgoing.exists) {
      final status = outgoing.data()?['status'];
      if (status == 'accepted') return ConnectionStatus.connected;
      if (status == 'pending') return ConnectionStatus.pendingOutgoing;
    }
    final incoming = await _connections.doc(_reqId(other, me)).get();
    if (incoming.exists) {
      final status = incoming.data()?['status'];
      if (status == 'accepted') return ConnectionStatus.connected;
      if (status == 'pending') return ConnectionStatus.pendingIncoming;
    }
    return ConnectionStatus.none;
  }

  /// Live count of a user's accepted connections.
  // FIX: array-contains combined with a second equality filter on a
  // different field also needs a composite index in Firestore. Query
  // only on `participants` (single-field, no index needed) and filter
  // `status == accepted` client-side instead.
  Stream<int> connectionCountStream(String uid) => _connections
      .where('participants', arrayContains: uid)
      .snapshots()
      .map((s) => s.docs.where((d) => d.data()['status'] == 'accepted').length);

  /// NEW: live list of the "other side" uid for each accepted connection —
  /// backs the "who am I connected to" list screen.
  Stream<List<String>> connectionIdsStream(String uid) =>
      _connections.where('participants', arrayContains: uid).snapshots().map(
          (s) => s.docs.where((d) => d.data()['status'] == 'accepted').map((d) {
                final data = d.data();
                final from = data['fromUid'] as String? ?? '';
                final to = data['toUid'] as String? ?? '';
                return from == uid ? to : from;
              }).toList());

  /// Live stream of pending connection requests sent TO the current user —
  /// this is the data source for the Notifications screen.
  // FIX: two equality filters alone are fine (Firestore merges them
  // without an index), but adding orderBy on a third field forces a
  // composite index. Dropped orderBy, sorted client-side.
  Stream<List<ConnectionRequest>> incomingRequestsStream(String uid) =>
      _connections
          .where('toUid', isEqualTo: uid)
          .where('status', isEqualTo: 'pending')
          .snapshots()
          .map((s) {
        final list = s.docs
            .map((d) => ConnectionRequest.fromMap(d.id, d.data()))
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  /// Count of unread/pending incoming requests, for the app-bar badge.
  Stream<int> incomingRequestCountStream(String uid) =>
      incomingRequestsStream(uid).map((list) => list.length);

  // ════════════════════════════════════════════════════════════════════
  // SECURITY ROLE EXTENSIONS
  // Backed by the same Firestore collections the Admin Dashboard reads/
  // writes (CUTPulseAdmin.Controllers: Dispatch, Sos, Reports, Home, Map).
  // Every write below mirrors an action that controller already exposes
  // to the "AdminOrSecurity" policy — nothing here invents new backend
  // behaviour, it only reaches the same documents from the mobile client.
  // ════════════════════════════════════════════════════════════════════

  // ── USERS (directory / presence, mirrors UsersController + HomeController) ──

  /// All user docs — used to compute Security dashboard stats
  /// (online students/security) the same way HomeController.Index /
  /// DashboardStats does on the admin side.
  Stream<List<UserModel>> allUsersStream() => _users.snapshots().map(
      (s) => s.docs.map((d) => UserModel.fromMap(d.id, d.data())).toList());

  /// Security personnel directory — mirrors
  /// UsersController.Index's `SecurityPersonnel` list.
  Stream<List<UserModel>> securityPersonnelStream() => allUsersStream()
      .map((list) => list.where((u) => u.isSecurityRole).toList());

  /// Mirrors UsersController's `Availability` field, settable by the
  /// officer themselves (available|responding|busy|offline).
  Future<void> updateAvailability(String uid, String availability) =>
      _users.doc(uid).update({'availability': availability});

  // ── SOS RESPONSE (mirrors SosController — CanRespondToSOS, not admin-only) ──

  Future<void> markSOSResponding(String alertId, String responderName) =>
      _alerts.doc(alertId).update({
        'sosStatus': 'RESPONDING',
        'respondingBy': responderName,
      });

  /// Mirrors SosController.Resolve — used once an SOS has been marked
  /// SAFE and Security closes it out. Distinct from `markSOSSafe` (in
  /// AlertProvider/FirebaseService already), which is the "I'm safe"
  /// action available to the person who triggered the SOS.
  Future<void> resolveSOS(String alertId) =>
      _alerts.doc(alertId).update({'sosStatus': 'RESOLVED'});

  // ── DISPATCH (mirrors DispatchController.UpdateStatus — Security may only
  // update their OWN assigned incident; Assign/Unassign/SetPriority remain
  // AdministratorOnly on the backend and are intentionally NOT exposed here) ──

  Future<void> updateDispatchStatus(String alertId, String dispatchStatus) =>
      _alerts.doc(alertId).update({'dispatchStatus': dispatchStatus});

  // ── INCIDENTS (mirrors IncidentsController.UpdateStatus — CanUpdateIncidents) ──

  Future<void> updateIncidentStatus(String alertId, String status) =>
      _alerts.doc(alertId).update({'status': status});

  // ── REPORTS (mirrors ReportsController — non-AdministratorOnly actions only:
  // UpdateStatus, UpdatePriority, Dismiss, ActionCloseIncident. Assign/Unassign/
  // ActionDeletePost/ActionDisableUser/ActionLockGroup are AdministratorOnly on
  // the backend and are NOT implemented here. Report notes are explicitly
  // documented backend-side as "never exposed to mobile users" and are also
  // deliberately absent — only the append-only timeline is surfaced.) ──

  Stream<List<ReportModel>> reportsStream() =>
      _reports.orderBy('createdAt', descending: true).snapshots().map((s) =>
          s.docs.map((d) => ReportModel.fromMap(d.id, d.data())).toList());

  Stream<ReportModel?> reportStream(String id) =>
      _reports.doc(id).snapshots().map((d) => (d.exists && d.data() != null)
          ? ReportModel.fromMap(d.id, d.data()!)
          : null);

  Stream<List<ReportTimelineEvent>> reportTimelineStream(String id) => _reports
      .doc(id)
      .collection('timeline')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs
          .map((d) => ReportTimelineEvent.fromMap(d.id, d.data()))
          .toList());

  Future<void> _addReportTimelineEvent(
    String reportId, {
    required String actorId,
    required String actorName,
    required String event,
    String? detail,
  }) =>
      _reports.doc(reportId).collection('timeline').add(ReportTimelineEvent(
            id: '',
            actorId: actorId,
            actorName: actorName,
            event: event,
            detail: detail,
            createdAt: DateTime.now(),
          ).toMap());

  Future<void> updateReportStatus(
    String id,
    String status, {
    required String actorId,
    required String actorName,
  }) async {
    await _reports.doc(id).update({
      'status': status,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _addReportTimelineEvent(id,
        actorId: actorId,
        actorName: actorName,
        event: "Status changed to '${_statusDisplay(status)}'");
  }

  Future<void> updateReportPriority(
    String id,
    String priority, {
    required String actorId,
    required String actorName,
  }) async {
    await _reports.doc(id).update({
      'priority': priority,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _addReportTimelineEvent(id,
        actorId: actorId,
        actorName: actorName,
        event: "Priority changed to '$priority'");
  }

  Future<void> dismissReport(String id,
          {required String actorId, required String actorName}) =>
      updateReportStatus(id, 'dismissed',
          actorId: actorId, actorName: actorName);

  /// Mirrors ReportsController.ActionCloseIncident — closes the underlying
  /// incident AND resolves the report in one action.
  Future<void> actionCloseIncidentForReport(
    String reportId,
    String incidentId, {
    required String actorId,
    required String actorName,
  }) async {
    await updateIncidentStatus(incidentId, 'closed');
    await _reports.doc(reportId).update({
      'status': 'resolved',
      'updatedAt': DateTime.now().toIso8601String(),
    });
    await _addReportTimelineEvent(reportId,
        actorId: actorId,
        actorName: actorName,
        event: 'Incident closed — report resolved');
  }

  String _statusDisplay(String status) => switch (status) {
        'under_investigation' => 'Under Investigation',
        'resolved' => 'Resolved',
        'dismissed' => 'Dismissed',
        _ => 'Pending Review',
      };
}
