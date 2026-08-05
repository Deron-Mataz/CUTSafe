import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/report_model.dart';
import '../../providers/report_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';
import 'security_report_detail_screen.dart';

/// Mirrors CUTPulseAdmin.Controllers.ReportsController.Index — status-based
/// filtering of the reports queue. Search/date-range filters from the admin
/// dashboard are omitted here in favour of the simple status tabs that fit
/// a mobile screen; nothing about the underlying data model changes.
class SecurityReportsScreen extends StatefulWidget {
  const SecurityReportsScreen({super.key});
  @override
  State<SecurityReportsScreen> createState() => _SecurityReportsScreenState();
}

class _SecurityReportsScreenState extends State<SecurityReportsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ReportProvider>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Pending (${prov.pendingReview.length})'),
            Tab(text: 'Investigating (${prov.underInvestigation.length})'),
            Tab(text: 'Resolved (${prov.resolved.length})'),
            Tab(text: 'Dismissed (${prov.dismissed.length})'),
          ],
        ),
      ),
      body: TabBarView(controller: _tabs, children: [
        _ReportsList(reports: prov.pendingReview),
        _ReportsList(reports: prov.underInvestigation),
        _ReportsList(reports: prov.resolved),
        _ReportsList(reports: prov.dismissed),
      ]),
    );
  }
}

class _ReportsList extends StatelessWidget {
  final List<ReportModel> reports;
  const _ReportsList({required this.reports});

  @override
  Widget build(BuildContext context) {
    if (reports.isEmpty) {
      return const EmptyState(
          icon: Icons.flag_outlined,
          title: 'No Reports',
          subtitle: 'Nothing in this category right now.');
    }
    final sorted = [...reports]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sorted.length,
      itemBuilder: (_, i) => _ReportCard(report: sorted[i]),
    );
  }
}

class _ReportCard extends StatelessWidget {
  final ReportModel report;
  const _ReportCard({required this.report});

  @override
  Widget build(BuildContext context) => Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => SecurityReportDetailScreen(reportId: report.id))),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(report.itemTypeIcon, size: 16, color: AppTheme.cutMuted),
                const SizedBox(width: 6),
                Text(report.itemTypeDisplay,
                    style: const TextStyle(fontSize: 12, color: AppTheme.cutMuted)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                      color: report.priorityColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6)),
                  child: Text(report.priority.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: report.priorityColor)),
                ),
              ]),
              const SizedBox(height: 8),
              Text(report.itemName.isNotEmpty ? report.itemName : '(untitled item)',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              const SizedBox(height: 4),
              Text('Reason: ${report.reason}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12)),
              const SizedBox(height: 8),
              Row(children: [
                const Icon(Icons.person_outline, size: 13, color: AppTheme.cutMuted),
                const SizedBox(width: 4),
                Expanded(
                    child: Text('Reported by ${report.reportedByName}',
                        style:
                            const TextStyle(fontSize: 11, color: AppTheme.cutMuted))),
                TimeAgoText(report.createdAt,
                    style: const TextStyle(fontSize: 11, color: AppTheme.cutMuted)),
              ]),
            ]),
          ),
        ),
      );
}
