import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/alert_model.dart';
import '../../providers/alert_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/report_dialog.dart';
import '../../widgets/verified_badge.dart';
import '../map/map_screen.dart';
import '../profile/user_profile_screen.dart';
import '../notifications/notifications_screen.dart';
import 'post_alert_sheet.dart';
import 'post_update_sheet.dart';

class AlertsScreen extends StatefulWidget {
  const AlertsScreen({super.key});
  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  AlertCategory? _filter;
  bool    _nearMeOnly = false;
  double? _myLat, _myLng;

  // FIX: feed refreshes every 5 seconds (recalculates distances/timestamps;
  // Firestore streams are already live, this also re-pulls GPS position).
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _fetchMyPosition();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchMyPosition());
  }

  @override
  void dispose() { _tabs.dispose(); _refreshTimer?.cancel(); super.dispose(); }

  Future<void> _fetchMyPosition() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition();
      if (mounted) setState(() { _myLat = pos.latitude; _myLng = pos.longitude; });
    } catch (_) {}
  }

  Future<void> _manualRefresh() async {
    await _fetchMyPosition();
    if (mounted) setState(() {});
  }

  void _showPostOptions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 8),
          Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(color: AppTheme.cutBorder, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 4),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFFFEBEE), child: Icon(Icons.warning_amber_rounded, color: AppTheme.cutRed)),
            title: const Text('Post an Alert', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Report an incident or crime'),
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(context: context, isScrollControlled: true,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => const PostAlertSheet());
            },
          ),
          ListTile(
            leading: const CircleAvatar(backgroundColor: Color(0xFFE3F2FD), child: Icon(Icons.campaign_outlined, color: AppTheme.cutBlue)),
            title: const Text('Post an Update', style: TextStyle(fontWeight: FontWeight.w600)),
            subtitle: const Text('Share a safety tip or information'),
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(context: context, isScrollControlled: true,
                  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                  builder: (_) => const PostUpdateSheet());
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setModal) => SafeArea(
        child: Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Filter Alerts', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_filter != null || _nearMeOnly)
                TextButton(onPressed: () { setState(() { _filter = null; _nearMeOnly = false; }); setModal(() {}); Navigator.pop(ctx); }, child: const Text('Clear All')),
            ]),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero, title: const Text('Near Me Only'),
              subtitle: Text(_myLat == null ? 'Location not available' : 'Show alerts within 2 km of you'),
              value: _nearMeOnly, activeThumbColor: AppTheme.cutBlue,
              onChanged: _myLat == null ? null : (v) { setState(() => _nearMeOnly = v); setModal(() {}); },
            ),
            const Divider(), const SizedBox(height: 8),
            const Text('Category', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _FChip(label: 'All', selected: _filter == null, color: AppTheme.cutBlue,
                  onTap: () { setState(() => _filter = null); setModal(() {}); Navigator.pop(ctx); }),
              ...[AlertCategory.crime, AlertCategory.medical, AlertCategory.hazard, AlertCategory.sos, AlertCategory.other]
                  .map((c) => _FChip(label: c.label, selected: _filter == c, color: _catColor(c),
                      onTap: () { setState(() => _filter = c); setModal(() {}); Navigator.pop(ctx); })),
            ]),
            const SizedBox(height: 8),
          ]),
        ),
      )),
    );
  }

  Color _catColor(AlertCategory c) => switch (c) {
    AlertCategory.crime   => AppTheme.cutRed,
    AlertCategory.medical => Colors.teal,
    AlertCategory.hazard  => Colors.orange,
    AlertCategory.sos     => AppTheme.cutRed,
    AlertCategory.other   => AppTheme.cutMuted,
  };

  @override
  Widget build(BuildContext context) {
    final hasFilter = _filter != null || _nearMeOnly;
    final prov      = context.watch<AlertProvider>();
    final sosCount  = prov.activeSOS.length;
    final myUid     = context.watch<UserProvider>().user?.id ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Safety Feed'),
          if (sosCount > 0)
            Text('$sosCount SOS ACTIVE', style: const TextStyle(fontSize: 11, color: Colors.yellowAccent, fontWeight: FontWeight.w700)),
        ]),
        actions: [
          // NEW: manual refresh icon (dropdown-refresh alongside pull-to-refresh)
          IconButton(icon: const Icon(Icons.refresh), tooltip: 'Refresh', onPressed: _manualRefresh),
          AnimatedBuilder(
            animation: _tabs,
            builder: (_, __) => _tabs.index == 0
                ? IconButton(icon: Icon(Icons.filter_list, color: hasFilter ? Colors.yellowAccent : Colors.white), onPressed: _showFilterSheet)
                : const SizedBox.shrink(),
          ),
          // NEW: notification bell with live pending-request badge
          if (myUid.isNotEmpty)
            StreamBuilder<int>(
              stream: FirebaseService.instance.incomingRequestCountStream(myUid),
              builder: (_, snap) {
                final count = snap.data ?? 0;
                return Stack(clipBehavior: Clip.none, children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotificationsScreen())),
                  ),
                  if (count > 0)
                    Positioned(right: 6, top: 6,
                      child: Container(padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(color: AppTheme.cutRed, shape: BoxShape.circle),
                        constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                        child: Text('$count', textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)))),
                ]);
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabs, labelColor: Colors.white, unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white, indicatorWeight: 3,
          tabs: const [Tab(text: 'Alerts'), Tab(text: 'Updates')],
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: _showPostOptions, backgroundColor: AppTheme.cutRed, child: const Icon(Icons.add, color: Colors.white)),
      body: TabBarView(controller: _tabs, children: [
        RefreshIndicator(onRefresh: _manualRefresh,
          child: _AlertsFeed(filter: _filter, nearMeOnly: _nearMeOnly, myLat: _myLat, myLng: _myLng, catColor: _catColor)),
        RefreshIndicator(onRefresh: _manualRefresh, child: const _UpdatesFeed()),
      ]),
    );
  }
}

