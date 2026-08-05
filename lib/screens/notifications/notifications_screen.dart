import '../profile/user_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/connection_model.dart';
import '../../providers/user_provider.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';


class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = context.watch<UserProvider>().user?.id ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: StreamBuilder<List<ConnectionRequest>>(
        stream: FirebaseService.instance.incomingRequestsStream(uid),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final requests = snap.data ?? [];
          if (requests.isEmpty) {
            return const EmptyState(
              icon: Icons.notifications_none,
              title: 'No Notifications',
              subtitle: 'Connection requests will appear here.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: requests.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
            itemBuilder: (_, i) => _RequestTile(request: requests[i], myUid: uid),
          );
        },
      ),
    );
  }
}

class _RequestTile extends StatefulWidget {
  final ConnectionRequest request; final String myUid;
  const _RequestTile({required this.request, required this.myUid});
  @override
  State<_RequestTile> createState() => _RequestTileState();
}

class _RequestTileState extends State<_RequestTile> {
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      await FirebaseService.instance.acceptConnectionRequest(widget.request.fromUid, widget.myUid);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('You are now connected with ${widget.request.fromName}.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decline() async {
    setState(() => _busy = true);
    try {
      await FirebaseService.instance.declineConnectionRequest(widget.request.fromUid, widget.myUid);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.request;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: GestureDetector(
        onTap: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => UserProfileScreen(userId: r.fromUid))),
        child: UserAvatar(photoUrl: r.fromPhotoUrl,
            initials: r.fromName.isNotEmpty ? r.fromName[0].toUpperCase() : '?', radius: 22),
      ),
      title: RichText(
        text: TextSpan(style: const TextStyle(color: AppTheme.cutDark, fontSize: 13), children: [
          TextSpan(text: r.fromName, style: const TextStyle(fontWeight: FontWeight.w700)),
          const TextSpan(text: ' wants to connect with you'),
        ]),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Expanded(child: ElevatedButton(
            onPressed: _busy ? null : _accept,
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cutBlue, minimumSize: const Size(0, 34)),
            child: _busy
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Accept', style: TextStyle(fontSize: 12)),
          )),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton(
            onPressed: _busy ? null : _decline,
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.cutMuted, minimumSize: const Size(0, 34)),
            child: const Text('Decline', style: TextStyle(fontSize: 12)),
          )),
        ]),
      ),
    );
  }
}
