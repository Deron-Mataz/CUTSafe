import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../models/alert_model.dart';
import '../../models/group_model.dart' show UpdateModel;
import '../../models/user_model.dart';
import '../../providers/user_provider.dart';
import '../../providers/alert_provider.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/verified_badge.dart';
import 'connections_list_screen.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart' show kCampuses;

const double _kCoverHeight = 130;
const double _kAvatarDiameter = 84;
// Same "beautiful size" used for profile indicator pills across both screens.
const double _kChipHeight = 34;

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<UserProvider>();

    if (prov.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (prov.user == null) {
      return Scaffold(
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.person_off_outlined, size: 56, color: AppTheme.cutMuted),
          const SizedBox(height: 16),
          const Text('Not signed in', style: TextStyle(fontSize: 16, color: AppTheme.cutMuted)),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false),
            child: const Text('Sign In'),
          ),
        ])),
      );
    }

    return _ProfileBody(user: prov.user!, prov: prov);
  }
}

class _ProfileBody extends StatefulWidget {
  final UserModel user; final UserProvider prov;
  const _ProfileBody({required this.user, required this.prov});
  @override
  State<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends State<_ProfileBody> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  // FIX: About tab removed — it was a duplicate of the Settings screen
  // (same Edit Profile / Change Password / Sign Out entries). Only 2
  // tabs now; the gear icon remains the single way to reach settings.
  @override
  void initState() { super.initState(); _tabs = TabController(length: 2, vsync: this); }
  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  // ── BUG FIX: cover/profile photo updates silently doing nothing ──────
  // The old header lived inside a SliverAppBar's FlexibleSpaceBar, which
  // Flutter rebuilds/re-instantiates aggressively as the sliver scrolls
  // (it drives an opacity/parallax animation on every frame). The picker
  // methods lived on that same short-lived widget and awaited
  // ImagePicker().pickImage(...) — a genuinely slow, user-driven await.
  // By the time the user came back from the camera/gallery, the header
  // widget had very often already been torn down and rebuilt, so the
  // `if (!context.mounted) return;` guard (correctly, defensively) fired
  // and silently aborted — nothing was ever uploaded, no error was shown,
  // and the only visible symptom was the screen quietly redrawing itself.
  //
  // Fix: the whole pick → upload → save flow now lives here, on
  // _ProfileBodyState — a State object that stays mounted for the entire
  // time this screen is on screen, not rebuilt on every scroll frame — so
  // the async gap while the user is in the camera/gallery can never
  // silently invalidate the operation. The header below is now a plain
  // presentational widget that just calls back into these methods.
  Future<void> _showPhotoChooser() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      // FIX (req #5): bottom sheets weren't safe-area aware, so on devices
      // with gesture-nav bars the lowest option could sit underneath the
      // system nav bar. Wrapping every sheet in SafeArea(top: false) below
      // reserves that space.
      builder: (_) => SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: AppTheme.cutBorder, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Align(alignment: Alignment.centerLeft,
                child: Text('Update Photos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700))),
          ),
          const SizedBox(height: 4),
          ListTile(
            leading: const Icon(Icons.account_circle_outlined, color: AppTheme.cutBlue),
            title: const Text('Change Profile Photo'),
            onTap: () => Navigator.pop(context, 'profile'),
          ),
          ListTile(
            leading: const Icon(Icons.image_outlined, color: AppTheme.cutBlue),
            title: const Text('Change Cover Photo'),
            onTap: () => Navigator.pop(context, 'cover'),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (choice == null || !mounted) return;
    await _pickAndUpload(isCover: choice == 'cover');
  }

  Future<void> _pickAndUpload({required bool isCover}) async {
    final source = await _askSource();
    if (source == null || !mounted) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 80);
    if (picked == null || !mounted) return;

    final err = isCover
        ? await widget.prov.updateCoverPhoto(File(picked.path))
        : await widget.prov.updateProfile(photoFile: File(picked.path));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(err ?? (isCover ? 'Cover photo updated!' : 'Profile photo updated!')),
      backgroundColor: err != null ? AppTheme.cutRed : null,
    ));
  }

  Future<ImageSource?> _askSource() => showModalBottomSheet<ImageSource>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 16),
        ListTile(leading: const Icon(Icons.camera_alt_outlined, color: AppTheme.cutBlue), title: const Text('Take a photo'), onTap: () => Navigator.pop(context, ImageSource.camera)),
        ListTile(leading: const Icon(Icons.photo_library_outlined, color: AppTheme.cutBlue), title: const Text('Choose from gallery'), onTap: () => Navigator.pop(context, ImageSource.gallery)),
        const SizedBox(height: 16),
      ]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // Req #1: same NestedScrollView + SliverToBoxAdapter(header) +
    // pinned SliverPersistentHeader(tabs) architecture as UserProfileScreen,
    // instead of the old SliverAppBar/FlexibleSpaceBar. This is also part
    // of the bug fix above — SliverToBoxAdapter content is normal, stable
    // widget tree, not subject to FlexibleSpaceBar's per-frame rebuilds.
    return Scaffold(
      appBar: AppBar(
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Flexible(child: Text(widget.user.name, overflow: TextOverflow.ellipsis)),
          if (widget.user.isVerified) ...[
            const SizedBox(width: 6),
            const VerifiedBadge.onPrimary(size: 16),
          ],
        ]),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.settings_outlined),
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _SettingsScreen(prov: widget.prov)))),
        ],
      ),
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [
          SliverToBoxAdapter(
            child: _ProfileHeaderSelf(user: widget.user, onEditPhotos: _showPhotoChooser),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _TabBarDelegate(TabBar(
              controller: _tabs, labelColor: AppTheme.cutBlue, unselectedLabelColor: AppTheme.cutMuted,
              indicatorColor: AppTheme.cutBlue, indicatorWeight: 3,
              tabs: const [Tab(text: 'My Alerts'), Tab(text: 'My Updates')],
            )),
          ),
        ],
        body: TabBarView(controller: _tabs, children: [
          _MyAlertsTab(userId: widget.user.id),
          _MyUpdatesTab(userId: widget.user.id),
        ]),
      ),
    );
  }
}