// ─── Alerts Feed ──────────────────────────────────────────────────
class _AlertsFeed extends StatelessWidget {
  final AlertCategory? filter;
  final bool nearMeOnly;
  final double? myLat, myLng;
  final Color Function(AlertCategory) catColor;
  const _AlertsFeed({this.filter, required this.nearMeOnly, this.myLat, this.myLng, required this.catColor});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AlertProvider>();
    final uid  = context.watch<UserProvider>().user?.id ?? '';
    var list   = prov.alerts;
    if (filter != null) list = list.where((a) => a.category == filter).toList();
    if (nearMeOnly && myLat != null && myLng != null) {
      list = list.where((a) {
        if (!a.hasCoords) return false;
        return Geolocator.distanceBetween(myLat!, myLng!, a.latitude!, a.longitude!) <= 2000;
      }).toList();
    }
    if (list.isEmpty) {
      return ListView(children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.6,
          child: EmptyState(icon: Icons.warning_amber_outlined,
              title: nearMeOnly ? 'No Nearby Alerts' : 'No Alerts',
              subtitle: nearMeOnly ? 'No incidents within 2 km of you.' : 'Tap + to report an incident.')),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      itemBuilder: (_, i) {
        final alert = list[i];
        if (alert.isSOS) return _SOSCard(alert: alert, uid: uid);
        return _AlertCard(alert: alert, uid: uid, myLat: myLat, myLng: myLng, catColor: catColor);
      },
    );
  }
}

