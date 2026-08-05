import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/user_model.dart';
import '../../models/alert_model.dart';
import '../../models/group_model.dart';
import '../../providers/user_provider.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/verified_badge.dart';
import '../../widgets/connection_button.dart';
import 'profile_screen.dart';

const double _kCoverHeight = 130;
const double _kAvatarDiameter = 84;
// Shared "beautiful size" for the connections pill / campus pill / connect
// button, so all three read as one consistent row of chips.
const double _kChipHeight = 34;

/// EXTEND: tapping any user's avatar throughout the app now navigates
/// here instead of doing nothing / just showing a mini popup.
class UserProfileScreen extends StatelessWidget {
  final String userId;
  const UserProfileScreen({super.key, required this.userId});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<UserProvider>().user;

    // FIX: if the signed-in user taps their OWN avatar anywhere in the
    // app (feed, chat, member list, etc.), they were being shown this
    // read-only "visitor" profile screen — which correctly hides the
    // Connect button for yourself, but gave the impression of "no connect
    // button = broken". The owner should never see the visitor view of
    // their own profile; route them straight to the real ProfileScreen
    // (with settings, edit profile, sign out, etc.) instead.
    if (me != null && me.id == userId) {
      return const ProfileScreen();
    }

    return FutureBuilder<UserModel?>(
      future: FirebaseService.instance.getUser(userId),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data;
        if (user == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('User not found')),
          );
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(user.name),
            centerTitle: false,
          ),
          body: _ProfileContent(user: user, me: me),
        );
      },
    );
  }
}

class _ProfileContent extends StatefulWidget {
  final UserModel user;
  final UserModel? me;
  const _ProfileContent({required this.user, required this.me});
  @override
  State<_ProfileContent> createState() => _ProfileContentState();
}

class _ProfileContentState extends State<_ProfileContent>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final me = widget.me;

    // FIX: the previous layout used SliverAppBar(expandedHeight: 260) with
    // a FlexibleSpaceBar whose content (avatar + name + badge + campus
    // chip + connection count + connect button) could exceed 260px,
    // producing a "BOTTOM OVERFLOWED" render error. Because that overflow
    // happened inside the sliver's fixed-height box, it corrupted the
    // sliver layout math below it — which is why the TabBar/TabBarView
    // (Alerts tab, post button) appeared broken or missing entirely.
    //
    // Fixed by replacing the fixed-height SliverAppBar+FlexibleSpaceBar
    // with a content-sized SliverToBoxAdapter header (grows to fit
    // whatever content it has, no overflow possible) followed by a
    // separately pinned SliverPersistentHeader for the TabBar.
    return NestedScrollView(
      headerSliverBuilder: (_, __) => [
        SliverToBoxAdapter(child: _ProfileHeader(user: user, me: me)),
        SliverPersistentHeader(
          pinned: true,
          delegate: _TabBarDelegate(TabBar(
            controller: _tabs,
            labelColor: AppTheme.cutBlue,
            unselectedLabelColor: AppTheme.cutMuted,
            indicatorColor: AppTheme.cutBlue,
            indicatorWeight: 3,
            tabs: const [Tab(text: 'Alerts'), Tab(text: 'Updates')],
          )),
        ),
      ],
      body: TabBarView(controller: _tabs, children: [
        _UserAlertsTab(userId: user.id),
        _UserUpdatesTab(userId: user.id),
      ]),
    );
  }
}