// ── LinkedIn-style header — identical layout to UserProfileScreen's
// _ProfileHeader (req #1/#2/#3): cover photo top, avatar overlapping the
// cover's bottom edge by half its height on the left, connections pill +
// campus and connections pills under the cover photo. Purely presentational;
// req #5's single edit affordance lives only on the avatar and calls back
// into _ProfileBodyState's stable pick/upload flow. ──
class _ProfileHeaderSelf extends StatelessWidget {
  final UserModel user;
  final VoidCallback onEditPhotos;
  const _ProfileHeaderSelf({required this.user, required this.onEditPhotos});

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Cover photo + overlapping avatar. Req #5: the cover photo itself
      // no longer carries its own edit icon — the avatar's icon is now
      // the single entry point for updating either photo.
      SizedBox(
        height: _kCoverHeight,
        child: Stack(
          children: [
            Positioned(
              left: 0, right: 0, top: 0, height: _kCoverHeight,
              child: (user.coverPhotoUrl != null && user.coverPhotoUrl!.isNotEmpty)
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
              child: Stack(children: [
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: UserAvatar(
                      photoUrl: user.photoUrl, initials: user.initials,
                      radius: _kAvatarDiameter / 2 - 3),
                ),
                Positioned(
                  right: 0, bottom: 0,
                  child: GestureDetector(
                    onTap: onEditPhotos,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: AppTheme.cutBlue, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt_outlined, size: 14, color: Colors.white),
                    ),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
      // Info column — starts to the right of the avatar.
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Campus and connections indicators sit together under the cover.
          Center(
            child: Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
              _InfoPill(icon: Icons.school_outlined, label: user.campus),
              StreamBuilder<int>(
                stream: FirebaseService.instance.connectionCountStream(user.id),
                builder: (_, snap) {
                  final count = snap.data ?? 0;
                  return GestureDetector(
                    onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => ConnectionsListScreen(userId: user.id, displayName: user.name))),
                    child: _InfoPill(icon: Icons.people_outline, label: '$count connection${count == 1 ? '' : 's'}'),
                  );
                },
              ),
            ]),
          ),
        ]),
      ),
    ],
  );

  Widget _fallbackCover() => Container(
    decoration: const BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft, end: Alignment.bottomRight,
        colors: [AppTheme.cutBlue, Color(0xFF002878)],
      ),
    ),
  );
}

/// Same pill used on UserProfileScreen — kept identical here so both
/// screens are visually consistent (req #1).
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
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.cutDark)),
    ]),
  );
}

// Pinned TabBar delegate for SliverPersistentHeader — same pattern as
// UserProfileScreen's.
class _TabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;
  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) =>
      Container(color: Colors.white, child: tabBar);

  @override
  bool shouldRebuild(covariant _TabBarDelegate oldDelegate) => tabBar != oldDelegate.tabBar;
}

