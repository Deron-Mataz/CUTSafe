import 'package:flutter/material.dart';
import '../../models/group_model.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

/// Allows group admins to approve or decline pending join requests.
class JoinRequestsScreen extends StatelessWidget {
  final GroupModel group;
  const JoinRequestsScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final svc = FirebaseService.instance;

    return Scaffold(
      appBar: AppBar(title: Text('Requests — ${group.name}')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: svc.joinRequestsStream(group.id),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final requests = snap.data ?? [];
          if (requests.isEmpty) {
            return const EmptyState(
              icon: Icons.person_add_outlined,
              title: 'No Pending Requests',
              subtitle: 'All join requests will appear here.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: requests.length,
            itemBuilder: (_, i) {
              final r = requests[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppTheme.cutBlue.withValues(alpha: 0.12),
                    child: Text(
                      (r['userName'] as String? ?? '?').isNotEmpty
                          ? (r['userName'] as String)[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                          color: AppTheme.cutBlue, fontWeight: FontWeight.w700),
                    ),
                  ),
                  title: Text(r['userName'] as String? ?? 'Unknown',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('Wants to join ${group.name}',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.cutMuted)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    // Decline
                    IconButton(
                      icon: const Icon(Icons.close, color: AppTheme.cutRed),
                      tooltip: 'Decline',
                      onPressed: () {
                        svc.declineRequest(group.id, r['uid'] as String);
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Request declined.')));
                      },
                    ),
                    // Approve
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      tooltip: 'Approve',
                      onPressed: () {
                        svc.approveRequest(group.id, r['uid'] as String);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(
                                '${r['userName']} approved and added to the group.')));
                      },
                    ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
