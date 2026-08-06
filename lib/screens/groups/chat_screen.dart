import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/group_provider.dart';
import '../../services/firebase_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/report_dialog.dart';
import '../../widgets/media_viewer.dart';
import '../profile/user_profile_screen.dart';
import 'join_requests_screen.dart';

/// Google Maps Static API key.
/// Supplied at build/run time via --dart-define, never hardcoded.
/// Example: flutter run --dart-define=MAPS_API_KEY=your_key_here
const String _mapsApiKey = String.fromEnvironment('MAPS_API_KEY');

const List<Color> _palette = [
  Color(0xFF1565C0),
  Color(0xFF2E7D32),
  Color(0xFF6A1B9A),
  Color(0xFF00838F),
  Color(0xFFBF360C),
  Color(0xFF37474F),
  Color(0xFF880E4F),
  Color(0xFF0277BD),
  Color(0xFF4A148C),
  Color(0xFF1B5E20),
];
Color _colorFor(String uid) {
  final h = uid.codeUnits.fold(0, (a, c) => a + c);
  return _palette[h % _palette.length];
}

_VoiceContentState? _activeVoiceNote;

const _locationDurations = [
  ('10 min', Duration(minutes: 10)),
  ('30 min', Duration(minutes: 30)),
  ('1 hour', Duration(hours: 1)),
  ('2 hours', Duration(hours: 2)),
  ('5 hours', Duration(hours: 5)),
  ('24 hours', Duration(hours: 24)),
];

class ChatScreen extends StatefulWidget {
  final GroupModel group;
  const ChatScreen({super.key, required this.group});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _ctrl = TextEditingController();
  final _scroll = ScrollController();
  bool _uploadingCover = false;
  bool _sendingMedia = false;