// ── LinkedIn-style header: cover photo top, avatar overlapping the cover's
// bottom edge by half its height on the left, then a text column to the
// RIGHT of the avatar with name/badge, a connections-pill + Connect-button
// row, and a campus pill row underneath — all sized to match. ──
class _ProfileHeader extends StatelessWidget {
  final UserModel user;
  final UserModel? me;
  const _ProfileHeader({required this.user, required this.me});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover photo + overlapping avatar
          SizedBox(
            height: _kCoverHeight,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: _kCoverHeight,
                  child: (user.coverPhotoUrl != null &&
                          user.coverPhotoUrl!.isNotEmpty)
                      ? CachedNetworkImage(
                          imageUrl: user.coverPhotoUrl!,
                          cacheKey: user.coverPhotoUrl,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (_, __) => _fallbackCover(),
                          errorWidget: (_, __, ___) => _fallbackCover(),
                        )
                      : _fallbackCover(),
                ),
                Positioned(
                  left: 20,
                  top: _kCoverHeight - _kAvatarDiameter - 12,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: UserAvatar(
                        photoUrl: user.photoUrl,
                        initials: user.initials,
                        radius: _kAvatarDiameter / 2 - 3),
                  ),
                ),
              ],
            ),
          ),
          // Info column — starts to the right of the avatar.
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  children: [
                    Text(user.name,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w700)),
                    if (user.isVerified) const VerifiedBadge(size: 16),
                  ]),
              const SizedBox(height: 10),
              // Connections pill + Connect button — "next to it", same size.
              Wrap(spacing: 8, runSpacing: 8, children: [
                _InfoPill(icon: Icons.school_outlined, label: user.campus),
                StreamBuilder<int>(
                  stream:
                      FirebaseService.instance.connectionCountStream(user.id),
                  builder: (_, snap) {
                    final count = snap.data ?? 0;
                    return _InfoPill(
                      icon: Icons.people_outline,
                      label: '$count connection${count == 1 ? '' : 's'}',
                    );
                  },
                ),
              ]),
              if (me != null) ...[
                const SizedBox(height: 12),
                Center(
                  child: SizedBox(
                    height: _kChipHeight,
                    child: ConnectionButton(
                      meUid: user.id,
                      meName: user.name,
                      mePhotoUrl: user.photoUrl,
                      otherUid: user.id,
                      otherName: user.name,
                      otherPhotoUrl: user.photoUrl,
                    ),
                  ),
                ),
              ],
            ]),
          ),
        ],
      );

  Widget _fallbackCover() => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.cutBlue, Color(0xFF002878)],
          ),
        ),
      );
}

/// Consistent pill used for both the connections count and the campus —
/// same height/padding/font as the Connect button beside it.
class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill({required this.icon, required this.label});
  @override
  Widget build(BuildContext context) => Container(
        height: _kChipHeight,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
            color: AppTheme.cutGrey,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.cutBorder)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: AppTheme.cutMuted),
          const SizedBox(width: 6),
          Text(label,
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.cutDark)),
        ]),
      );
}

// Pinned TabBar delegate for SliverPersistentHeader.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
          BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: Colors.white, child: tabBar);

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) =>
      tabBar != oldDelegate.tabBar;
}

class _UserAlertsTab extends StatelessWidget {
  final String userId;
  const _UserAlertsTab({required this.userId});
  @override
  Widget build(BuildContext context) => StreamBuilder<List<AlertModel>>(
        stream: FirebaseService.instance.userAlertsStream(userId),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (snap.hasError)
            return Center(
                child: Text('Could not load alerts: ${snap.error}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.cutMuted)));
          final alerts = snap.data ?? [];
          if (alerts.isEmpty)
            return const EmptyState(
                icon: Icons.warning_amber_outlined,
                title: 'No Alerts',
                subtitle: 'This user has not posted any alerts.');
          return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: alerts.length,
              itemBuilder: (_, i) {
                final a = alerts[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              CategoryBadge(
                                  label: a.category.label,
                                  color: AppTheme.cutRed),
                              const Spacer(),
                              Text(DateFormat('d MMM y').format(a.createdAt),
                                  style: const TextStyle(
                                      fontSize: 11, color: AppTheme.cutMuted)),
                            ]),
                            const SizedBox(height: 8),
                            Text(a.title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(height: 4),
                            Text(a.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12)),
                          ])),
                );
              });
        },
      );
}

class _UserUpdatesTab extends StatelessWidget {
  final String userId;
  const _UserUpdatesTab({required this.userId});
  @override
  Widget build(BuildContext context) => StreamBuilder<List<UpdateModel>>(
        stream: FirebaseService.instance.userUpdatesStream(userId),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (snap.hasError)
            return Center(
                child: Text('Could not load updates: ${snap.error}',
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.cutMuted)));
          final updates = snap.data ?? [];
          if (updates.isEmpty)
            return const EmptyState(
                icon: Icons.campaign_outlined,
                title: 'No Updates',
                subtitle: 'This user has not posted any updates.');
          return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: updates.length,
              itemBuilder: (_, i) {
                final u = updates[i];
                return Card(
                  margin:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(DateFormat('d MMM y').format(u.createdAt),
                                style: const TextStyle(
                                    fontSize: 11, color: AppTheme.cutMuted)),
                            const SizedBox(height: 6),
                            Text(u.content,
                                style:
                                    const TextStyle(fontSize: 13, height: 1.4)),
                          ])),
                );
              });
        },
      );
}
