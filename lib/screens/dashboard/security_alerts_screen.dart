import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/alert_model.dart';
import '../../providers/alert_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../map/map_screen.dart';
import '../profile/user_profile_screen.dart';

/// Security's own Alerts destination (Requirement #5).
///
/// Reads the exact same `alerts` collection / AlertProvider stream as the
/// Student/Staff AlertsScreen — no separate data source — but presents it
/// with Security-appropriate actions instead of the User actions
/// (confirm/report/post). Mirrors:
///   • SosController (MarkResponding / MarkSafe / Resolve — CanRespondToSOS)
///   • DispatchController.UpdateStatus (accept/complete own assignment;
///     Assign/Unassign/SetPriority remain admin-only and are NOT here)
/// The existing Student/Staff AlertsScreen is completely unchanged.
class SecurityAlertsScreen extends StatefulWidget {
  final int initialTab;
  const SecurityAlertsScreen({super.key, this.initialTab = 0});
  @override
  State<SecurityAlertsScreen> createState() => _SecurityAlertsScreenState();
}

class _SecurityAlertsScreenState extends State<SecurityAlertsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  String? _priorityFilter;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
        length: 2, vsync: this, initialIndex: widget.initialTab);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _showPriorityFilter() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              const Text('Filter by Priority',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_priorityFilter != null)
                TextButton(
                    onPressed: () {
                      setState(() => _priorityFilter = null);
                      Navigator.pop(ctx);
                    },
                    child: const Text('Clear')),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _FilterChip(
                  label: 'All',
                  selected: _priorityFilter == null,
                  color: AppTheme.cutBlue,
                  onTap: () {
                    setState(() => _priorityFilter = null);
                    Navigator.pop(ctx);
                  }),
              ...['critical', 'high', 'medium', 'low'].map((p) => _FilterChip(
                    label: p.toUpperCase(),
                    selected: _priorityFilter == p,
                    color: _priorityColor(p),
                    onTap: () {
                      setState(() => _priorityFilter = p);
                      Navigator.pop(ctx);
                    },
                  )),
            ]),
          ]),
        ),
      ),
    );
  }

  Color _priorityColor(String p) => switch (p) {
        'critical' => AppTheme.cutRed,
        'high' => Colors.orange,
        'low' => AppTheme.cutMuted,
        _ => AppTheme.cutBlue,
      };

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AlertProvider>();
    final sosCount = prov.activeSOS.length;

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Security Alerts'),
          if (sosCount > 0)
            Text('$sosCount SOS ACTIVE',
                style: const TextStyle(
                    fontSize: 11,
                    color: Colors.yellowAccent,
                    fontWeight: FontWeight.w700)),
        ]),
        actions: [
          AnimatedBuilder(
            animation: _tabs,
            builder: (_, __) => _tabs.index == 0
                ? IconButton(
                    icon: Icon(Icons.filter_list,
                        color: _priorityFilter != null
                            ? Colors.yellowAccent
                            : Colors.white),
                    onPressed: _showPriorityFilter)
                : const SizedBox.shrink(),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [Tab(text: 'Incidents'), Tab(text: 'SOS Cases')],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _IncidentsList(priorityFilter: _priorityFilter),
        const _SosCasesList(),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label,
      required this.selected,
      required this.color,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              color: selected ? color : color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: selected ? color : color.withValues(alpha: 0.4),
                  width: selected ? 2 : 1)),
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.white : color,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
      );
}

// ─── Incidents tab ───────────────────────────────────────────────────
class _IncidentsList extends StatelessWidget {
  final String? priorityFilter;
  const _IncidentsList({this.priorityFilter});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AlertProvider>();
    var list = prov.alerts.where((a) => !a.isSOS).toList();
    if (priorityFilter != null) {
      list = list.where((a) => a.priority == priorityFilter).toList();
    }
    list.sort((a, b) {
      const order = {'critical': 0, 'high': 1, 'medium': 2, 'low': 3};
      final pc = (order[a.priority] ?? 2).compareTo(order[b.priority] ?? 2);
      return pc != 0 ? pc : b.createdAt.compareTo(a.createdAt);
    });