  // Voice recording state
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  int _recordSeconds = 0;
  Timer? _recordTimer;
  String? _recordPath;

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _recordTimer?.cancel();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final user = context.read<UserProvider>().user;
    if (user == null) return;
    _ctrl.clear();
    try {
      await FirebaseService.instance.sendMessage(GroupMessage(
        id: '',
        groupId: widget.group.id,
        userId: user.id,
        userName: user.name,
        userPhotoUrl: user.photoUrl,
        text: text,
        createdAt: DateTime.now(),
      ));
      _scrollBottom();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _showAttachMenu() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: AppTheme.cutBorder,
                        borderRadius: BorderRadius.circular(2)))),
            const Text('Share',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _AttachBtn(
                  icon: Icons.image_outlined,
                  label: 'Image',
                  color: AppTheme.cutBlue,
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage();
                  }),
              _AttachBtn(
                  icon: Icons.videocam_outlined,
                  label: 'Video',
                  color: Colors.deepOrange,
                  onTap: () {
                    Navigator.pop(context);
                    _pickVideo();
                  }),
              // FIX: voice note restored
              _AttachBtn(
                  icon: Icons.mic_outlined,
                  label: 'Voice',
                  color: Colors.purple,
                  onTap: () {
                    Navigator.pop(context);
                    _startVoiceRecording();
                  }),
              // FIX: location sharing restored (was a placeholder toast)
              _AttachBtn(
                  icon: Icons.location_on_outlined,
                  label: 'Location',
                  color: Colors.teal,
                  onTap: () {
                    Navigator.pop(context);
                    _shareLocation();
                  }),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  // ── Image ─────────────────────────────────────────────────────
  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    if (await file.length() > 5 * 1024 * 1024) {
      _showSnack('Image must be under 5 MB.', error: true);
      return;
    }
    final user = context.read<UserProvider>().user;
    if (user == null) return;
    setState(() => _sendingMedia = true);
    try {
      final msgId = await FirebaseService.instance.sendMessage(GroupMessage(
        id: '',
        groupId: widget.group.id,
        userId: user.id,
        userName: user.name,
        userPhotoUrl: user.photoUrl,
        text: '',
        messageType: MessageType.image,
        createdAt: DateTime.now(),
      ));
      final url = await FirebaseService.instance
          .uploadChatImage(widget.group.id, msgId, file);
      await FirebaseService.instance
          .updateMessageMedia(widget.group.id, msgId, url);
      _scrollBottom();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  // ── Video (max 30s) ──────────────────────────────────────────
  Future<void> _pickVideo() async {
    final picked = await ImagePicker().pickVideo(
        source: ImageSource.gallery, maxDuration: const Duration(seconds: 30));
    if (picked == null || !mounted) return;
    final user = context.read<UserProvider>().user;
    if (user == null) return;
    setState(() => _sendingMedia = true);
    try {
      final msgId = await FirebaseService.instance.sendMessage(GroupMessage(
        id: '',
        groupId: widget.group.id,
        userId: user.id,
        userName: user.name,
        userPhotoUrl: user.photoUrl,
        text: '',
        messageType: MessageType.video,
        createdAt: DateTime.now(),
      ));
      final url = await FirebaseService.instance
          .uploadChatVideo(widget.group.id, msgId, File(picked.path));
      await FirebaseService.instance
          .updateMessageMedia(widget.group.id, msgId, url);
      _scrollBottom();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  // ── Voice note (max 90s) ─────────────────────────────────────
  Future<void> _startVoiceRecording() async {
    if (!await _recorder.hasPermission()) {
      _showSnack('Microphone permission is required to record voice notes.',
          error: true);
      return;
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    _recordPath = path;
    setState(() {
      _isRecording = true;
      _recordSeconds = 0;
    });

    _recordTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      setState(() => _recordSeconds++);
      if (_recordSeconds >= 90) {
        // 1min30s max
        _stopVoiceRecording(send: true);
      }
    });

    if (mounted) _showRecordingSheet();
  }

  void _showRecordingSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(builder: (ctx, setModal) {
        // Rebuild every second via the outer timer calling setState + this
        // sheet re-reading _recordSeconds through the closure.
        Timer.periodic(const Duration(milliseconds: 300), (t) {
          if (!_isRecording) {
            t.cancel();
            return;
          }
          if (ctx.mounted) setModal(() {});
        });
        return SafeArea(
            child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(
                    color: Colors.purple, shape: BoxShape.circle),
                child: const Icon(Icons.mic, color: Colors.white, size: 32)),
            const SizedBox(height: 12),
            Text('${_recordSeconds}s / 90s',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Recording voice note…',
                style: TextStyle(fontSize: 12, color: AppTheme.cutMuted)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _stopVoiceRecording(send: false);
                },
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.cutRed,
                    side: const BorderSide(color: AppTheme.cutRed)),
                child: const Text('Cancel'),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _stopVoiceRecording(send: true);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                child: const Text('Send'),
              )),
            ]),
          ]),
        ));
      }),
    );
  }

  Future<void> _stopVoiceRecording({required bool send}) async {
    _recordTimer?.cancel();
    final path = await _recorder.stop();
    final duration = _recordSeconds;
    setState(() {
      _isRecording = false;
      _recordSeconds = 0;
    });

    if (!send || path == null) {
      if (path != null) {
        try {
          await File(path).delete();
        } catch (_) {}
      }
      return;
    }

    final user = context.read<UserProvider>().user;
    if (user == null) return;
    setState(() => _sendingMedia = true);
    try {
      final msgId = await FirebaseService.instance.sendMessage(GroupMessage(
        id: '',
        groupId: widget.group.id,
        userId: user.id,
        userName: user.name,
        userPhotoUrl: user.photoUrl,
        text: '',
        messageType: MessageType.voice,
        mediaDuration: duration,
        createdAt: DateTime.now(),
      ));
      final url = await FirebaseService.instance
          .uploadVoiceNote(widget.group.id, msgId, File(path));
      await FirebaseService.instance.updateMessageMedia(
          widget.group.id, msgId, url,
          mediaDuration: duration);
      _scrollBottom();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  // ── Location share ────────────────────────────────────────────
  Future<void> _shareLocation() async {
    Duration? chosen;
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                  child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                          color: AppTheme.cutBorder,
                          borderRadius: BorderRadius.circular(2)))),
              const Text('Share Live Location For',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ..._locationDurations.map((e) => ListTile(
                    leading:
                        const Icon(Icons.timer_outlined, color: Colors.teal),
                    title: Text(e.$1),
                    onTap: () {
                      chosen = e.$2;
                      Navigator.pop(context);
                    },
                  )),
            ]),
      )),
    );
    if (chosen == null || !mounted) return;

    final user = context.read<UserProvider>().user;
    if (user == null) return;

    setState(() => _sendingMedia = true);
    try {
      final pos = await LocationService.instance.getCurrentPosition();
      if (pos == null) {
        _showSnack('Could not get location. Enable GPS.', error: true);
        return;
      }
      final address = await LocationService.instance
              .reverseGeocode(pos.latitude, pos.longitude) ??
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';

      await FirebaseService.instance.sendMessage(GroupMessage(
        id: '',
        groupId: widget.group.id,
        userId: user.id,
        userName: user.name,
        userPhotoUrl: user.photoUrl,
        text: address,
        messageType: MessageType.location,
        locationLat: pos.latitude,
        locationLng: pos.longitude,
        locationAddress: address,
        locationExpiresAt: DateTime.now().add(chosen!),
        createdAt: DateTime.now(),
      ));
      _scrollBottom();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _sendingMedia = false);
    }
  }

  Future<void> _changeCover() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked == null || !mounted) return;
    setState(() => _uploadingCover = true);
    try {
      await FirebaseService.instance
          .uploadGroupCover(widget.group.id, File(picked.path));
      if (mounted) _showSnack('Group icon updated!');
    } catch (e) {
      if (mounted) _showSnack('Upload failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppTheme.cutRed : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<UserProvider>().user?.id ?? '';

    return StreamBuilder<GroupModel?>(
      stream: FirebaseService.instance.groupStream(widget.group.id),
      initialData: widget.group,
      builder: (_, groupSnap) {
        final group = groupSnap.data ?? widget.group;
        final isAdmin = group.adminId == uid;

        return Scaffold(
          appBar: AppBar(
            title: Row(children: [
              GestureDetector(
                onTap: isAdmin ? _changeCover : null,
                child: Stack(children: [
                  _coverAvatar(group, radius: 18),
                  if (isAdmin)
                    Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                                color: Colors.white, shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt,
                                size: 10, color: AppTheme.cutBlue))),
                  if (_uploadingCover)
                    Positioned.fill(
                        child: Container(
                            decoration: const BoxDecoration(
                                color: Colors.black45, shape: BoxShape.circle),
                            child: const Center(
                                child: SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2))))),
                ]),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Flexible(
                          child: Text(group.name,
                              style: const TextStyle(fontSize: 15),
                              overflow: TextOverflow.ellipsis)),
                      if (group.isVerified) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 14, color: Colors.white)
                      ],
                      if (group.isLocked) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.lock_outline,
                            size: 13, color: Colors.white70)
                      ],
                    ]),
                    Text(
                        '${group.memberCount} member${group.memberCount == 1 ? '' : 's'}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70)),
                  ])),
            ]),
            actions: [
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (v) async {
                  if (v == 'info') _showGroupInfo(context, group, uid, isAdmin);
                  if (v == 'cover') _changeCover();
                  if (v == 'requests' && isAdmin) {
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => JoinRequestsScreen(group: group)));
                  }
                  if (v == 'report')
                    showReportDialog(context,
                        itemType: 'group',
                        itemId: group.id,
                        itemName: group.name);
                  if (v == 'leave') _confirmLeave(context, group, uid);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'info',
                      child: Row(children: [
                        Icon(Icons.info_outline, size: 18),
                        SizedBox(width: 8),
                        Text('Group Info')
                      ])),
                  if (isAdmin)
                    const PopupMenuItem(
                        value: 'cover',
                        child: Row(children: [
                          Icon(Icons.image_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Change Group Icon')
                        ])),
                  if (isAdmin && !group.isOpen)
                    const PopupMenuItem(
                        value: 'requests',
                        child: Row(children: [
                          Icon(Icons.person_add_outlined, size: 18),
                          SizedBox(width: 8),
                          Text('Join Requests')
                        ])),
                  if (!isAdmin)
                    const PopupMenuItem(
                        value: 'report',
                        child: Row(children: [
                          Icon(Icons.flag_outlined,
                              size: 18, color: AppTheme.cutRed),
                          SizedBox(width: 8),
                          Text('Report Group',
                              style: TextStyle(color: AppTheme.cutRed))
                        ])),
                  if (!isAdmin)
                    const PopupMenuItem(
                        value: 'leave',
                        child: Row(children: [
                          Icon(Icons.exit_to_app,
                              size: 18, color: AppTheme.cutRed),
                          SizedBox(width: 8),
                          Text('Leave Group',
                              style: TextStyle(color: AppTheme.cutRed))
                        ])),
                ],
              ),
            ],
          ),
          body: Column(children: [
            if (group.isSuspended) const GroupSuspendedBanner(),
            if (group.isLocked && !group.isSuspended) const GroupLockedBanner(),
            if (_sendingMedia)
              const LinearProgressIndicator(
                  backgroundColor: AppTheme.cutGrey, color: AppTheme.cutBlue),
            Expanded(
              child: StreamBuilder<List<GroupMessage>>(
                stream: FirebaseService.instance.messagesStream(group.id),
                builder: (_, snap) {
                  if (snap.connectionState == ConnectionState.waiting)
                    return const Center(child: CircularProgressIndicator());
                  final msgs = snap.data ?? [];
                  if (msgs.isEmpty)
                    return const EmptyState(
                        icon: Icons.chat_bubble_outline,
                        title: 'No messages yet',
                        subtitle: 'Start the conversation.');
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final msg = msgs[i];
                      final mine = msg.userId == uid;
                      final isAdminMsg = msg.userId == group.adminId;
                      final showDate = i == 0 ||
                          !_sameDay(msgs[i - 1].createdAt, msg.createdAt);
                      final showName = !mine &&
                          (i == 0 ||
                              msgs[i - 1].userId != msg.userId ||
                              msg.createdAt
                                      .difference(msgs[i - 1].createdAt)
                                      .inMinutes
                                      .abs() >=
                                  10);
                      return Column(children: [
                        if (showDate) _DateSep(msg.createdAt),
                        _Bubble(
                            msg: msg,
                            mine: mine,
                            showName: showName,
                            isAdminMsg: isAdminMsg,
                            onAvatarTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                    builder: (_) => UserProfileScreen(
                                        userId: msg.userId)))),
                      ]);
                    },
                  );
                },
              ),
            ),
            _InputBar(
                ctrl: _ctrl,
                onSend: _send,
                onAttach: _showAttachMenu,
                disabled: group.isLocked || group.isSuspended),
          ]),
        );
      },
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Widget _coverAvatar(GroupModel group, {double radius = 24}) {
    final url = group.coverUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
          child: CachedNetworkImage(
              imageUrl: url,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              placeholder: (_, __) => _letterAvatar(group, radius),
              errorWidget: (_, __, ___) => _letterAvatar(group, radius)));
    }
    return _letterAvatar(group, radius);
  }

  Widget _letterAvatar(GroupModel group, double r) => CircleAvatar(
      radius: r,
      backgroundColor: Colors.white.withValues(alpha: 0.25),
      child: Text(group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
          style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: r * 0.8)));

  void _showGroupInfo(
      BuildContext context, GroupModel group, String uid, bool isAdmin) {
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _GroupInfoSheet(
            group: group,
            uid: uid,
            isAdmin: isAdmin,
            onChangeCover: _changeCover));
  }

  Future<void> _confirmLeave(
      BuildContext context, GroupModel group, String uid) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text('Leave ${group.name}?'),
              content: const Text('You can re-join any time.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cutRed),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Leave'))
              ],
            ));
    if (ok == true && context.mounted) {
      await context.read<GroupProvider>().leaveGroup(group.id, uid);
      if (context.mounted) Navigator.of(context).pop();
    }
  }
}

