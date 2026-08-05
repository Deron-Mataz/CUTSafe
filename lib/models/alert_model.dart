enum AlertCategory {
  crime('crime', 'Crime'),
  medical('medical', 'Medical'),
  hazard('hazard', 'Hazard'),
  sos('sos', 'SOS'),
  other('other', 'Other');

  const AlertCategory(this.value, this.label);
  final String value;
  final String label;
  static AlertCategory fromString(String v) => AlertCategory.values
      .firstWhere((e) => e.value == v, orElse: () => AlertCategory.other);
}

enum IncidentPriority { low, medium, high, critical }

/// Mirrors backend AlertModel (CUTPulseAdmin.Models.AlertModel).
class AlertModel {
  final String id, userId, userName;
  final String? userPhotoUrl;
  final String title, description;
  final String? location;
  final double? latitude, longitude;
  final AlertCategory category;
  final DateTime createdAt;
  final int reportCount;
  final bool isReported;
  final int confirmCount;
  final bool isConfirmed;
  final List<String> imageUrls;
  final String? videoUrl;

  // SOS
  final bool isSOS;
  final String sosStatus; // ACTIVE | RESPONDING | SAFE | RESOLVED
  final DateTime? safeAt;
  final String? respondingBy;

  // Moderation / dispatch (admin-controlled, read-only on mobile)
  final String status; // open | closed
  final String priority; // low|medium|high|critical
  final String? assignedOfficerId;
  final String? assignedOfficerName;
  final String dispatchStatus; // unassigned|assigned|accepted|completed

  const AlertModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.title,
    required this.description,
    this.location,
    this.latitude,
    this.longitude,
    required this.category,
    required this.createdAt,
    this.reportCount = 0,
    this.isReported = false,
    this.confirmCount = 0,
    this.isConfirmed = false,
    this.imageUrls = const [],
    this.videoUrl,
    this.isSOS = false,
    this.sosStatus = '',
    this.safeAt,
    this.respondingBy,
    this.status = 'open',
    this.priority = 'medium',
    this.assignedOfficerId,
    this.assignedOfficerName,
    this.dispatchStatus = 'unassigned',
  });

  bool get hasCoords => latitude != null && longitude != null;
  bool get isSOSActive => isSOS && sosStatus == 'ACTIVE';
  bool get isSOSResponding => isSOS && sosStatus == 'RESPONDING';
  bool get isSOSSafe => isSOS && sosStatus == 'SAFE';
  bool get isSOSResolved => isSOS && sosStatus == 'RESOLVED';
  bool get hasMedia => imageUrls.isNotEmpty || videoUrl != null;
  bool get isDispatched =>
      assignedOfficerId != null && assignedOfficerId!.isNotEmpty;
  bool get isClosed => status == 'closed';

  IncidentPriority get priorityEnum => switch (priority.toLowerCase()) {
        'low' => IncidentPriority.low,
        'high' => IncidentPriority.high,
        'critical' => IncidentPriority.critical,
        _ => IncidentPriority.medium,
      };

  factory AlertModel.fromMap(String id, Map<String, dynamic> map) => AlertModel(
        id: id,
        userId: map['userId'] as String? ?? '',
        userName: map['userName'] as String? ?? 'Anonymous',
        userPhotoUrl: map['userPhotoUrl'] as String?,
        title: map['title'] as String? ?? '',
        description: map['description'] as String? ?? '',
        location: map['location'] as String?,
        latitude: (map['latitude'] as num?)?.toDouble(),
        longitude: (map['longitude'] as num?)?.toDouble(),
        category: AlertCategory.fromString(map['category'] as String? ?? ''),
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        reportCount: (map['reportCount'] as int?) ?? 0,
        confirmCount: (map['confirmCount'] as int?) ?? 0,
        imageUrls: List<String>.from((map['imageUrls'] as List?) ?? []),
        videoUrl: map['videoUrl'] as String?,
        isSOS: map['isSOS'] as bool? ?? false,
        sosStatus: map['sosStatus'] as String? ?? '',
        safeAt: map['safeAt'] != null
            ? DateTime.tryParse(map['safeAt'] as String)
            : null,
        respondingBy: map['respondingBy'] as String?,
        status: map['status'] as String? ?? 'open',
        priority: map['priority'] as String? ?? 'medium',
        assignedOfficerId: map['assignedOfficerId'] as String?,
        assignedOfficerName: map['assignedOfficerName'] as String?,
        dispatchStatus: map['dispatchStatus'] as String? ?? 'unassigned',
      );

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        'title': title,
        'description': description,
        'location': location,
        'latitude': latitude,
        'longitude': longitude,
        'category': category.value,
        'createdAt': createdAt.toIso8601String(),
        'reportCount': reportCount,
        'confirmCount': confirmCount,
        'imageUrls': imageUrls,
        'videoUrl': videoUrl,
        'isSOS': isSOS,
        'sosStatus': sosStatus,
        'safeAt': safeAt?.toIso8601String(),
        'respondingBy': respondingBy,
        'status': status,
        'priority': priority,
        'assignedOfficerId': assignedOfficerId,
        'assignedOfficerName': assignedOfficerName,
        'dispatchStatus': dispatchStatus,
      };

  AlertModel copyWith({
    bool? isReported,
    int? reportCount,
    bool? isConfirmed,
    int? confirmCount,
    String? sosStatus,
    DateTime? safeAt,
  }) =>
      AlertModel(
        id: id,
        userId: userId,
        userName: userName,
        userPhotoUrl: userPhotoUrl,
        title: title,
        description: description,
        location: location,
        latitude: latitude,
        longitude: longitude,
        category: category,
        createdAt: createdAt,
        reportCount: reportCount ?? this.reportCount,
        isReported: isReported ?? this.isReported,
        confirmCount: confirmCount ?? this.confirmCount,
        isConfirmed: isConfirmed ?? this.isConfirmed,
        imageUrls: imageUrls,
        videoUrl: videoUrl,
        isSOS: isSOS,
        sosStatus: sosStatus ?? this.sosStatus,
        safeAt: safeAt ?? this.safeAt,
        respondingBy: respondingBy,
        status: status,
        priority: priority,
        assignedOfficerId: assignedOfficerId,
        assignedOfficerName: assignedOfficerName,
        dispatchStatus: dispatchStatus,
      );
}
