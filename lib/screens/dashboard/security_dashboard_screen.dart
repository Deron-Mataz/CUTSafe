import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:provider/provider.dart';
import '../../models/alert_model.dart';
import '../../providers/alert_provider.dart';
import '../../providers/report_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import '../emergency/emergency_screen.dart';
import '../map/map_screen.dart';
import 'security_alerts_screen.dart';
import 'security_reports_screen.dart';

/// Security's operational home screen (Requirement #4).
///
/// Surfaces exactly the data CUTPulseAdmin.Controllers.HomeController's
/// DashboardStats does (active SOS, open incidents, pending reports, online
/// security), plus the officer's own assigned-incident queue (mirrors
/// DispatchController) — using this app's existing design language
/// (AppTheme tokens, Card/EmptyState/TimeAgoText widgets) rather than a
/// new design system.
class SecurityDashboardScreen extends StatelessWidget {
  const SecurityDashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final me = context.watch<UserProvider>().user;
    final alertProv = context.watch<AlertProvider>();
    final reportProv = context.watch<ReportProvider>();

    final incidents = alertProv.alerts.where((a) => !a.isSOS).toList();
    final openIncidents = incidents.where((a) => !a.isClosed).length;
    final activeSOS = alertProv.activeSOS.length;
    final myAssigned = me == null
        ? <AlertModel>[]
        : incidents
            .where((a) =>
                a.assignedOfficerId == me.id && a.dispatchStatus != 'completed')
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Security Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.emergency_outlined),
            tooltip: 'Personal Emergency SOS',
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const EmergencyScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (me != null) _AvailabilityCard(uid: me.id, current: me.availability),
            const SizedBox(height: 16),
            _StatsGrid(
              activeSOS: activeSOS,
              openIncidents: openIncidents,
              pendingReports: reportProv.pendingCount,
            ),
            const SizedBox(height: 20),
            _SectionTitle('MY ASSIGNED INCIDENTS'),
            if (myAssigned.isEmpty)
              const _InlineEmpty(
                  icon: Icons.assignment_turned_in_outlined,
                  text: 'No incidents currently assigned to you.')
            else
              ...myAssigned.map((a) => _AssignedIncidentTile(alert: a)),
            const SizedBox(height: 20),
            _SectionTitle('ACTIVE SOS'),
            if (alertProv.activeSOS.isEmpty)
              const _InlineEmpty(
                  icon: Icons.check_circle_outline, text: 'No active SOS alerts.')
            else
              ...alertProv.activeSOS.map((a) => _DashboardSOSTile(alert: a)),
            const SizedBox(height: 20),
            _SectionTitle('QUICK ACTIONS'),
            _QuickActionsRow(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppTheme.cutMuted,
                letterSpacing: 0.5)),
      );
}

class _InlineEmpty extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InlineEmpty({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: AppTheme.cutGrey,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.cutBorder)),
        child: Row(children: [
          Icon(icon, color: AppTheme.cutMuted, size: 20),
          const SizedBox(width: 10),
          Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, color: AppTheme.cutMuted))),
        ]),
      );
}

// ── Availability toggle ──────────────────────────────────────────────
class _AvailabilityCard extends StatelessWidget {
  final String uid;
  final String current;
  const _AvailabilityCard({required this.uid, required this.current});

  static const _opts = ['available', 'responding', 'busy', 'offline'];
  static const _labels = {
    'available': 'Available',
    'responding': 'Responding',
    'busy': 'Busy',
    'offline': 'Offline',
  };
  static const _colors = {
    'available': Colors.green,
    'responding': AppTheme.cutRed,
    'busy': Colors.orange,
    'offline': AppTheme.cutMuted,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[current] ?? AppTheme.cutMuted;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          const Text('My availability',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const Spacer(),
          DropdownButton<String>(
            value: current,
            underline: const SizedBox.shrink(),
            items: _opts
                .map((o) => DropdownMenuItem(
                    value: o,
                    child: Text(_labels[o]!,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _colors[o]))))
                .toList(),
            onChanged: (v) {
              if (v != null) FirebaseService.instance.updateAvailability(uid, v);
            },
          ),
        ]),
      ),
    );
  }
}

// ── Stats grid ────────────────────────────────────────────────────────
class _StatsGrid extends StatelessWidget {
  final int activeSOS;
  final int openIncidents;
  final int pendingReports;
  const _StatsGrid(
      {required this.activeSOS,
      required this.openIncidents,
      required this.pendingReports});

  @override
  Widget build(BuildContext context) => StreamBuilder<int>(
        stream: FirebaseService.instance
            .securityPersonnelStream()
            .map((list) => list.where((u) => u.isOnline).length),
        builder: (_, snap) {
          final onlineSec = snap.data ?? 0;
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _StatCard(
                  label: 'Active SOS',
                  value: activeSOS,
                  icon: Icons.emergency,
                  color: AppTheme.cutRed),
              _StatCard(
                  label: 'Open Incidents',
                  value: openIncidents,
                  icon: Icons.warning_amber_rounded,
                  color: Colors.orange),
              _StatCard(
                  label: 'Pending Reports',
                  value: pendingReports,
                  icon: Icons.flag_outlined,
                  color: AppTheme.cutBlue),
              _StatCard(
                  label: 'Security Online',
                  value: onlineSec,
                  icon: Icons.shield_outlined,
                  color: Colors.green),
            ],
          );
        },
      );
}