    if (list.isEmpty) {
      return const EmptyState(
          icon: Icons.warning_amber_outlined,
          title: 'No Incidents',
          subtitle: 'No incidents match this filter.');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      itemBuilder: (_, i) => _IncidentCard(alert: list[i]),
    );
  }
}

class _IncidentCard extends StatelessWidget {
  final AlertModel alert;
  const _IncidentCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final prov = context.read<AlertProvider>();
    final me = context.read<UserProvider>().user;
    final isMine = alert.assignedOfficerId == me?.id;
    final color = switch (alert.priority) {
      'critical' => AppTheme.cutRed,
      'high' => Colors.orange,
      'low' => AppTheme.cutMuted,
      _ => AppTheme.cutBlue,
    };

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showDetail(context),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => UserProfileScreen(userId: alert.userId))),
                child: UserAvatar(
                    photoUrl: alert.userPhotoUrl,
                    initials: alert.userName.isNotEmpty ? alert.userName[0] : '?'),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(alert.userName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13)),
                    TimeAgoText(alert.createdAt,
                        style:
                            const TextStyle(fontSize: 11, color: AppTheme.cutMuted)),
                  ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(alert.priority.toUpperCase(),
                    style: TextStyle(
                        fontSize: 10, fontWeight: FontWeight.w700, color: color)),
              ),
            ]),
            const SizedBox(height: 10),
            Text(alert.title,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 4),
            Text(alert.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12)),
            if (alert.location != null) ...[
              const SizedBox(height: 8),
              LocationRow(alert.location!),
            ],
            const SizedBox(height: 10),
            Row(children: [
              CategoryBadge(label: alert.category.label, color: AppTheme.cutRed),
              const SizedBox(width: 8),
              if (alert.isClosed)
                const CategoryBadge(label: 'Closed', color: AppTheme.cutMuted)
              else if (alert.isDispatched)
                CategoryBadge(
                    label: alert.dispatchStatus == 'completed'
                        ? 'Completed'
                        : (isMine ? 'Assigned to me' : 'Dispatched'),
                    color: alert.dispatchStatus == 'completed'
                        ? Colors.green
                        : AppTheme.cutBlue)
              else
                const CategoryBadge(label: 'Unassigned', color: AppTheme.cutMuted),
            ]),
            if (isMine && alert.dispatchStatus != 'completed') ...[
              const SizedBox(height: 10),
              Row(children: [
                if (alert.dispatchStatus == 'assigned')
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          prov.updateDispatchStatus(alert.id, 'accepted'),
                      style:
                          ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                      child: const Text('Accept', style: TextStyle(fontSize: 12)),
                    ),
                  ),
                if (alert.dispatchStatus == 'accepted')
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () =>
                          prov.updateDispatchStatus(alert.id, 'completed'),
                      style: ElevatedButton.styleFrom(
                          minimumSize: const Size(0, 36),
                          backgroundColor: Colors.green),
                      child:
                          const Text('Mark Completed', style: TextStyle(fontSize: 12)),
                    ),
                  ),
              ]),
            ],
          ]),
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(alert.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(alert.description, style: const TextStyle(fontSize: 14, height: 1.5)),
            if (alert.location != null) ...[
              const SizedBox(height: 12),
              LocationRow(alert.location!),
            ],
            if (alert.hasCoords) ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MapScreen(
                            focusTarget: LatLng(alert.latitude!, alert.longitude!),
                            focusLabel: alert.title)));
                  },
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('View Location on Map'),
                ),
              ),
            ],
            const SizedBox(height: 14),
            const Divider(),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.check_circle_outline, size: 15, color: AppTheme.cutMuted),
              const SizedBox(width: 5),
              Text('${alert.confirmCount} confirmed',
                  style: const TextStyle(fontSize: 13, color: AppTheme.cutMuted)),
              const SizedBox(width: 14),
              const Icon(Icons.flag_outlined, size: 15, color: AppTheme.cutMuted),
              const SizedBox(width: 5),
              Text('${alert.reportCount} reported',
                  style: const TextStyle(fontSize: 13, color: AppTheme.cutMuted)),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ─── SOS Cases tab ───────────────────────────────────────────────────
