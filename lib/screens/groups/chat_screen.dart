import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
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

// Shared cache manager for all chat media (images + videos). Keeps files
// on-device for a year and allows a generous cache size, so media only
// downloads once per device — matching WhatsApp-style local persistence.
final CacheManager chatMediaCacheManager = CacheManager(
  Config(
    'cutSafetyChatMediaCache',
    stalePeriod: const Duration(days: 365),
    maxNrOfCacheObjects: 500,
  ),
);

// Sender ("mine") bubble palette — deliberately a soft light blue,
// distinct from the app's main brand blue, with dark text for contrast.
const Color _myBubbleColor = Color(0xFFDCEEFF);
const Color _myBubbleBorder = Color(0xFFB6DBFF);
const Color _myBubbleTextColor = Color(0xFF0B4A7A);

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

  // Streams created ONCE — never call these methods inline inside build().
  // Doing so recreates the subscription on every setState/rebuild (i.e.
  // every button press), which resets the StreamBuilder to a loading
  // state and makes the whole chat look like it's "refreshing".
  late final Stream<GroupModel?> _groupStream;
  late final Stream<List<GroupMessage>> _messagesStream;

  @override
  void initState() {
    super.initState();
    _groupStream = FirebaseService.instance.groupStream(widget.group.id);
    _messagesStream = FirebaseService.instance.messagesStream(widget.group.id);
  }

  // Voice recording state
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String? _recordPath;

  // Reply state
  GroupMessage? _replyingTo;

  void _startReply(GroupMessage msg) {
    setState(() => _replyingTo = msg);
    FocusScope.of(context).requestFocus(FocusNode());
  }

  void _cancelReply() => setState(() => _replyingTo = null);

  String _replyPreviewFor(GroupMessage msg) {
    switch (msg.messageType) {
      case MessageType.image:
        return '📷 Photo';
      case MessageType.video:
        return '🎥 Video';
      case MessageType.voice:
        return '🎤 Voice message';
      case MessageType.location:
        return '📍 Location';
      case MessageType.text:
      default:
        return msg.text;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scroll.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final user = context.read<UserProvider>().user;
    if (user == null) return;
    final replyTo = _replyingTo;
    _ctrl.clear();
    setState(() => _replyingTo = null);
    try {
      await FirebaseService.instance.sendMessage(GroupMessage(
        id: '',
        groupId: widget.group.id,
        userId: user.id,
        userName: user.name,
        userPhotoUrl: user.photoUrl,
        text: text,
        createdAt: DateTime.now(),
        replyToMessageId: replyTo?.id,
        replyToSenderName: replyTo?.userName,
        replyToText: replyTo != null ? _replyPreviewFor(replyTo) : null,
        replyToType: replyTo?.messageType.value,
      ));
      _scrollBottom();
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''), error: true);
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // With reverse:true, offset 0 IS the bottom/newest-message anchor.
      if (_scroll.hasClients) {
        _scroll.animateTo(0,
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
    setState(() => _isRecording = true);
    if (mounted) _showRecordingSheet();
  }

  void _showRecordingSheet() {
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => _RecordingSheet(
        maxSeconds: 90,
        onCancel: (seconds) {
          Navigator.pop(context);
          _stopVoiceRecording(send: false, duration: seconds);
        },
        onSend: (seconds) {
          Navigator.pop(context);
          _stopVoiceRecording(send: true, duration: seconds);
        },
      ),
    );
  }

  Future<void> _stopVoiceRecording(
      {required bool send, required int duration}) async {
    final path = await _recorder.stop();
    setState(() => _isRecording = false);

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
      stream: _groupStream,
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
                stream: _messagesStream,
                builder: (_, snap) {
                  if (snap.connectionState == ConnectionState.waiting)
                    return const Center(child: CircularProgressIndicator());
                  final msgs = (snap.data ?? []).reversed.toList();
                  if (msgs.isEmpty)
                    return const EmptyState(
                        icon: Icons.chat_bubble_outline,
                        title: 'No messages yet',
                        subtitle: 'Start the conversation.');
                  return ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final msg = msgs[i];
                      final mine = msg.userId == uid;
                      final isAdminMsg = msg.userId == group.adminId;
                      // In this reversed list, index i+1 is the chronologically
                      // OLDER neighbour (since index 0 = newest).
                      final older = i + 1 < msgs.length ? msgs[i + 1] : null;
                      final showDate = older == null ||
                          !_sameDay(older.createdAt, msg.createdAt);
                      final showName = !mine &&
                          (older == null ||
                              older.userId != msg.userId ||
                              msg.createdAt
                                      .difference(older.createdAt)
                                      .inMinutes
                                      .abs() >=
                                  10);
                      return Column(
                        key: ValueKey(msg.id),
                        children: [
                          if (showDate) _DateSep(msg.createdAt),
                          _Bubble(
                              msg: msg,
                              mine: mine,
                              showName: showName,
                              isAdminMsg: isAdminMsg,
                              onAvatarTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) => UserProfileScreen(
                                          userId: msg.userId))),
                              onReply: () => _startReply(msg)),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            if (_replyingTo != null)
              _ReplyPreviewBar(
                userName: _replyingTo!.userId == uid
                    ? 'Yourself'
                    : _replyingTo!.userName,
                preview: _replyPreviewFor(_replyingTo!),
                onCancel: _cancelReply,
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
  final VoidCallback onReply;
  const _Bubble(
      {required this.msg,
      required this.mine,
      required this.showName,
      required this.isAdminMsg,
      required this.onAvatarTap,
      required this.onReply});

  @override
  Widget build(BuildContext context) {
    final sc = _colorFor(msg.userId);
    final bg = mine ? _myBubbleColor : Colors.white;
    final isMedia = (msg.messageType == MessageType.image ||
            msg.messageType == MessageType.video) &&
        msg.mediaUrl != null &&
        msg.mediaUrl!.isNotEmpty;

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
          if (isMedia)
            _SwipeToReply(
              onReply: onReply,
              child: _MediaBubble(
                msg: msg,
                mine: mine,
                showName: showName,
                isAdminMsg: isAdminMsg,
                accentColor: sc,
                content: _buildContent(context, mine),
              ),
            )
          else
            _SwipeToReply(
              onReply: onReply,
              child: Container(
                constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.72),
                margin: const EdgeInsets.symmetric(vertical: 4),
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.only(
                      topLeft:
                          Radius.circular(mine ? 18 : (showName ? 8 : 18)),
                      topRight: Radius.circular(mine ? 8 : 18),
                      bottomLeft: const Radius.circular(18),
                      bottomRight: const Radius.circular(18)),
                  border: Border.all(
                      color: mine ? _myBubbleBorder : AppTheme.cutBorder),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!mine && showName)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child:
                              Row(mainAxisSize: MainAxisSize.min, children: [
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
                    if (msg.replyToText != null) _ReplyQuote(msg: msg, mine: mine),
                    _buildContent(context, mine),
                    const SizedBox(height: 5),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      TimeAgoText(msg.createdAt,
                          style: TextStyle(
                              fontSize: 10,
                              color: mine
                                  ? _myBubbleTextColor.withValues(alpha: 0.7)
                                  : AppTheme.cutMuted)),
                      if (mine) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.done_all,
                            size: 13,
                            color:
                                _myBubbleTextColor.withValues(alpha: 0.6)),
                      ],
                    ]),
                  ],
                ),
              ),
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
                color: mine ? _myBubbleTextColor : AppTheme.cutDark));
    }
  }
}