// ─── SOS Card ─────────────────────────────────────────────────────
class _SOSCard extends StatelessWidget {
  final AlertModel alert; final String uid;
  const _SOSCard({required this.alert, required this.uid});
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AlertProvider>();
    final isOwner = alert.userId == uid;
    final isSafe = alert.isSOSSafe;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: isSafe ? Colors.green.withValues(alpha: 0.08) : AppTheme.cutRed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14), border: Border.all(color: isSafe ? Colors.green : AppTheme.cutRed, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(color: isSafe ? Colors.green : AppTheme.cutRed, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
          child: Row(children: [
            Icon(isSafe ? Icons.check_circle : Icons.emergency, color: Colors.white, size: 20), const SizedBox(width: 8),
            Expanded(child: Text(isSafe ? '✅ SOS — ${alert.userName} is now SAFE' : '🚨 SOS ACTIVE — ${alert.userName} needs help!',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13))),
            TimeAgoText(alert.createdAt, style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
        Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(alert.description, style: const TextStyle(fontSize: 13, height: 1.4)),
          if (alert.location != null) ...[const SizedBox(height: 8), LocationRow(alert.location!)],
          if (alert.assignedOfficerName != null && alert.assignedOfficerName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(children: [const Icon(Icons.shield_outlined, size: 13, color: AppTheme.cutBlue), const SizedBox(width: 4),
              Text('${alert.assignedOfficerName} responding', style: const TextStyle(fontSize: 12, color: AppTheme.cutBlue, fontWeight: FontWeight.w500))]),
          ],
          const SizedBox(height: 14),
          Row(children: [
            if (alert.hasCoords) Expanded(child: OutlinedButton.icon(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapScreen(focusTarget: LatLng(alert.latitude!, alert.longitude!), focusLabel: '🚨 SOS — ${alert.userName}'))),
              icon: const Icon(Icons.map_outlined, size: 15), label: const Text('View on Map', style: TextStyle(fontSize: 12)),
              style: OutlinedButton.styleFrom(foregroundColor: AppTheme.cutBlue, side: const BorderSide(color: AppTheme.cutBlue), minimumSize: const Size(0, 36)))),
            if (alert.hasCoords && isOwner && alert.isSOSActive) const SizedBox(width: 10),
            if (isOwner && alert.isSOSActive) Expanded(child: ElevatedButton.icon(
              onPressed: () => prov.markSOSSafe(alert.id),
              icon: const Icon(Icons.check_circle_outline, size: 15, color: Colors.white), label: const Text("I'm Safe", style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green, minimumSize: const Size(0, 36)))),
          ]),
        ])),
      ]),
    );
  }
}

// ─── Alert Card ───────────────────────────────────────────────────
class _AlertCard extends StatelessWidget {
  final AlertModel alert; final String uid;
  final double? myLat, myLng;
  final Color Function(AlertCategory) catColor;
  const _AlertCard({required this.alert, required this.uid, this.myLat, this.myLng, required this.catColor});