// ─── Group Info sheet ─────────────────────────────────────────────
class _GroupInfoSheet extends StatefulWidget {
  final GroupModel group;
  final String uid;
  final bool isAdmin;
  final VoidCallback onChangeCover;
  const _GroupInfoSheet(
      {required this.group,
      required this.uid,
      required this.isAdmin,
      required this.onChangeCover});
  @override
  State<_GroupInfoSheet> createState() => _GroupInfoSheetState();
}

class _GroupInfoSheetState extends State<_GroupInfoSheet> {
  bool _loadingMembers = false;
  List<UserModel>? _members;

  Future<void> _loadMembers() async {
    setState(() => _loadingMembers = true);
    try {
      final users =
          await FirebaseService.instance.getUsers(widget.group.memberIds);
      if (mounted) setState(() => _members = users);
    } catch (_) {
      if (mounted) setState(() => _members = []);
    } finally {
      if (mounted) setState(() => _loadingMembers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.92,
      builder: (_, ctrl) => SafeArea(
        child: SingleChildScrollView(
          controller: ctrl,
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(
                child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                        color: AppTheme.cutBorder,
                        borderRadius: BorderRadius.circular(2)))),
            Row(children: [
              GestureDetector(
                onTap: widget.isAdmin ? widget.onChangeCover : null,
                child: Stack(children: [
                  _coverCircle(radius: 32),
                  if (widget.isAdmin)
                    Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                                color: AppTheme.cutBlue,
                                shape: BoxShape.circle),
                            child: const Icon(Icons.camera_alt,
                                size: 12, color: Colors.white))),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Row(children: [
                      Flexible(
                          child: Text(widget.group.name,
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis)),
                      if (widget.group.isVerified) ...[
                        const SizedBox(width: 6),
                        const VerifiedBadge(size: 18)
                      ],
                    ]),
                  ])),
            ]),
            const SizedBox(height: 14),
            if (widget.group.description.isNotEmpty) ...[
              Text(widget.group.description,
                  style: const TextStyle(
                      fontSize: 13, color: AppTheme.cutMuted, height: 1.5)),
              const SizedBox(height: 14),
            ],
            OutlinedButton.icon(
              onPressed: _loadingMembers
                  ? null
                  : () {
                      if (_members == null) {
                        _loadMembers();
                      } else {
                        setState(() => _members = null);
                      }
                    },
              icon: _loadingMembers
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(
                      _members != null
                          ? Icons.expand_less
                          : Icons.group_outlined,
                      size: 16),
              label: Text(
                  '${widget.group.memberCount} Member${widget.group.memberCount == 1 ? '' : 's'}',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.cutBlue,
                  side: const BorderSide(color: AppTheme.cutBlue),
                  minimumSize: const Size(double.infinity, 44)),
            ),
            if (_members != null) ...[
              const SizedBox(height: 12),
              ..._members!.map((u) => _MemberTile(
                    user: u,
                    isAdmin: u.id == widget.group.adminId,
                    canManage: widget.isAdmin && u.id != widget.uid,
                    onTimeout: () =>
                        _showMemberActions(context, u, isBan: false),
                    onBan: () => _showMemberActions(context, u, isBan: true),
                    onTapAvatar: () {
                      Navigator.pop(context);
                      Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => UserProfileScreen(userId: u.id)));
                    },
                  )),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _coverCircle({double radius = 32}) {
    final url = widget.group.coverUrl;
    if (url != null && url.isNotEmpty) {
      return ClipOval(
          child: CachedNetworkImage(
              imageUrl: url,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              placeholder: (_, __) => _letterCircle(radius),
              errorWidget: (_, __, ___) => _letterCircle(radius)));
    }
    return _letterCircle(radius);
  }

  Widget _letterCircle(double r) => CircleAvatar(
      radius: r,
      backgroundColor: AppTheme.cutBlue.withValues(alpha: 0.12),
      child: Text(
          widget.group.name.isNotEmpty
              ? widget.group.name[0].toUpperCase()
              : 'G',
          style: TextStyle(
              color: AppTheme.cutBlue,
              fontWeight: FontWeight.w700,
              fontSize: r * 0.7)));

  Future<void> _showMemberActions(BuildContext context, UserModel u,
      {required bool isBan}) async {
    if (isBan) {
      final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
                title: Text('Ban ${u.name}?'),
                content: Text(
                    '${u.name} will be permanently removed and cannot rejoin without sending a new join request.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  ElevatedButton(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.cutRed),
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Ban User'))
                ],
              ));
      if (ok == true && context.mounted) {
        await context.read<GroupProvider>().banUser(widget.group.id, u.id);
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('${u.name} has been banned.')));
      }
    } else {
      Duration? chosen;
      await showDialog(
          context: context,
          builder: (_) => AlertDialog(
                title: Text('Timeout ${u.name}'),
                content: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Remove from group for:'),
                  const SizedBox(height: 8),
                  ...[
                    ('5 minutes', const Duration(minutes: 5)),
                    ('10 minutes', const Duration(minutes: 10)),
                    ('1 hour', const Duration(hours: 1))
                  ].map((e) => ListTile(
                      title: Text(e.$1),
                      onTap: () {
                        chosen = e.$2;
                        Navigator.pop(context);
                      })),
                ]),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'))
                ],
              ));
      if (chosen != null && context.mounted) {
        await context.read<GroupProvider>().timeoutUser(widget.group.id, u.id);
        if (context.mounted)
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  '${u.name} removed. They can rejoin after the timeout.')));
      }
    }
  }
}

