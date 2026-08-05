import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import '../../models/report_model.dart';
import '../../providers/report_provider.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common_widgets.dart';

class SecurityReportDetailScreen extends StatelessWidget {
  final String reportId;
  const SecurityReportDetailScreen({super.key, required this.reportId});

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<ReportProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Report Detail')),
      body: StreamBuilder<ReportModel?>(
        stream: prov.reportStream(reportId),
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final report = snap.data;
          if (report == null) {
            return const Center(child: Text('Report not found'));
          }
          return _ReportDetailBody(report: report);
        },
      ),
    );
  }
}

class _ReportDetailBody extends StatelessWidget {
  final ReportModel report;
  const _ReportDetailBody({required this.report});

  @override
  Widget build(BuildContext context) {
    final me = context.read<UserProvider>().user;
    final prov = context.read<ReportProvider>();

    Future<void> handle(Future<String?> Function() action, String successMsg) async {
      final err = await action();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(err ?? successMsg),
          backgroundColor: err != null ? AppTheme.cutRed : Colors.green));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Icon(report.itemTypeIcon, color: AppTheme.cutBlue),
          const SizedBox(width: 8),
          Expanded(
              child: Text(report.itemName.isNotEmpty ? report.itemName : '(untitled item)',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _Badge(text: report.statusDisplay, color: report.statusColor),
          _Badge(text: report.priority.toUpperCase(), color: report.priorityColor),
          _Badge(text: report.itemTypeDisplay, color: AppTheme.cutMuted),
        ]),
        const SizedBox(height: 16),
        _SectionCard(title: 'Report Details', children: [
          _InfoRow(label: 'Reported by', value: report.reportedByName),
          _InfoRow(label: 'Reason', value: report.reason),
          if (report.description.isNotEmpty)
            _InfoRow(label: 'Description', value: report.description),
          _InfoRow(
              label: 'Submitted',
              value: '${report.createdAt.day}/${report.createdAt.month}/${report.createdAt.year}'),
        ]),
        if (report.evidenceUrls.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionCard(title: 'Evidence', children: [
            SizedBox(
              height: 90,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: report.evidenceUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                      imageUrl: report.evidenceUrls[i],
                      width: 90,
                      height: 90,
                      fit: BoxFit.cover),
                ),
              ),
            ),
          ]),
        ],
        const SizedBox(height: 16),
        _SectionCard(title: 'Actions', children: [
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (report.statusEnum != ReportStatus.underInvestigation &&
                report.statusEnum != ReportStatus.resolved &&
                report.statusEnum != ReportStatus.dismissed)
              OutlinedButton(
                onPressed: () => handle(
                    () => prov.updateStatus(report.id, 'under_investigation',
                        actorId: me?.id ?? '', actorName: me?.name ?? 'Security'),
                    'Marked as under investigation.'),
                child: const Text('Start Investigation'),
              ),
            if (report.statusEnum != ReportStatus.resolved)
              OutlinedButton(
                onPressed: () => handle(
                    () => prov.updateStatus(report.id, 'resolved',
                        actorId: me?.id ?? '', actorName: me?.name ?? 'Security'),
                    'Report resolved.'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.green),
                child: const Text('Mark Resolved'),
              ),
            if (report.statusEnum != ReportStatus.dismissed &&
                report.statusEnum != ReportStatus.resolved)
              OutlinedButton(
                onPressed: () => handle(
                    () => prov.dismiss(report.id,
                        actorId: me?.id ?? '', actorName: me?.name ?? 'Security'),
                    'Report dismissed.'),
                style: OutlinedButton.styleFrom(foregroundColor: AppTheme.cutMuted),
                child: const Text('Dismiss'),
              ),
            if (report.itemTypeEnum == ReportItemType.incident &&
                report.statusEnum != ReportStatus.resolved)
              ElevatedButton(
                onPressed: () => handle(
                    () => prov.closeIncident(report.id, report.itemId,
                        actorId: me?.id ?? '', actorName: me?.name ?? 'Security'),
                    'Incident closed, report resolved.'),
                style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cutRed),
                child: const Text('Close Incident & Resolve'),
              ),
          ]),
          const SizedBox(height: 12),
          const Text('Priority', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            for (final p in ['low', 'medium', 'high', 'critical'])
              ChoiceChip(
                label: Text(p.toUpperCase(), style: const TextStyle(fontSize: 11)),
                selected: report.priority == p,
                onSelected: (_) => handle(
                    () => prov.updatePriority(report.id, p,
                        actorId: me?.id ?? '', actorName: me?.name ?? 'Security'),
                    'Priority updated.'),
              ),
          ]),
        ]),
        const SizedBox(height: 16),
        _SectionCard(title: 'Timeline', children: [
          StreamBuilder<List<ReportTimelineEvent>>(
            stream: prov.timelineStream(report.id),
            builder: (_, snap) {
              final events = snap.data ?? [];
              if (events.isEmpty) {
                return const Text('No activity yet.',
                    style: TextStyle(fontSize: 12, color: AppTheme.cutMuted));
              }
              return Column(
                children: events
                    .map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 4),
                                  child: Icon(Icons.circle, size: 6, color: AppTheme.cutBlue),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(e.event,
                                            style: const TextStyle(
                                                fontSize: 13, fontWeight: FontWeight.w600)),
                                        Text('${e.actorName} · ${_fmt(e.createdAt)}',
                                            style: const TextStyle(
                                                fontSize: 11, color: AppTheme.cutMuted)),
                                      ]),
                                ),
                              ]),
                        ))
                    .toList(),
              );
            },
          ),
        ]),
      ],
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SectionCard({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              const SizedBox(height: 10),
              ...children,
            ],
          ),
        ),
      );
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.cutMuted)),
            Text(value, style: const TextStyle(fontSize: 13)),
          ],
        ),
      );
}

class _Badge extends StatelessWidget {
  final String text;
  final Color color;
  const _Badge({required this.text, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
        child: Text(text,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
      );
}