// ─── Swipe-left-to-reply gesture wrapper ───────────────────────────
class _SwipeToReply extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;
  const _SwipeToReply({required this.child, required this.onReply});

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> {
  double _dragX = 0; // positive values only (swiping right)
  static const double _maxDrag = 64;
  static const double _triggerDrag = 44;
  bool _triggered = false;

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _dragX = (_dragX + d.delta.dx).clamp(0.0, _maxDrag);
      _triggered = _dragX >= _triggerDrag;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    if (_triggered) widget.onReply();
    setState(() {
      _dragX = 0;
      _triggered = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: Stack(clipBehavior: Clip.none, children: [
        if (_dragX > 4)
          Positioned(
            left: -28,
            top: 0,
            bottom: 0,
            child: Center(
              child: Opacity(
                opacity: (_dragX / _triggerDrag).clamp(0, 1),
                child: Icon(Icons.reply,
                    color: _triggered ? AppTheme.cutBlue : AppTheme.cutMuted,
                    size: 20),
              ),
            ),
          ),
        AnimatedContainer(
          duration: _dragX == 0
              ? const Duration(milliseconds: 180)
              : Duration.zero,
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(_dragX, 0, 0),
          child: widget.child,
        ),
      ]),
    );
  }
}

// ─── Cached, fully-controlled video player ─────────────────────────
// Downloads the video once via the shared cache manager, then plays from
// the local file. Subsequent opens of the same video are instant — no
// re-download — matching WhatsApp-style local media persistence.
class _CachedVideoPlayerScreen extends StatefulWidget {
  final String url;
  const _CachedVideoPlayerScreen({required this.url});