class _MemberTile extends StatelessWidget {
  final UserModel user;
  final bool isAdmin, canManage;
  final VoidCallback onTimeout, onBan, onTapAvatar;
  const _MemberTile(
      {required this.user,
      required this.isAdmin,
      required this.canManage,
      required this.onTimeout,
      required this.onBan,
      required this.onTapAvatar});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          GestureDetector(
              onTap: onTapAvatar,
              child: UserAvatar(
                  photoUrl: user.photoUrl,
                  initials:
                      user.name.isNotEmpty ? user.name[0].toUpperCase() : '?',
                  radius: 20)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Flexible(
                      child: Text(user.name,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis)),
                  if (user.isVerified) ...[
                    const SizedBox(width: 4),
                    const VerifiedBadge(size: 13)
                  ],
                  if (isAdmin) ...[
                    const SizedBox(width: 6),
                    Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                            color: AppTheme.cutBlue.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4)),
                        child: const Text('Admin',
                            style: TextStyle(
                                fontSize: 10,
                                color: AppTheme.cutBlue,
                                fontWeight: FontWeight.w700)))
                  ],
                ]),
                Text(user.campus,
                    style: const TextStyle(
                        fontSize: 11, color: AppTheme.cutMuted)),
              ])),
          if (canManage)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert,
                  size: 18, color: AppTheme.cutMuted),
              onSelected: (v) {
                if (v == 'timeout') onTimeout();
                if (v == 'ban') onBan();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(
                    value: 'timeout',
                    child: Row(children: [
                      Icon(Icons.timer_outlined,
                          size: 18, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Timeout')
                    ])),
                const PopupMenuItem(
                    value: 'ban',
                    child: Row(children: [
                      Icon(Icons.block, size: 18, color: AppTheme.cutRed),
                      SizedBox(width: 8),
                      Text('Permanently Remove',
                          style: TextStyle(color: AppTheme.cutRed))
                    ])),
              ],
            ),
        ]),
      );
}