class _SosCasesList extends StatelessWidget {
  const _SosCasesList();
  @override
  Widget build(BuildContext context) {
    final prov = context.watch<AlertProvider>();
    final list = prov.alerts.where((a) => a.isSOS).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (list.isEmpty) {
      return const EmptyState(
          icon: Icons.emergency_outlined,
          title: 'No SOS Cases',
          subtitle: 'No SOS alerts have been triggered.');
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: list.length,
      itemBuilder: (_, i) => _SosCaseCard(alert: list[i]),
    );
  }
}

class _SosCaseCard extends StatelessWidget {
  final AlertModel alert;
  const _SosCaseCard({required this.alert});

  @override
  Widget build(BuildContext context) {
    final prov = context.read<AlertProvider>();
    final me = context.read<UserProvider>().user;
    final statusColor = switch (alert.sosStatus) {
      'ACTIVE' => AppTheme.cutRed,
      'RESPONDING' => Colors.orange,
      'SAFE' => Colors.green,
      _ => AppTheme.cutMuted,
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
          color: statusColor.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: statusColor, width: 2)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
              color: statusColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
          child: Row(children: [
            Icon(
                alert.sosStatus == 'SAFE'
                    ? Icons.check_circle
                    : Icons.emergency,
                color: Colors.white,
                size: 18),
            const SizedBox(width: 8),
            Expanded(
                child: Text('${alert.userName} — ${alert.sosStatus}',
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 13))),
            TimeAgoText(alert.createdAt,
                style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(alert.description, style: const TextStyle(fontSize: 13, height: 1.4)),
            if (alert.location != null) ...[
              const SizedBox(height: 8),
              LocationRow(alert.location!),
            ],
            if (alert.respondingBy != null && alert.respondingBy!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(children: [
                const Icon(Icons.shield_outlined, size: 13, color: AppTheme.cutBlue),
                const SizedBox(width: 4),
                Text('${alert.respondingBy} responding',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.cutBlue,
                        fontWeight: FontWeight.w500)),
              ]),
            ],
            const SizedBox(height: 12),
            Row(children: [
              if (alert.hasCoords)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => MapScreen(
                            focusTarget: LatLng(alert.latitude!, alert.longitude!),
                            focusLabel: '🚨 SOS — ${alert.userName}'))),
                    icon: const Icon(Icons.map_outlined, size: 15),
                    label: const Text('View on Map', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                  ),
                ),
              if (alert.hasCoords) const SizedBox(width: 8),
              if (alert.sosStatus == 'ACTIVE')
                Expanded(
                  child: ElevatedButton(
                    onPressed: () =>
                        prov.markSOSResponding(alert.id, me?.name ?? 'Security'),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.cutRed, minimumSize: const Size(0, 36)),
                    child: const Text('Respond', style: TextStyle(fontSize: 12)),
                  ),
                ),
              if (alert.sosStatus == 'RESPONDING')
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => prov.markSOSSafe(alert.id),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green, minimumSize: const Size(0, 36)),
                    child: const Text("Mark Safe", style: TextStyle(fontSize: 12)),
                  ),
                ),
              if (alert.sosStatus == 'SAFE') ...[
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => prov.resolveSOS(alert.id),
                    style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                    child: const Text('Resolve', style: TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ]),
          ]),
        ),
      ]),
    );
  }
}