  @override
  State<_CachedVideoPlayerScreen> createState() =>
      _CachedVideoPlayerScreenState();
}

class _CachedVideoPlayerScreenState extends State<_CachedVideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _error = false;
  bool _controlsVisible = true;
  bool _muted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final file = await chatMediaCacheManager.getSingleFile(widget.url);
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      controller.addListener(() {
        if (mounted) setState(() {});
      });
      if (!mounted) return;
      setState(() {
        _controller = controller;
        _loading = false;
      });
      controller.play();
    } catch (_) {
      if (mounted) setState(() {
        _loading = false;
        _error = true;
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _togglePlay() {
    final c = _controller;
    if (c == null) return;
    setState(() => c.value.isPlaying ? c.pause() : c.play());
  }

  void _toggleMute() {
    final c = _controller;
    if (c == null) return;
    setState(() {
      _muted = !_muted;
      c.setVolume(_muted ? 0 : 1);
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: GestureDetector(
          onTap: () => setState(() => _controlsVisible = !_controlsVisible),
          child: Stack(children: [
            Center(
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : _error || c == null
                      ? const Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.error_outline,
                                color: Colors.white54, size: 40),
                            SizedBox(height: 8),
                            Text('Could not load video',
                                style: TextStyle(color: Colors.white70)),
                          ],
                        )
                      : AspectRatio(
                          aspectRatio: c.value.aspectRatio,
                          child: VideoPlayer(c),
                        ),
            ),
            if (_controlsVisible)
              Positioned(
                top: 4,
                left: 4,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            if (_controlsVisible && c != null && !_loading && !_error)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0),
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Text(_fmt(c.value.position),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 6),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 14),
                          ),
                          child: Slider(
                            value: c.value.position.inMilliseconds
                                .clamp(0, c.value.duration.inMilliseconds)
                                .toDouble(),
                            min: 0,
                            max: c.value.duration.inMilliseconds.toDouble().clamp(
                                1, double.infinity),
                            activeColor: Colors.white,
                            inactiveColor: Colors.white24,
                            onChanged: (v) => c.seekTo(
                                Duration(milliseconds: v.round())),
                          ),
                        ),
                      ),
                      Text(_fmt(c.value.duration),
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12)),
                    ]),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      IconButton(
                        icon: Icon(
                            _muted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white),
                        onPressed: _toggleMute,
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _togglePlay,
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                              color: Colors.white24, shape: BoxShape.circle),
                          child: Icon(
                              c.value.isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                              color: Colors.white,
                              size: 32),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ]),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}


class _RecordingSheet extends StatefulWidget {
  final int maxSeconds;
  final ValueChanged<int> onCancel;
  final ValueChanged<int> onSend;
  const _RecordingSheet(
      {required this.maxSeconds, required this.onCancel, required this.onSend});

  @override
  State<_RecordingSheet> createState() => _RecordingSheetState();
}

class _RecordingSheetState extends State<_RecordingSheet> {
  int _seconds = 0;
  Timer? _timer;
  bool _autoSent = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_seconds >= widget.maxSeconds && !_autoSent) {
        _autoSent = true;
        t.cancel();
        widget.onSend(_seconds);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final progress = _seconds / widget.maxSeconds;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(alignment: Alignment.center, children: [
            SizedBox(
              width: 72,
              height: 72,
              child: CircularProgressIndicator(
                value: progress.clamp(0, 1),
                strokeWidth: 3,
                backgroundColor: Colors.purple.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation(Colors.purple),
              ),
            ),
            Container(
                width: 56,
                height: 56,
                decoration: const BoxDecoration(
                    color: Colors.purple, shape: BoxShape.circle),
                child: const Icon(Icons.mic, color: Colors.white, size: 26)),
          ]),
          const SizedBox(height: 14),
          Text('${_seconds}s / ${widget.maxSeconds}s',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text('Recording voice note…',
              style: TextStyle(fontSize: 12, color: AppTheme.cutMuted)),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(
                child: OutlinedButton(
              onPressed: () => widget.onCancel(_seconds),
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.cutRed,
                  side: const BorderSide(color: AppTheme.cutRed)),
              child: const Text('Cancel'),
            )),
            const SizedBox(width: 10),
            Expanded(
                child: ElevatedButton(
              onPressed: () => widget.onSend(_seconds),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
              child: const Text('Send'),
            )),
          ]),
        ]),
      ),
    );
  }
}