// ─── Bubble ───────────────────────────────────────────────────────
class _Bubble extends StatelessWidget {
  final GroupMessage msg;
  final bool mine, showName, isAdminMsg;
  final VoidCallback onAvatarTap;
  const _Bubble(
      {required this.msg,
      required this.mine,
      required this.showName,
      required this.isAdminMsg,
      required this.onAvatarTap});

  @override
  Widget build(BuildContext context) {
    final sc = _colorFor(msg.userId);
    final bg = mine ? AppTheme.cutBlue : Colors.white;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Row(
        mainAxisAlignment:
            mine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!mine) ...[
            Padding(
              padding: EdgeInsets.only(top: showName ? 20 : 4),
              child: GestureDetector(
                  onTap: onAvatarTap,
                  child: UserAvatar(
                      photoUrl: msg.userPhotoUrl,
                      initials: msg.userName.isNotEmpty
                          ? msg.userName[0].toUpperCase()
                          : '?',
                      radius: 16)),
            ),
            const SizedBox(width: 6),
          ],
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72),
            margin: const EdgeInsets.symmetric(vertical: 4),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(mine ? 18 : (showName ? 8 : 18)),
                  topRight: Radius.circular(mine ? 8 : 18),
                  bottomLeft: const Radius.circular(18),
                  bottomRight: const Radius.circular(18)),
              border: mine ? null : Border.all(color: AppTheme.cutBorder),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4))
              ],
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (!mine && showName)
                Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(msg.userName,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: sc.withValues(alpha: 0.8))),
                      if (isAdminMsg) ...[
                        const SizedBox(width: 4),
                        const VerifiedBadge(size: 12)
                      ],
                    ])),
              _buildContent(context, mine),
              const SizedBox(height: 5),
              Row(mainAxisSize: MainAxisSize.min, children: [
                TimeAgoText(msg.createdAt,
                    style: TextStyle(
                        fontSize: 10,
                        color: mine ? Colors.white70 : AppTheme.cutMuted)),
                if (mine) ...[
                  const SizedBox(width: 4),
                  const Icon(Icons.done_all, size: 13, color: Colors.white70),
                ],
              ]),
            ]),
          ),
          if (mine) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, bool mine) {
    switch (msg.messageType) {
      case MessageType.image:
        return _ImageContent(msg: msg, mine: mine);
      case MessageType.video:
        return _VideoContent(msg: msg, mine: mine);
      case MessageType.voice:
        return _VoiceContent(msg: msg, mine: mine);
      case MessageType.location:
        return _LocationContent(msg: msg, mine: mine);
      case MessageType.text:
      default:
        return Text(msg.text,
            style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: mine ? Colors.white : AppTheme.cutDark));
    }
  }
}

