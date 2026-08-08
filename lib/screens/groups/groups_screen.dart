import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/group_model.dart';
import '../../providers/group_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/verified_badge.dart';
import 'chat_screen.dart';
import 'create_group_sheet.dart';
import 'join_requests_screen.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key});

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final gp = context.watch<GroupProvider>();
    final uid = context.watch<UserProvider>().user?.id ?? '';
    final sections = _buildSections(gp.groups, uid);
    final hasResults =
        sections.myGroups.isNotEmpty || sections.explore.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Groups')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
          builder: (_) => const CreateGroupSheet(),
        ),
        backgroundColor: AppTheme.cutBlue,
        tooltip: 'Create Group',
        child: const Icon(Icons.group_add, color: Colors.white),
      ),
      body: gp.isLoading && gp.groups.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(slivers: [
              SliverToBoxAdapter(
                  child: _SearchHeader(
                      controller: _searchCtrl, onChanged: _onSearchChanged)),
              if (gp.groups.isEmpty)
                const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                        icon: Icons.group_outlined,
                        title: 'No Groups Yet',
                        subtitle: 'Tap + to create a safety group.'))
              else if (!hasResults)
                const SliverFillRemaining(
                    hasScrollBody: false,
                    child: EmptyState(
                        icon: Icons.search_off_outlined,
                        title: 'No groups found',
                        subtitle: 'Try a different group name or description.'))
              else ...[
                if (sections.myGroups.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader('MY GROUPS')),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _GroupCard(
                          key: ValueKey(sections.myGroups[index].id),
                          group: sections.myGroups[index],
                          uid: uid,
                          isMember: true,
                        ),
                      ),
                      childCount: sections.myGroups.length,
                    ),
                  ),
                ] else if (_query.isEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader('MY GROUPS')),
                  const SliverToBoxAdapter(child: _MyGroupsEmptyState()),
                ],
                if (sections.explore.isNotEmpty) ...[
                  const SliverToBoxAdapter(child: SectionHeader('EXPLORE')),
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _GroupCard(
                          key: ValueKey(sections.explore[index].id),
                          group: sections.explore[index],
                          uid: uid,
                          isMember: false,
                        ),
                      ),
                      childCount: sections.explore.length,
                    ),
                  ),
                ],
                const SliverToBoxAdapter(child: SizedBox(height: 88)),
              ],
            ]),
    );
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }

  _GroupSections _buildSections(List<GroupModel> groups, String uid) {
    final query = _query;
    final visible = query.isEmpty
        ? groups
        : groups.where((g) {
            final haystack = '${g.name} ${g.description}'.toLowerCase();
            return haystack.contains(query);
          }).toList();

    final myGroups = visible.where((g) => g.memberIds.contains(uid)).toList()
      ..sort((a, b) => (b.latestMessageAt ?? b.createdAt)
          .compareTo(a.latestMessageAt ?? a.createdAt));
    final explore = visible
        .where((g) => !g.memberIds.contains(uid) && !g.bannedIds.contains(uid))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    return _GroupSections(myGroups: myGroups, explore: explore);
  }
}

class _GroupSections {
  final List<GroupModel> myGroups;
  final List<GroupModel> explore;
  const _GroupSections({required this.myGroups, required this.explore});
}

class _SearchHeader extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchHeader({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search groups',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: controller.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      controller.clear();
                      onChanged('');
                    },
                  ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.cutBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.cutBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: AppTheme.cutBlue, width: 1.5),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      );
}

class _MyGroupsEmptyState extends StatelessWidget {
  const _MyGroupsEmptyState();

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 14),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppTheme.cutBlue.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.cutBlue.withValues(alpha: 0.12)),
        ),
        child: Column(children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.cutBlue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.travel_explore,
                color: AppTheme.cutBlue, size: 34),
          ),
          const SizedBox(height: 12),
          const Text('Find your community',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
              'Explore CUT groups below and join the ones that matter to you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 13, color: AppTheme.cutMuted, height: 1.4)),
        ]),
      );
}

class _GroupCard extends StatefulWidget {
  final GroupModel group;
  final String uid;
  final bool isMember;
  const _GroupCard(
      {super.key,
      required this.group,
      required this.uid,
      required this.isMember});

  @override
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  bool _joining = false;

  String _unreadLabel(int count) {
    if (count <= 0) return '';
    if (count == 1) return '1 New message';
    if (count >= 9) return '9+ New messages';
    return '$count New messages';
  }