// ─── Modern media bubble (image/video) — thin border, no padding box ──
class _MediaBubble extends StatelessWidget {
  final GroupMessage msg;
  final bool mine, showName, isAdminMsg;
  final Color accentColor;
  final Widget content;
  const _MediaBubble({
    required this.msg,
    required this.mine,
    required this.showName,
    required this.isAdminMsg,
    required this.accentColor,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: Radius.circular(mine ? 18 : (showName ? 8 : 18)),
      topRight: Radius.circular(mine ? 8 : 18),
      bottomLeft: const Radius.circular(18),
      bottomRight: const Radius.circular(18),
    );
    return Container(
      constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.62),
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ClipRRect(
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
                color: AppTheme.cutBorder.withValues(alpha: 0.8), width: 1),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (msg.replyToText != null)
                _ReplyQuote(msg: msg, mine: mine, dense: true),
              Stack(children: [
                content,
                // Sender name chip (group chats only)
                if (!mine && showName)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(msg.userName,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: accentColor.withValues(alpha: 1),
                                shadows: const [
                                  Shadow(color: Colors.black, blurRadius: 2)
                                ])),
                        if (isAdminMsg) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: 11)
                        ],
                      ]),
                    ),
                  ),
            // Timestamp + read receipt, bottom-right, on a soft gradient scrim
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 20, 8, 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                      bottomLeft: radius.bottomLeft,
                      bottomRight: radius.bottomRight),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0),
                      Colors.black.withValues(alpha: 0.45),
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    TimeAgoText(msg.createdAt,
                        style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w600)),
                    if (mine) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.done_all,
                          size: 13, color: Colors.white),
                    ],
                  ],
                ),
              ),
            ),
          ]),
            ],
          ),
        ),
      ),
    );
  }
}


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
                strokeWidth: 2, color: mine ? _myBubbleTextColor : AppTheme.cutBlue)),
        const SizedBox(width: 8),
        Text('Uploading…',
            style: TextStyle(
                fontSize: 12,
                color: mine ? _myBubbleTextColor.withValues(alpha: 0.7) : AppTheme.cutMuted)),
      ]);
    }
    return GestureDetector(
      onTap: () => FullscreenImageViewer.show(context, msg.mediaUrl!),
      child: CachedNetworkImage(
        imageUrl: msg.mediaUrl!,
        cacheManager: chatMediaCacheManager,
        width: double.infinity,
        height: 230,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
            width: double.infinity,
            height: 230,
            color: Colors.grey.shade200,
            child: const Center(child: CircularProgressIndicator())),
        errorWidget: (_, __, ___) => Container(
            width: double.infinity,
            height: 160,
            color: Colors.grey.shade200,
            child: const Icon(Icons.broken_image_outlined)),
      ),
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
                strokeWidth: 2, color: mine ? _myBubbleTextColor : AppTheme.cutBlue)),
        const SizedBox(width: 8),
        Text('Uploading video…',
            style: TextStyle(
                fontSize: 12,
                color: mine ? _myBubbleTextColor.withValues(alpha: 0.7) : AppTheme.cutMuted)),
      ]);
    }
    return GestureDetector(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => _CachedVideoPlayerScreen(url: msg.mediaUrl!))),
      child: Container(
          width: double.infinity,
          height: 230,
          color: Colors.black,
          child: Stack(alignment: Alignment.center, children: [
            Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Icon(Icons.play_arrow,
                    color: Colors.white, size: 30)),
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
                strokeWidth: 2, color: mine ? _myBubbleTextColor : AppTheme.cutBlue)),
        const SizedBox(width: 8),
        Text('Uploading voice note…',
            style: TextStyle(
                fontSize: 12,
                color: mine ? _myBubbleTextColor.withValues(alpha: 0.7) : AppTheme.cutMuted)),
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
                      color: mine ? _myBubbleTextColor : AppTheme.cutBlue),
                )
              : Icon(
                  _player.playing
                      ? Icons.pause_circle_filled
                      : Icons.play_circle_fill,
                  color: mine ? _myBubbleTextColor : AppTheme.cutBlue,
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
              activeColor: mine ? _myBubbleTextColor : AppTheme.cutBlue,
              inactiveColor: (mine ? _myBubbleTextColor : AppTheme.cutBlue)
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
                color: mine ? _myBubbleTextColor.withValues(alpha: 0.7) : AppTheme.cutMuted)),
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
                  ? _myBubbleBorder.withValues(alpha: 0.3)
                  : Colors.teal.withValues(alpha: 0.08)),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: expired ? Colors.grey.shade400 : Colors.teal.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!expired && hasCoords) ...[
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 100,
                    width: double.infinity,
                    child: IgnorePointer(
                      child: GoogleMap(
                        initialCameraPosition: CameraPosition(
                          target: LatLng(msg.locationLat!, msg.locationLng!),
                          zoom: 15.5,
                        ),
                        markers: {
                          Marker(
                            markerId: const MarkerId('preview'),
                            position: LatLng(msg.locationLat!, msg.locationLng!),
                          ),
                        },
                        liteModeEnabled: true,
                        zoomControlsEnabled: false,
                        zoomGesturesEnabled: false,
                        scrollGesturesEnabled: false,
                        rotateGesturesEnabled: false,
                        tiltGesturesEnabled: false,
                        myLocationButtonEnabled: false,
                        mapToolbarEnabled: false,
                        compassEnabled: false,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.touch_app_outlined, color: Colors.white, size: 12),
                      SizedBox(width: 4),
                      Text('Tap to explore',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
              ],
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
                              : (mine ? _myBubbleTextColor : AppTheme.cutDark)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (!expired && coords.isNotEmpty)
                    Text(coords,
                        style: TextStyle(
                            fontSize: 10,
                            color: mine ? _myBubbleTextColor.withValues(alpha: 0.7) : AppTheme.cutMuted)),
                  if (!expired && msg.locationExpiresAt != null)
                    Text('Expires ${_timeLeft(msg.locationExpiresAt!)}',
                        style: TextStyle(
                            fontSize: 10,
                            color: mine ? _myBubbleTextColor.withValues(alpha: 0.6) : AppTheme.cutMuted)),
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
                  foregroundColor: mine ? _myBubbleTextColor : Colors.teal,
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
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 40),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.location_on, color: Colors.teal, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Text(msg.locationAddress ?? 'Live Location',
                              style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700))),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, size: 20),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ]),
                    if (msg.locationExpiresAt != null) ...[
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 42),
                        child: Text(
                            'Expires at ${msg.locationExpiresAt!.hour.toString().padLeft(2, '0')}:${msg.locationExpiresAt!.minute.toString().padLeft(2, '0')}',
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.cutMuted)),
                      ),
                    ],
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 340,
                        width: double.infinity,
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(msg.locationLat!, msg.locationLng!),
                            zoom: 16,
                          ),
                          markers: {
                            Marker(
                              markerId: const MarkerId('shared_location'),
                              position: LatLng(msg.locationLat!, msg.locationLng!),
                              infoWindow: InfoWindow(
                                  title: msg.locationAddress ?? 'Shared location'),
                            ),
                          },
                          zoomControlsEnabled: true,
                          zoomGesturesEnabled: true,
                          scrollGesturesEnabled: true,
                          rotateGesturesEnabled: true,
                          tiltGesturesEnabled: true,
                          myLocationButtonEnabled: false,
                          mapToolbarEnabled: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Text(
                          '${msg.locationLat!.toStringAsFixed(5)}, ${msg.locationLng!.toStringAsFixed(5)}',
                          style: const TextStyle(
                              fontSize: 11, color: AppTheme.cutMuted)),
                    ),
                    SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                            onPressed: _openMaps,
                            icon: const Icon(Icons.open_in_new, size: 18),
                            label: const Text('Open in Google Maps app'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ))),
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