// ── Image bubble — FIX: tap opens fullscreen viewer ────────────────
class _ImageContent extends StatelessWidget {
  final GroupMessage msg;
  final bool mine;
  const _ImageContent({required this.msg, required this.mine});
  @override
  Widget build(BuildContext context) {
    if (msg.mediaUrl == null || msg.mediaUrl!.isEmpty) {
      return Row(children: [
        SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: mine ? Colors.white : AppTheme.cutBlue)),
        const SizedBox(width: 8),
        Text('Uploading…',
            style: TextStyle(
                fontSize: 12,
                color: mine ? Colors.white70 : AppTheme.cutMuted)),
      ]);
    }
    return GestureDetector(
      onTap: () => FullscreenImageViewer.show(context, msg.mediaUrl!),
      child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: CachedNetworkImage(
              imageUrl: msg.mediaUrl!,
              width: 200,
              height: 200,
              fit: BoxFit.cover,
              placeholder: (_, __) => Container(
                  width: 200,
                  height: 200,
                  color: Colors.grey.shade200,
                  child: const Center(child: CircularProgressIndicator())),
              errorWidget: (_, __, ___) => Container(
                  width: 200,
                  height: 120,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image_outlined)))),
    );
  }
}

// ── Video bubble — FIX: tap opens fullscreen playback ──────────────
class _VideoContent extends StatelessWidget {
  final GroupMessage msg;
  final bool mine;
  const _VideoContent({required this.msg, required this.mine});
  @override
  Widget build(BuildContext context) {
    if (msg.mediaUrl == null || msg.mediaUrl!.isEmpty) {
      return Row(children: [
        SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: mine ? Colors.white : AppTheme.cutBlue)),
        const SizedBox(width: 8),
        Text('Uploading video…',
            style: TextStyle(
                fontSize: 12,
                color: mine ? Colors.white70 : AppTheme.cutMuted)),
      ]);
    }
    return GestureDetector(
      onTap: () => FullscreenVideoViewer.show(context, msg.mediaUrl!),
      child: Container(
          width: 200,
          height: 120,
          decoration: BoxDecoration(
              color: Colors.black, borderRadius: BorderRadius.circular(10)),
          child: Stack(alignment: Alignment.center, children: [
            Container(
                width: 48,
                height: 48,
                decoration: const BoxDecoration(
                    color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.play_arrow,
                    color: Colors.white, size: 32)),
          ])),
    );
  }
}

// ── Voice bubble ─────────────────────────────────────────────────
class _VoiceContent extends StatefulWidget {
  final GroupMessage msg;
  final bool mine;
  const _VoiceContent({required this.msg, required this.mine});
  @override
  State<_VoiceContent> createState() => _VoiceContentState();
}

class _VoiceContentState extends State<_VoiceContent> {
  final AudioPlayer _player = AudioPlayer();
  bool _loading = false;
  bool _ready = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<PlayerState>? _stateSub;

