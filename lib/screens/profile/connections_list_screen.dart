import 'package:flutter/material.dart';
import '../../models/user_model.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/verified_badge.dart';
import 'user_profile_screen.dart';

/// Shown when a profile's connection count is tapped — lists everyone
/// that user is connected to, live.
class ConnectionsListScreen extends StatelessWidget {
  final String userId;
  final String displayName;
  const ConnectionsListScreen({super.key, required this.userId, required this.displayName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("$displayName's Connections")),
      body: StreamBuilder<List<String>>(
        stream: FirebaseService.instance.connectionIdsStream(userId),
        builder: (_, idSnap) {
          if (idSnap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final ids = idSnap.data ?? [];
          if (ids.isEmpty) {
            return const EmptyState(
              icon: Icons.people_outline,
              title: 'No Connections Yet',
              subtitle: 'Connections made will appear here.',
            );
          }
          return FutureBuilder<List<UserModel>>(
            future: FirebaseService.instance.getUsers(ids),
            builder: (_, userSnap) {
              if (userSnap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              final users = userSnap.data ?? [];
              if (users.isEmpty) {
                return const EmptyState(
                  icon: Icons.people_outline,
                  title: 'No Connections Yet',
                  subtitle: 'Connections made will appear here.',
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: users.length,
                separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                itemBuilder: (_, i) {
                  final u = users[i];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    leading: UserAvatar(photoUrl: u.photoUrl,
                        initials: u.name.isNotEmpty ? u.name[0].toUpperCase() : '?', radius: 22),
                    title: NameWithBadge(name: u.name, isVerified: u.isVerified,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    subtitle: Text(u.campus, style: const TextStyle(fontSize: 12, color: AppTheme.cutMuted)),
                    trailing: const Icon(Icons.chevron_right, color: AppTheme.cutMuted),
                    onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => UserProfileScreen(userId: u.id))),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