class _StatCard extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  const _StatCard(
      {required this.label,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.cutBorder)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 18)),
            const Spacer(),
            Text('$value',
                style: TextStyle(
                    fontSize: 24, fontWeight: FontWeight.w800, color: color)),
          ]),
          const SizedBox(height: 8),
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppTheme.cutMuted)),
        ]),
      );
}

// ── Assigned incident tile ───────────────────────────────────────────
class _AssignedIncidentTile extends StatelessWidget {
  final AlertModel alert;
  const _AssignedIncidentTile({required this.alert});

  @override
  Widget build(BuildContext context) {
    final prov = context.read<AlertProvider>();
    final canAccept = alert.dispatchStatus == 'assigned';
    final canComplete = alert.dispatchStatus == 'accepted';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CategoryBadge(label: alert.category.label, color: AppTheme.cutRed),
            const SizedBox(width: 8),
            _PriorityBadge(priority: alert.priority),
            const Spacer(),
            TimeAgoText(alert.createdAt,
                style: const TextStyle(fontSize: 11, color: AppTheme.cutMuted)),
          ]),
          const SizedBox(height: 8),
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
          const SizedBox(height: 12),
          Row(children: [
            if (alert.hasCoords)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => MapScreen(
                          focusTarget:
                              LatLng(alert.latitude!, alert.longitude!),
                          focusLabel: alert.title))),
                  icon: const Icon(Icons.map_outlined, size: 15),
                  label: const Text('Map', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                ),
              ),
            if (alert.hasCoords) const SizedBox(width: 8),
            if (canAccept)
              Expanded(
                child: ElevatedButton(
                  onPressed: () => prov.updateDispatchStatus(alert.id, 'accepted'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(0, 36)),
                  child: const Text('Accept', style: TextStyle(fontSize: 12)),
                ),
              ),
            if (canComplete)
              Expanded(
                child: ElevatedButton(
                  onPressed: () =>
                      prov.updateDispatchStatus(alert.id, 'completed'),
                  style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 36), backgroundColor: Colors.green),
                  child: const Text('Mark Completed', style: TextStyle(fontSize: 12)),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String priority;
  const _PriorityBadge({required this.priority});
  @override
  Widget build(BuildContext context) {
    final color = switch (priority.toLowerCase()) {
      'critical' => AppTheme.cutRed,
      'high' => Colors.orange,
      'low' => AppTheme.cutMuted,
      _ => AppTheme.cutBlue,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(6)),
      child: Text(priority.toUpperCase(),
          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
    );
  }
}

// ── Dashboard SOS tile ────────────────────────────────────────────────
class _DashboardSOSTile extends StatelessWidget {
  final AlertModel alert;
  const _DashboardSOSTile({required this.alert});

  @override
  Widget build(BuildContext context) {
    final prov = context.read<AlertProvider>();
    final me = context.read<UserProvider>().user;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppTheme.cutRed.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.cutRed, width: 1.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.emergency, color: AppTheme.cutRed, size: 18),
          const SizedBox(width: 8),
          Expanded(
              child: Text(alert.userName,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
          TimeAgoText(alert.createdAt,
              style: const TextStyle(fontSize: 11, color: AppTheme.cutMuted)),
        ]),
        if (alert.location != null) ...[
          const SizedBox(height: 6),
          LocationRow(alert.location!),
        ],
        const SizedBox(height: 10),
        Row(children: [
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
          if (alert.hasCoords) const SizedBox(width: 8),
          if (alert.hasCoords)
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SecurityAlertsScreen(initialTab: 1))),
                style: OutlinedButton.styleFrom(minimumSize: const Size(0, 36)),
                child: const Text('View', style: TextStyle(fontSize: 12)),
              ),
            ),
        ]),
      ]),
    );
  }
}

// ── Quick actions ─────────────────────────────────────────────────────
class _QuickActionsRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
            child: _QuickAction(
                icon: Icons.warning_amber_rounded,
                label: 'Alerts',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SecurityAlertsScreen())))),
        const SizedBox(width: 10),
        Expanded(
            child: _QuickAction(
                icon: Icons.flag_outlined,
                label: 'Reports',
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SecurityReportsScreen())))),
        const SizedBox(width: 10),
        Expanded(
            child: _QuickAction(
                icon: Icons.map_outlined,
                label: 'Live Map',
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const MapScreen())))),
      ]);
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
              color: AppTheme.cutBlue.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.cutBlue.withValues(alpha: 0.2))),
          child: Column(children: [
            Icon(icon, color: AppTheme.cutBlue, size: 22),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.cutBlue)),
          ]),
        ),
      );
}