  @override
  void initState() {
    super.initState();
    _positionSub = _player.positionStream.listen((value) {
      if (mounted) setState(() => _position = value);
    });
    _durationSub = _player.durationStream.listen((value) {
      if (mounted) setState(() => _duration = value ?? Duration.zero);
    });
    _stateSub = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        _player.pause();
        _player.seek(Duration.zero);
      }
      setState(() => _loading =
          state.processingState == ProcessingState.loading ||
              state.processingState == ProcessingState.buffering);
    });
  }

  @override
  void didUpdateWidget(covariant _VoiceContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.msg.mediaUrl != widget.msg.mediaUrl) {
      _ready = false;
      _position = Duration.zero;
      _duration = Duration.zero;
      _player.stop();
    }
  }

  @override
  void dispose() {
    if (_activeVoiceNote == this) _activeVoiceNote = null;
    _positionSub?.cancel();
    _durationSub?.cancel();
    _stateSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final url = widget.msg.mediaUrl;
    if (url == null || url.isEmpty || _loading) return;
    try {
      if (_activeVoiceNote != null && _activeVoiceNote != this) {
        await _activeVoiceNote!._pauseFromCoordinator();
      }
      _activeVoiceNote = this;
      if (!_ready) {
        setState(() => _loading = true);
        await _player.setUrl(url);
        _ready = true;
      }
      if (_player.playing) {
        await _player.pause();
      } else {
        if (_duration > Duration.zero && _position >= _duration) {
          await _player.seek(Duration.zero);
        }
        await _player.play();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Could not play this voice note.'),
          backgroundColor: AppTheme.cutRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pauseFromCoordinator() async {
    if (_player.playing) await _player.pause();
  }

  @override
  Widget build(BuildContext context) {
    final msg = widget.msg;
    final mine = widget.mine;
    if (msg.mediaUrl == null || msg.mediaUrl!.isEmpty) {
      return Row(children: [
        SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: mine ? Colors.white : AppTheme.cutBlue)),
        const SizedBox(width: 8),
        Text('Uploading voice note…',
            style: TextStyle(
                fontSize: 12,
                color: mine ? Colors.white70 : AppTheme.cutMuted)),
      ]);
    }
    final duration = _duration.inMilliseconds > 0
        ? _duration
        : Duration(seconds: msg.mediaDuration ?? 0);
    final progress = duration.inMilliseconds == 0
        ? 0.0
        : (_position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Semantics(
      button: true,
      label: _player.playing ? 'Pause voice note' : 'Play voice note',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        InkWell(
          onTap: _toggle,
          borderRadius: BorderRadius.circular(18),
          child: _loading
              ? SizedBox(
                  width: 30,
                  height: 30,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: mine ? Colors.white : AppTheme.cutBlue),
                )
              : Icon(
                  _player.playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  color: mine ? Colors.white : AppTheme.cutBlue,
                  size: 30),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 118,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            ),
            child: Slider(
              value: progress,
              min: 0,
              max: 1,
              activeColor: mine ? Colors.white : AppTheme.cutBlue,
              inactiveColor: (mine ? Colors.white : AppTheme.cutBlue)
                  .withValues(alpha: 0.25),
              onChanged: duration.inMilliseconds == 0
                  ? null
                  : (value) => _player.seek(Duration(
                      milliseconds: (duration.inMilliseconds * value).round())),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(_formatDuration(duration),
            style: TextStyle(
                fontSize: 11,
                color: mine ? Colors.white70 : AppTheme.cutMuted)),
      ]),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration == Duration.zero) return '--:--';
    final minutes = duration.inMinutes.remainder(60).toString();
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

// ── Location bubble ──────────────────────────────────────────────
class _LocationContent extends StatelessWidget {
  final GroupMessage msg;
  final bool mine;
  const _LocationContent({required this.msg, required this.mine});
  @override
  Widget build(BuildContext context) {
    final expired = msg.isLocationExpired;
    final hasCoords = msg.locationLat != null && msg.locationLng != null;
    final coords = hasCoords
        ? '${msg.locationLat!.toStringAsFixed(5)}, ${msg.locationLng!.toStringAsFixed(5)}'
        : '';
    return GestureDetector(
      onTap: expired ? null : () => _showMap(context),
      child: Container(
        width: 230,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: expired
              ? Colors.grey.shade200
              : (mine
                  ? Colors.white.withValues(alpha: 0.15)
                  : Colors.teal.withValues(alpha: 0.1)),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: expired ? Colors.grey.shade400 : Colors.teal),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!expired && hasCoords) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedNetworkImage(
                imageUrl: _staticMapUrl(width: 460, height: 180),
                width: double.infinity,
                height: 88,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 88,
                  color: Colors.teal.withValues(alpha: 0.12),
                  child: const Center(
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) => Container(
                  height: 88,
                  color: Colors.teal.withValues(alpha: 0.12),
                  child: const Icon(Icons.map_outlined, color: Colors.teal),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(expired ? Icons.location_off_outlined : Icons.location_on,
                color: expired ? Colors.grey : Colors.teal, size: 20),
            const SizedBox(width: 8),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(
                      expired
                          ? 'Location expired'
                          : (msg.locationAddress ?? 'Shared location'),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: expired
                              ? Colors.grey
                              : (mine ? Colors.white : AppTheme.cutDark)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (!expired && coords.isNotEmpty)
                    Text(coords,
                        style: TextStyle(
                            fontSize: 10,
                            color: mine ? Colors.white70 : AppTheme.cutMuted)),
                  if (!expired && msg.locationExpiresAt != null)
                    Text('Expires ${_timeLeft(msg.locationExpiresAt!)}',
                        style: TextStyle(
                            fontSize: 10,
                            color: mine ? Colors.white60 : AppTheme.cutMuted)),
                ])),
          ]),
          if (!expired && hasCoords) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _openMaps,
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('Open in Maps'),
                style: TextButton.styleFrom(
                  foregroundColor: mine ? Colors.white : Colors.teal,
                  textStyle: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ],
        ]),
      ),
    );
  }

  String _staticMapUrl({required int width, required int height}) =>
      'https://maps.googleapis.com/maps/api/staticmap?center=${msg.locationLat},${msg.locationLng}'
      '&zoom=15&size=${width}x$height&markers=color:red|${msg.locationLat},${msg.locationLng}'
      '&key=$_mapsApiKey';

  String _timeLeft(DateTime expires) {
    final diff = expires.difference(DateTime.now());
    if (diff.inHours >= 1) return 'in ${diff.inHours}h';
    if (diff.inMinutes >= 1) return 'in ${diff.inMinutes}m';
    return 'soon';
  }

  void _showMap(BuildContext context) {
    if (msg.locationLat == null || msg.locationLng == null) return;
    showDialog(
        context: context,
        builder: (_) => Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      const Icon(Icons.location_on, color: Colors.teal),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(msg.locationAddress ?? 'Live Location',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600)))
                    ]),
                    const SizedBox(height: 8),
                    if (msg.locationExpiresAt != null)
                      Text(
                          'Expires at ${msg.locationExpiresAt!.hour.toString().padLeft(2, '0')}:${msg.locationExpiresAt!.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(
                              fontSize: 12, color: AppTheme.cutMuted)),
                    const SizedBox(height: 12),
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                          color: AppTheme.cutGrey,
                          borderRadius: BorderRadius.circular(10)),
                      child: ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: CachedNetworkImage(
                            imageUrl: _staticMapUrl(width: 400, height: 200),
                            fit: BoxFit.cover,
                            placeholder: (_, __) => const Center(
                                child: CircularProgressIndicator()),
                            errorWidget: (_, __, ___) => Center(
                                child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                  const Icon(Icons.map_outlined,
                                      size: 36, color: AppTheme.cutMuted),
                                  const SizedBox(height: 8),
                                  Text(
                                      '${msg.locationLat!.toStringAsFixed(5)}, ${msg.locationLng!.toStringAsFixed(5)}',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          color: AppTheme.cutMuted)),
                                ])),
                          )),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                            onPressed: _openMaps,
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('Open in Maps'))),
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Close')),
                  ])),
            ));
  }

  Future<void> _openMaps() async {
    if (msg.locationLat == null || msg.locationLng == null) return;
    final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=${msg.locationLat},${msg.locationLng}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

class _DateSep extends StatelessWidget {
  final DateTime date;
  const _DateSep(this.date);
  String _label() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(date.year, date.month, date.day);
    if (d == today) return 'Today';
    if (d == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          const Expanded(child: Divider()),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Text(_label(),
                  style:
                      const TextStyle(fontSize: 11, color: AppTheme.cutMuted))),
          const Expanded(child: Divider())
        ]),
      );
}