  String? _dist() {
    if (myLat == null || myLng == null || !alert.hasCoords) return null;
    final m = Geolocator.distanceBetween(myLat!, myLng!, alert.latitude!, alert.longitude!);
    return m < 1000 ? '${m.round()} m away' : '${(m / 1000).toStringAsFixed(1)} km away';
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AlertProvider>();
    final isOwner = alert.userId == uid;
    final dist = _dist();
    final cc = catColor(alert.category);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showDetail(context, prov),
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            // FIX: tap navigates to the poster's profile
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: alert.userId))),
              child: UserAvatar(photoUrl: alert.userPhotoUrl, initials: alert.userName.isNotEmpty ? alert.userName[0] : '?'),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // FIX: verified badge next to poster name
              FutureBuilder(
                future: FirebaseService.instance.getUser(alert.userId),
                builder: (_, snap) => NameWithBadge(
                  name: alert.userName, isVerified: snap.data?.isVerified ?? false,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), badgeSize: 12,
                ),
              ),
              Row(children: [
                TimeAgoText(alert.createdAt),
                if (dist != null) ...[
                  const Text(' · ', style: TextStyle(color: AppTheme.cutMuted, fontSize: 12)),
                  Text(dist, style: const TextStyle(color: AppTheme.cutBlue, fontSize: 12, fontWeight: FontWeight.w500)),
                ],
              ]),
            ])),
            CategoryBadge(label: alert.category.label, color: cc),
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.cutMuted),
              onSelected: (v) async {
                if (v == 'delete') _confirmDelete(context, prov);
                if (v == 'report') showReportDialog(context, itemType: 'post', itemId: alert.id, itemName: alert.title);
              },
              itemBuilder: (_) => [
                if (!isOwner) const PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_outlined, size: 18, color: AppTheme.cutRed), SizedBox(width: 8), Text('Report', style: TextStyle(color: AppTheme.cutRed))])),
                if (isOwner) const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: AppTheme.cutRed), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppTheme.cutRed))])),
              ],
            ),
          ]),
          const SizedBox(height: 12),
          Text(alert.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 6),
          Text(alert.description, style: const TextStyle(fontSize: 13, height: 1.4, color: AppTheme.cutDark), maxLines: 3, overflow: TextOverflow.ellipsis),
          if (alert.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(height: 80, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: alert.imageUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ClipRRect(borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(imageUrl: alert.imageUrls[i], width: 80, height: 80, fit: BoxFit.cover)))),
          ],
          if (alert.location != null) ...[const SizedBox(height: 8), LocationRow(alert.location!)],
          const SizedBox(height: 12), const Divider(),
          Row(children: [
            Icon(Icons.check_circle_outline, size: 13, color: alert.isConfirmed ? Colors.green : AppTheme.cutMuted), const SizedBox(width: 3),
            Text('${alert.confirmCount}', style: const TextStyle(fontSize: 12, color: AppTheme.cutMuted)), const SizedBox(width: 10),
            const Icon(Icons.flag_outlined, size: 13, color: AppTheme.cutMuted), const SizedBox(width: 3),
            Text('${alert.reportCount}', style: const TextStyle(fontSize: 12, color: AppTheme.cutMuted)),
            if (alert.isDispatched) ...[const SizedBox(width: 10),
              Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppTheme.cutBlue.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                child: const Text('Officer assigned', style: TextStyle(fontSize: 10, color: AppTheme.cutBlue, fontWeight: FontWeight.w600)))],
            const Spacer(),
            const Text('Tap for details', style: TextStyle(fontSize: 11, color: AppTheme.cutMuted)),
          ]),
        ])),
      ),
    );
  }

  void _showDetail(BuildContext context, AlertProvider prov) {
    showModalBottomSheet(context: context, isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (_) => _AlertDetailSheet(alert: alert, uid: uid));
  }

  Future<void> _confirmDelete(BuildContext context, AlertProvider prov) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Delete Alert'), content: const Text('Permanently remove this alert?'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cutRed), onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
    ));
    if (ok == true && context.mounted) prov.deleteAlert(alert.id);
  }
}