  Future<void> _onTap(BuildContext context) async {
    final group = widget.group;
    final uid = widget.uid;
    if (widget.isMember) {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => ChatScreen(group: group)));
      return;
    }
    if (group.bannedIds.contains(uid)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'You were removed from this group and cannot rejoin without sending a request.'),
        backgroundColor: AppTheme.cutRed,
      ));
      return;
    }

    setState(() => _joining = true);
    String? error;
    if (group.isOpen) {
      error = await context.read<GroupProvider>().joinGroup(group.id, uid);
    } else {
      final user = context.read<UserProvider>().user;
      error = await context
          .read<GroupProvider>()
          .requestJoin(group.id, uid, user?.name ?? 'Unknown');
    }
    if (!mounted) return;
    setState(() => _joining = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ??
          (group.isOpen
              ? 'Joined ${group.name}!'
              : 'Join request sent to the group admin.')),
      backgroundColor: error == null ? null : AppTheme.cutRed,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final uid = widget.uid;
    final isAdmin = group.adminId == uid;
    final isBanned = group.bannedIds.contains(uid);
    final unreadCount = group.unreadCounts[uid] ?? 0;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.isMember ? () => _onTap(context) : null,
        child: Opacity(
          opacity: group.isSuspended ? 0.6 : 1,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              _GroupAvatar(group: group, radius: widget.isMember ? 26 : 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(group.name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14),
                              overflow: TextOverflow.ellipsis),
                        ),
                        if (group.isVerified) ...[
                          const SizedBox(width: 4),
                          const VerifiedBadge(size: 14)
                        ],
                        if (group.isLocked) ...[
                          const SizedBox(width: 4),
                          const Icon(Icons.lock_outline,
                              size: 13, color: Colors.orange)
                        ],
                      ]),
                      const SizedBox(height: 4),
                      Text(
                        widget.isMember
                            ? (group.latestMessage?.trim().isNotEmpty == true
                                ? group.latestMessage!.trim()
                                : 'No messages yet')
                            : group.description,
                        maxLines: widget.isMember ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.cutMuted,
                            height: 1.35),
                      ),
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.people_outline,
                            size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(
                            '${group.memberCount} member${group.memberCount == 1 ? '' : 's'}',
                            style: const TextStyle(
                                fontSize: 11, color: AppTheme.cutMuted)),
                        if (widget.isMember &&
                            group.latestMessageAt != null) ...[
                          const SizedBox(width: 10),
                          TimeAgoText(group.latestMessageAt!,
                              style: const TextStyle(
                                  fontSize: 11, color: AppTheme.cutMuted)),
                        ],
                        if (isAdmin) ...[
                          const SizedBox(width: 8),
                          const _TinyBadge(
                              label: 'Admin', color: AppTheme.cutBlue),
                        ],
                        if (group.isSuspended) ...[
                          const SizedBox(width: 8),
                          const _TinyBadge(
                              label: 'Suspended', color: AppTheme.cutRed),
                        ],
                      ]),
                    ]),
              ),
              const SizedBox(width: 8),
              if (widget.isMember)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MemberMenu(group: group, uid: uid, isAdmin: isAdmin),
                    if (unreadCount > 0)
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        constraints: const BoxConstraints(maxWidth: 108),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppTheme.cutRed,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _unreadLabel(unreadCount),
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                )
              else
                FilledButton(
                  onPressed:
                      isBanned || _joining ? null : () => _onTap(context),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(78, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    backgroundColor: AppTheme.cutBlue,
                  ),
                  child: _joining
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          isBanned
                              ? 'Removed'
                              : (group.isOpen ? 'Join' : 'Request'),
                          style: const TextStyle(fontSize: 12)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _MemberMenu extends StatelessWidget {
  final GroupModel group;
  final String uid;
  final bool isAdmin;
  const _MemberMenu(
      {required this.group, required this.uid, required this.isAdmin});

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.cutMuted),
        onSelected: (v) async {
          if (v == 'open') {
            Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ChatScreen(group: group)));
          } else if (v == 'requests' && isAdmin) {
            Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => JoinRequestsScreen(group: group)));
          } else if (v == 'leave') {
            await _confirmLeave(context);
          } else if (v == 'delete' && isAdmin) {
            await _confirmDelete(context);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
              value: 'open',
              child: Row(children: [
                Icon(Icons.chat_outlined, size: 18),
                SizedBox(width: 8),
                Text('Open Chat')
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
                value: 'leave',
                child: Row(children: [
                  Icon(Icons.exit_to_app, size: 18, color: AppTheme.cutRed),
                  SizedBox(width: 8),
                  Text('Leave Group', style: TextStyle(color: AppTheme.cutRed))
                ])),
          if (isAdmin)
            const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 18, color: AppTheme.cutRed),
                  SizedBox(width: 8),
                  Text('Delete Group', style: TextStyle(color: AppTheme.cutRed))
                ])),
        ],
      );

  Future<void> _confirmLeave(BuildContext context) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text('Leave ${group.name}?'),
              content: const Text('You can re-join this group at any time.'),
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
    if (ok == true && context.mounted)
      context.read<GroupProvider>().leaveGroup(group.id, uid);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: Text('Delete ${group.name}?'),
              content: const Text(
                  'This will permanently delete the group and all messages.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                ElevatedButton(
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cutRed),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete'))
              ],
            ));
    if (ok == true && context.mounted)
      context.read<GroupProvider>().deleteGroup(group.id);
  }
}

class _TinyBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TinyBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(4)),
        child: Text(label,
            style: TextStyle(
                fontSize: 10, color: color, fontWeight: FontWeight.w700)),
      );
}

class _GroupAvatar extends StatelessWidget {
  final GroupModel group;
  final double radius;
  const _GroupAvatar({required this.group, this.radius = 24});

  @override
  Widget build(BuildContext context) {
    if (group.coverUrl != null && group.coverUrl!.isNotEmpty) {
      return ClipOval(
          child: CachedNetworkImage(
              imageUrl: group.coverUrl!,
              width: radius * 2,
              height: radius * 2,
              fit: BoxFit.cover,
              placeholder: (_, __) => _letter(),
              errorWidget: (_, __, ___) => _letter()));
    }
    return _letter();
  }

  Widget _letter() => CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.cutBlue.withValues(alpha: 0.12),
      child: Text(group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
          style: TextStyle(
              color: AppTheme.cutBlue,
              fontWeight: FontWeight.w700,
              fontSize: radius * 0.75)));
}