class _AttachBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _AttachBtn(
      {required this.icon,
      required this.label,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Column(children: [
        Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(color: color.withValues(alpha: 0.3))),
            child: Icon(icon, color: color, size: 26)),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 11)),
      ]));
}

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final VoidCallback onSend, onAttach;
  final bool disabled;
  const _InputBar(
      {required this.ctrl,
      required this.onSend,
      required this.onAttach,
      this.disabled = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.fromLTRB(
            8, 6, 8, 6 + MediaQuery.of(context).padding.bottom),
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppTheme.cutBorder))),
        child: Row(children: [
          IconButton(
              icon: Icon(Icons.attach_file,
                  color: disabled ? AppTheme.cutBorder : AppTheme.cutMuted,
                  size: 22),
              onPressed: disabled ? null : onAttach,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36)),
          Expanded(
              child: TextField(
                  controller: ctrl,
                  minLines: 1,
                  maxLines: 4,
                  enabled: !disabled,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                      hintText: disabled
                          ? 'Messaging is disabled for this group'
                          : 'Type a message…',
                      filled: true,
                      fillColor: AppTheme.cutGrey,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8)))),
          const SizedBox(width: 6),
          GestureDetector(
              onTap: disabled ? null : onSend,
              child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                      color: disabled ? AppTheme.cutBorder : AppTheme.cutBlue,
                      shape: BoxShape.circle),
                  child: const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20))),
        ]),
      );
}