// ─── Quoted-reply snippet — shown inside a bubble that is a reply ─────
class _ReplyQuote extends StatelessWidget {
  final GroupMessage msg;
  final bool mine;
  final bool dense;
  const _ReplyQuote({required this.msg, required this.mine, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final bg = dense
        ? Colors.black.withValues(alpha: 0.35)
        : (mine
            ? _myBubbleBorder.withValues(alpha: 0.4)
            : AppTheme.cutGrey);
    final textColor = dense
        ? Colors.white
        : (mine ? _myBubbleTextColor : AppTheme.cutDark);
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        border: Border(
            left: BorderSide(
                color: dense ? Colors.white70 : AppTheme.cutBlue, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(msg.replyToSenderName ?? 'Message',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: dense ? Colors.white : AppTheme.cutBlue)),
          Text(msg.replyToText ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 11,
                  color: textColor.withValues(alpha: 0.85))),
        ],
      ),
    );
  }
}


class _ReplyPreviewBar extends StatelessWidget {
  final String userName;
  final String preview;
  final VoidCallback onCancel;
  const _ReplyPreviewBar(
      {required this.userName, required this.preview, required this.onCancel});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: const BoxDecoration(
            color: Color(0xFFF0F7FF),
            border: Border(top: BorderSide(color: AppTheme.cutBorder))),
        child: Row(children: [
          Container(width: 3, height: 34, color: AppTheme.cutBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Replying to $userName',
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.cutBlue)),
                Text(preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.cutMuted)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppTheme.cutMuted),
            onPressed: onCancel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ]),
      );
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