class _MyAlertsTab extends StatelessWidget {
  final String userId;
  const _MyAlertsTab({required this.userId});
  @override
  Widget build(BuildContext context) => StreamBuilder<List<AlertModel>>(
    stream: FirebaseService.instance.userAlertsStream(userId),
    builder: (_, snap) {
      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return Center(child: Text('Could not load alerts: ${snap.error}', style: const TextStyle(fontSize: 12, color: AppTheme.cutMuted)));
      final alerts = snap.data ?? [];
      if (alerts.isEmpty) return const EmptyState(icon: Icons.warning_amber_outlined, title: 'No Alerts Yet', subtitle: 'Your posted alerts will appear here.');
      return ListView.builder(padding: const EdgeInsets.symmetric(vertical: 8), itemCount: alerts.length, itemBuilder: (_, i) => _AlertTile(alert: alerts[i]));
    },
  );
}

class _AlertTile extends StatelessWidget {
  final AlertModel alert;
  const _AlertTile({required this.alert});
  Color _cc() => switch (alert.category) {
    AlertCategory.crime => AppTheme.cutRed, AlertCategory.medical => Colors.teal,
    AlertCategory.hazard => Colors.orange, AlertCategory.sos => AppTheme.cutRed, AlertCategory.other => AppTheme.cutMuted,
  };
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        CategoryBadge(label: alert.category.label, color: _cc()),
        const Spacer(),
        Text(DateFormat('d MMM y').format(alert.createdAt), style: const TextStyle(fontSize: 11, color: AppTheme.cutMuted)),
        if (alert.isSOS) ...[const SizedBox(width: 8),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: alert.isSOSActive ? AppTheme.cutRed : Colors.green, borderRadius: BorderRadius.circular(6)),
              child: Text(alert.isSOSActive ? 'ACTIVE' : 'SAFE', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w700)))],
      ]),
      const SizedBox(height: 8),
      Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      const SizedBox(height: 4),
      Text(alert.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppTheme.cutDark)),
      if (alert.location != null) ...[const SizedBox(height: 6), LocationRow(alert.location!)],
      const SizedBox(height: 8),
      Row(children: [
        const Icon(Icons.check_circle_outline, size: 13, color: AppTheme.cutMuted), const SizedBox(width: 4),
        Text('${alert.confirmCount}', style: const TextStyle(fontSize: 11, color: AppTheme.cutMuted)), const SizedBox(width: 10),
        const Icon(Icons.flag_outlined, size: 13, color: AppTheme.cutMuted), const SizedBox(width: 4),
        Text('${alert.reportCount}', style: const TextStyle(fontSize: 11, color: AppTheme.cutMuted)),
        const Spacer(),
        GestureDetector(
          onTap: () async {
            final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
              title: const Text('Delete Alert?'), content: const Text('This will permanently remove this alert.'),
              actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cutRed), onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
            ));
            if (ok == true && context.mounted) context.read<AlertProvider>().deleteAlert(alert.id);
          },
          child: const Icon(Icons.delete_outline, size: 16, color: AppTheme.cutMuted),
        ),
      ]),
    ])),
  );
}

class _MyUpdatesTab extends StatelessWidget {
  final String userId;
  const _MyUpdatesTab({required this.userId});
  @override
  Widget build(BuildContext context) => StreamBuilder<List<UpdateModel>>(
    stream: FirebaseService.instance.userUpdatesStream(userId),
    builder: (_, snap) {
      if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
      if (snap.hasError) return Center(child: Text('Could not load updates: ${snap.error}', style: const TextStyle(fontSize: 12, color: AppTheme.cutMuted)));
      final updates = snap.data ?? [];
      if (updates.isEmpty) return const EmptyState(icon: Icons.campaign_outlined, title: 'No Updates Yet', subtitle: 'Your posted updates will appear here.');
      return ListView.builder(padding: const EdgeInsets.symmetric(vertical: 8), itemCount: updates.length, itemBuilder: (_, i) => _UpdateTile(update: updates[i]));
    },
  );
}

class _UpdateTile extends StatelessWidget {
  final UpdateModel update;
  const _UpdateTile({required this.update});
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const CategoryBadge(label: 'Update', color: AppTheme.cutBlue), const Spacer(),
        Text(DateFormat('d MMM y').format(update.createdAt), style: const TextStyle(fontSize: 11, color: AppTheme.cutMuted)),
      ]),
      const SizedBox(height: 8),
      Text(update.content, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, height: 1.4)),
      if (update.location != null) ...[const SizedBox(height: 6), LocationRow(update.location!)],
      const SizedBox(height: 8),
      Align(alignment: Alignment.centerRight, child: GestureDetector(
        onTap: () async {
          final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
            title: const Text('Delete Update?'), content: const Text('This will permanently remove this update.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cutRed), onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
          ));
          if (ok == true && context.mounted) context.read<AlertProvider>().deleteUpdate(update.id);
        },
        child: const Icon(Icons.delete_outline, size: 16, color: AppTheme.cutMuted),
      )),
    ])),
  );
}