// ─── Alert detail sheet ───────────────────────────────────────────
// FIX: previously a DraggableScrollableSheet with generous 0.72 initial
// size and loose spacing made the sheet feel like it required excessive
// scrolling to reach the bottom actions. This is now a plain modal capped
// at 80% of screen height with tightened spacing throughout, so short
// alerts don't force a big empty scroll and the whole thing feels snappier.
class _AlertDetailSheet extends StatelessWidget {
  final AlertModel alert; final String uid;
  const _AlertDetailSheet({required this.alert, required this.uid});
  Color _cc() => switch (alert.category) {
    AlertCategory.crime   => AppTheme.cutRed, AlertCategory.medical => Colors.teal,
    AlertCategory.hazard  => Colors.orange, _ => AppTheme.cutMuted,
  };

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AlertProvider>();
    final reported = prov.hasReported(alert.id);
    final isOwner = alert.userId == uid;
    final maxH = MediaQuery.of(context).size.height * 0.8;

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Center(child: Container(width: 40, height: 4, margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: AppTheme.cutBorder, borderRadius: BorderRadius.circular(2)))),
            Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(color: _cc().withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20), border: Border.all(color: _cc().withValues(alpha: 0.4))),
              child: Text(alert.category.label, style: TextStyle(color: _cc(), fontWeight: FontWeight.w700, fontSize: 12))),
            const SizedBox(height: 10),
            Row(children: [
              GestureDetector(
                onTap: () { Navigator.pop(context); Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: alert.userId))); },
                child: UserAvatar(photoUrl: alert.userPhotoUrl, initials: alert.userName.isNotEmpty ? alert.userName[0] : '?', radius: 20),
              ),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                FutureBuilder(future: FirebaseService.instance.getUser(alert.userId),
                  builder: (_, snap) => NameWithBadge(name: alert.userName, isVerified: snap.data?.isVerified ?? false,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14))),
                Text(DateFormat('d MMM yyyy, HH:mm').format(alert.createdAt), style: const TextStyle(fontSize: 12, color: AppTheme.cutMuted)),
              ]),
            ]),
            const SizedBox(height: 12),
            Text(alert.title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(alert.description, style: const TextStyle(fontSize: 14, height: 1.5, color: AppTheme.cutDark)),
            if (alert.imageUrls.isNotEmpty) ...[
              const SizedBox(height: 12),
              SizedBox(height: 160, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: alert.imageUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(borderRadius: BorderRadius.circular(10),
                  child: CachedNetworkImage(imageUrl: alert.imageUrls[i], height: 160, width: 220, fit: BoxFit.cover)))),
            ],
            if (alert.location != null) ...[const SizedBox(height: 12),
              Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.cutGrey, borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.cutBorder)),
                child: Row(children: [const Icon(Icons.location_on, color: AppTheme.cutBlue, size: 18), const SizedBox(width: 8),
                  Expanded(child: Text(alert.location!, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)))]))],
            if (alert.isDispatched) ...[const SizedBox(height: 10),
              Container(padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppTheme.cutBlue.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(10), border: Border.all(color: AppTheme.cutBlue.withValues(alpha: 0.2))),
                child: Row(children: [const Icon(Icons.shield_outlined, color: AppTheme.cutBlue, size: 18), const SizedBox(width: 8),
                  Expanded(child: Text('${alert.assignedOfficerName} has been assigned to this incident.', style: const TextStyle(fontSize: 13, color: AppTheme.cutBlue)))]))],
            if (alert.hasCoords) ...[const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: OutlinedButton.icon(
                onPressed: () { Navigator.pop(context); Navigator.of(context).push(MaterialPageRoute(builder: (_) => MapScreen(focusTarget: LatLng(alert.latitude!, alert.longitude!), focusLabel: alert.title))); },
                icon: const Icon(Icons.map_outlined), label: const Text('View Location on Map'),
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.cutBlue, side: const BorderSide(color: AppTheme.cutBlue))))],
            const SizedBox(height: 14), const Divider(), const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.check_circle_outline, size: 15, color: alert.isConfirmed ? Colors.green : AppTheme.cutMuted), const SizedBox(width: 5),
              Text('${alert.confirmCount} confirmed', style: const TextStyle(fontSize: 13, color: AppTheme.cutMuted)), const SizedBox(width: 14),
              const Icon(Icons.flag_outlined, size: 15, color: AppTheme.cutMuted), const SizedBox(width: 5),
              Text('${alert.reportCount} reported', style: const TextStyle(fontSize: 13, color: AppTheme.cutMuted)),
            ]),
            const SizedBox(height: 12),
            if (!isOwner) Row(children: [
              Expanded(child: OutlinedButton.icon(
                onPressed: alert.isConfirmed ? null : () { prov.confirmAlert(alert.id, uid); Navigator.pop(context); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Thanks for confirming!'))); },
                icon: Icon(Icons.check_circle_outline, size: 16, color: alert.isConfirmed ? Colors.green : AppTheme.cutBlue),
                label: Text(alert.isConfirmed ? 'Confirmed' : 'I Saw This', style: TextStyle(fontSize: 12, color: alert.isConfirmed ? Colors.green : AppTheme.cutBlue)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), side: BorderSide(color: alert.isConfirmed ? Colors.green : AppTheme.cutBlue)))),
              const SizedBox(width: 10),
              Expanded(child: OutlinedButton.icon(
                onPressed: reported ? null : () { Navigator.pop(context); showReportDialog(context, itemType: 'post', itemId: alert.id, itemName: alert.title); },
                icon: Icon(Icons.flag_outlined, size: 16, color: reported ? AppTheme.cutMuted : AppTheme.cutRed),
                label: Text(reported ? 'Reported' : 'Report', style: TextStyle(fontSize: 12, color: reported ? AppTheme.cutMuted : AppTheme.cutRed)),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), side: BorderSide(color: reported ? AppTheme.cutMuted : AppTheme.cutRed)))),
            ]),
            if (isOwner) SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () async {
                final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                  title: const Text('Delete Alert'), content: const Text('Permanently remove this alert?'),
                  actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cutRed), onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
                ));
                if (ok == true && context.mounted) { prov.deleteAlert(alert.id); Navigator.pop(context); }
              },
              icon: const Icon(Icons.delete_outline, color: AppTheme.cutRed), label: const Text('Delete Alert', style: TextStyle(color: AppTheme.cutRed)),
              style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40), side: const BorderSide(color: AppTheme.cutRed)))),
          ]),
        ),
      ),
    );
  }
}

