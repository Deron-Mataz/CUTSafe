import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum ReportItemType { post, user, group, incident }
enum ReportStatus { pendingReview, underInvestigation, resolved, dismissed }
enum ReportPriority { low, medium, high, critical }

/// Mirrors backend ReportModel (CUTPulseAdmin.Models.ReportModel).
/// Stored in Firestore collection "reports".
///
/// NOTE: the backend's `reports/{id}/notes` sub-collection is explicitly
/// documented as "Internal only — never exposed to mobile users." There is
/// intentionally no Flutter model, service method, or UI for report notes —
/// Security personnel using the app can see status/priority/timeline but
/// not administrator notes.
class ReportModel {
  final String id;
  final String itemType, itemId, itemName;
  final String reportedById, reportedByName;
  final String reason, description;
  final List<String> evidenceUrls;
  final String status;   // pending_review|under_investigation|resolved|dismissed
  final String priority; // low|medium|high|critical
  final String? assignedToId, assignedToName;
  final DateTime? assignedAt;
  final DateTime createdAt, updatedAt;

  const ReportModel({
    required this.id,
    required this.itemType,
    required this.itemId,
    required this.itemName,
    required this.reportedById,
    required this.reportedByName,
    required this.reason,
    this.description = '',
    this.evidenceUrls = const [],
    this.status = 'pending_review',
    this.priority = 'medium',
    this.assignedToId,
    this.assignedToName,
    this.assignedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  ReportItemType get itemTypeEnum => switch (itemType.toLowerCase()) {
        'user' => ReportItemType.user,
        'group' => ReportItemType.group,
        'incident' => ReportItemType.incident,
        _ => ReportItemType.post,
      };

  ReportStatus get statusEnum => switch (status) {
        'under_investigation' => ReportStatus.underInvestigation,
        'resolved' => ReportStatus.resolved,
        'dismissed' => ReportStatus.dismissed,
        _ => ReportStatus.pendingReview,
      };

  ReportPriority get priorityEnum => switch (priority.toLowerCase()) {
        'low' => ReportPriority.low,
        'high' => ReportPriority.high,
        'critical' => ReportPriority.critical,
        _ => ReportPriority.medium,
      };

  String get statusDisplay => switch (status) {
        'under_investigation' => 'Under Investigation',
        'resolved' => 'Resolved',
        'dismissed' => 'Dismissed',
        _ => 'Pending Review',
      };

  String get itemTypeDisplay => switch (itemTypeEnum) {
        ReportItemType.user => 'User',
        ReportItemType.group => 'Group',
        ReportItemType.incident => 'Incident',
        ReportItemType.post => 'Post',
      };

  IconData get itemTypeIcon => switch (itemTypeEnum) {
        ReportItemType.user => Icons.person_outline,
        ReportItemType.group => Icons.group_outlined,
        ReportItemType.incident => Icons.warning_amber_outlined,
        ReportItemType.post => Icons.campaign_outlined,
      };

  Color get statusColor => switch (statusEnum) {
        ReportStatus.underInvestigation => Colors.orange,
        ReportStatus.resolved => Colors.green,
        ReportStatus.dismissed => AppTheme.cutMuted,
        ReportStatus.pendingReview => AppTheme.cutBlue,
      };

  Color get priorityColor => switch (priorityEnum) {
        ReportPriority.critical => AppTheme.cutRed,
        ReportPriority.high => Colors.orange,
        ReportPriority.low => AppTheme.cutMuted,
        ReportPriority.medium => AppTheme.cutBlue,
      };

  bool get isOpen =>
      statusEnum == ReportStatus.pendingReview ||
      statusEnum == ReportStatus.underInvestigation;

  factory ReportModel.fromMap(String id, Map<String, dynamic> m) => ReportModel(
        id: id,
        itemType: m['itemType'] as String? ?? 'post',
        itemId: m['itemId'] as String? ?? '',
        itemName: m['itemName'] as String? ?? '',
        reportedById: m['reportedById'] as String? ?? '',
        reportedByName: m['reportedByName'] as String? ?? 'Unknown',
        reason: m['reason'] as String? ?? '',
        description: m['description'] as String? ?? '',
        evidenceUrls: List<String>.from((m['evidenceUrls'] as List?) ?? []),
        status: m['status'] as String? ?? 'pending_review',
        priority: m['priority'] as String? ?? 'medium',
        assignedToId: m['assignedToId'] as String?,
        assignedToName: m['assignedToName'] as String?,
        assignedAt: m['assignedAt'] != null
            ? DateTime.tryParse(m['assignedAt'] as String)
            : null,
        createdAt:
            DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
        updatedAt:
            DateTime.tryParse(m['updatedAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Mirrors backend ReportTimelineEvent — append-only activity log.
/// Stored in sub-collection reports/{reportId}/timeline.
class ReportTimelineEvent {
  final String id;
  final String actorId, actorName, event;
  final String? detail;
  final DateTime createdAt;

  const ReportTimelineEvent({
    required this.id,
    required this.actorId,
    required this.actorName,
    required this.event,
    this.detail,
    required this.createdAt,
  });

  factory ReportTimelineEvent.fromMap(String id, Map<String, dynamic> m) =>
      ReportTimelineEvent(
        id: id,
        actorId: m['actorId'] as String? ?? '',
        actorName: m['actorName'] as String? ?? 'System',
        event: m['event'] as String? ?? '',
        detail: m['detail'] as String?,
        createdAt:
            DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'actorId': actorId,
        'actorName': actorName,
        'event': event,
        'detail': detail,
        'createdAt': createdAt.toIso8601String(),
      };
}