// Settings screen unchanged — still the single place for Account/Support/Sign Out.
class _SettingsScreen extends StatelessWidget {
  final UserProvider prov;
  const _SettingsScreen({required this.prov});

  @override
  Widget build(BuildContext context) {
    final user = prov.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(children: [
        const SectionHeader('ACCOUNT'),
        _Tile(icon: Icons.edit_outlined, label: 'Edit Profile', onTap: () {
          showModalBottomSheet(context: context, isScrollControlled: true,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              builder: (_) => _EditSheet(provider: prov));
        }),
        const Divider(height: 0, indent: 56),
        _Tile(icon: Icons.lock_outlined, label: 'Change Password', onTap: () {
          if (user != null) prov.sendPasswordReset(user.email);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password reset link sent to your email.')));
        }),
        const Divider(height: 0, indent: 56),
        _Tile(icon: Icons.notifications_outlined, label: 'Notifications', onTap: () => _comingSoon(context)),
        const Divider(height: 0, indent: 56),
        _Tile(icon: Icons.privacy_tip_outlined, label: 'Privacy & Safety', onTap: () => _comingSoon(context)),
        const SectionHeader('SUPPORT'),
        _Tile(icon: Icons.help_outline, label: 'Help & FAQ', onTap: () => _comingSoon(context)),
        const Divider(height: 0, indent: 56),
        _Tile(icon: Icons.info_outline, label: 'About CUT Safety', onTap: () => showAboutDialog(
          context: context, applicationName: 'CUT Safety', applicationVersion: '1.0.0',
          applicationLegalese: '© 2025 Central University of Technology',
          children: const [SizedBox(height: 12), Text('A community-driven safety platform for CUT students and staff.')],
        )),
        const SizedBox(height: 24),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: () => _signOut(context),
            icon: const Icon(Icons.logout, color: AppTheme.cutRed, size: 18),
            label: const Text('Sign Out', style: TextStyle(color: AppTheme.cutRed, fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: AppTheme.cutRed)),
          )),
        const SizedBox(height: 40),
      ]),
    );
  }

  void _comingSoon(BuildContext context) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Coming soon!')));

  Future<void> _signOut(BuildContext context) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Sign Out'), content: const Text('Are you sure you want to sign out?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cutRed), onPressed: () => Navigator.pop(context, true), child: const Text('Sign Out'))],
    ));
    if (ok != true || !context.mounted) return;
    await prov.signOut();
    if (context.mounted) Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (_) => false);
  }
}

class _Tile extends StatelessWidget {
  final IconData icon; final String label; final VoidCallback onTap;
  const _Tile({required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
    tileColor: Colors.white,
    leading: Icon(icon, color: AppTheme.cutBlue, size: 22),
    title: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
    trailing: const Icon(Icons.chevron_right, color: AppTheme.cutMuted, size: 20),
    onTap: onTap,
  );
}

class _EditSheet extends StatefulWidget {
  final UserProvider provider;
  const _EditSheet({required this.provider});
  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final TextEditingController _name;
  late String _campus;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.provider.user?.name ?? '');
    _campus = widget.provider.user?.campus ?? kCampuses.first;
    if (!kCampuses.contains(_campus)) _campus = kCampuses.first;
  }
  @override
  void dispose() { _name.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final loading = widget.provider.isLoading;
    final bottom  = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(top: false,
      child: Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(color: AppTheme.cutBorder, borderRadius: BorderRadius.circular(2)))),
          const Text('Edit Profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          TextField(controller: _name, decoration: const InputDecoration(labelText: 'Full name', prefixIcon: Icon(Icons.person_outline))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _campus,
            decoration: const InputDecoration(labelText: 'Campus', prefixIcon: Icon(Icons.school_outlined)),
            items: kCampuses.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) { if (v != null) setState(() => _campus = v); },
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: loading ? null : () async {
              final err = await widget.provider.updateProfile(name: _name.text, campus: _campus);
              if (!mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err ?? 'Profile updated!'), backgroundColor: err != null ? AppTheme.cutRed : null));
            },
            child: loading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Save Changes'),
          ),
        ])),
    );
  }
}