// ─── Updates Feed ─────────────────────────────────────────────────
class _UpdatesFeed extends StatelessWidget {
  const _UpdatesFeed();
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AlertProvider>();
    final uid  = context.watch<UserProvider>().user?.id ?? '';
    if (prov.updates.isEmpty) {
      return ListView(children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.6,
            child: const EmptyState(icon: Icons.campaign_outlined, title: 'No Updates Yet', subtitle: 'Tap + to share a safety tip.')),
      ]);
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: prov.updates.length,
      itemBuilder: (_, i) {
        final u = prov.updates[i];
        final isOwner = u.userId == uid;
        return Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => UserProfileScreen(userId: u.userId))),
              child: UserAvatar(photoUrl: u.userPhotoUrl, initials: u.userName.isNotEmpty ? u.userName[0] : '?'),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FutureBuilder(future: FirebaseService.instance.getUser(u.userId),
                builder: (_, snap) => NameWithBadge(name: u.userName, isVerified: snap.data?.isVerified ?? false,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), badgeSize: 12)),
              TimeAgoText(u.createdAt),
            ])),
            const CategoryBadge(label: 'Update', color: AppTheme.cutBlue),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18, color: AppTheme.cutMuted),
              onSelected: (v) async {
                if (v == 'delete' && context.mounted) {
                  final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
                    title: const Text('Delete Update'), content: const Text('Delete this update?'),
                    actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cutRed), onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
                  ));
                  if (ok == true && context.mounted) context.read<AlertProvider>().deleteUpdate(u.id);
                }
                if (v == 'report') showReportDialog(context, itemType: 'post', itemId: u.id, itemName: 'Update by ${u.userName}');
              },
              itemBuilder: (_) => [
                if (!isOwner) const PopupMenuItem(value: 'report', child: Row(children: [Icon(Icons.flag_outlined, size: 18, color: AppTheme.cutRed), SizedBox(width: 8), Text('Report', style: TextStyle(color: AppTheme.cutRed))])),
                if (isOwner) const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: AppTheme.cutRed), SizedBox(width: 8), Text('Delete', style: TextStyle(color: AppTheme.cutRed))])),
              ],
            ),
          ]),
          const SizedBox(height: 12),
          Text(u.content, style: const TextStyle(fontSize: 13, height: 1.5)),
          if (u.imageUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(height: 80, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: u.imageUrls.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (_, i) => ClipRRect(borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(imageUrl: u.imageUrls[i], width: 80, height: 80, fit: BoxFit.cover)))),
          ],
          if (u.location != null) ...[const SizedBox(height: 8), LocationRow(u.location!)],
        ])));
      },
    );
  }
}

// ─── Filter chip ──────────────────────────────────────────────────
class _FChip extends StatelessWidget {
  final String label; final bool selected; final Color color; final VoidCallback onTap;
  const _FChip({required this.label, required this.selected, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: AnimatedContainer(duration: const Duration(milliseconds: 150), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(color: selected ? color : color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : color.withValues(alpha: 0.4), width: selected ? 2 : 1)),
      child: Text(label, style: TextStyle(color: selected ? Colors.white : color, fontWeight: FontWeight.w600, fontSize: 13))));
}
