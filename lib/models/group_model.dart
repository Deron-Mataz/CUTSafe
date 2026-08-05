enum GroupType {
  open('open', 'Open'),
  private('private', 'Private');

  const GroupType(this.value, this.label);
  final String value;
  final String label;
  static GroupType fromString(String v) => GroupType.values
      .firstWhere((e) => e.value == v, orElse: () => GroupType.open);
}

/// Mirrors backend AdminGroupModel (CUTPulseAdmin.Models.AdminGroupModel).
class GroupModel {
  final String id, name, description, adminId, adminName;
  final GroupType type;
  final List<String> memberIds;
  final List<String> bannedIds;
  final String? coverUrl;
  final DateTime createdAt;
  final String? latestMessage;
  final String? latestSenderName;
  final DateTime? latestMessageAt;
  final Map<String, int> unreadCounts;

  // Admin-managed moderation fields
  final bool isLocked; // no new messages allowed
  final bool isVerified; // admin-verified legitimate group
  final String status; // active | locked | suspended

  const GroupModel({
    required this.id,
    required this.name,
    required this.description,
    required this.adminId,
    required this.adminName,
    required this.type,
    required this.memberIds,
    this.bannedIds = const [],
    this.coverUrl,
    required this.createdAt,
    this.latestMessage,
    this.latestSenderName,
    this.latestMessageAt,
    this.unreadCounts = const {},
    this.isLocked = false,
    this.isVerified = false,
    this.status = 'active',
  });

  bool get isOpen => type == GroupType.open;
  int get memberCount => memberIds.length;
  bool get isSuspended => status == 'suspended';

  factory GroupModel.fromMap(String id, Map<String, dynamic> map) => GroupModel(
        id: id,
        name: map['name'] as String? ?? '',
        description: map['description'] as String? ?? '',
        adminId: map['adminId'] as String? ?? '',
        adminName: map['adminName'] as String? ?? 'Admin',
        type: GroupType.fromString(map['type'] as String? ?? ''),
        memberIds: List<String>.from((map['memberIds'] as List?) ?? []),
        bannedIds: List<String>.from((map['bannedIds'] as List?) ?? []),
        coverUrl: map['coverUrl'] as String?,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        latestMessage: map['latestMessage'] as String?,
        latestSenderName: map['latestSenderName'] as String?,
        latestMessageAt:
            DateTime.tryParse(map['latestMessageAt'] as String? ?? ''),
        unreadCounts: Map<String, int>.from(
            ((map['unreadCounts'] as Map?) ?? {})
                .map((key, value) => MapEntry(key.toString(), (value as num?)?.toInt() ?? 0))),
        isLocked: map['isLocked'] as bool? ?? false,
        isVerified: map['isVerified'] as bool? ?? false,
        status: map['status'] as String? ?? 'active',
      );

  Map<String, dynamic> toMap() => {
        'name': name,
        'description': description,
        'adminId': adminId,
        'adminName': adminName,
        'type': type.value,
        'memberIds': memberIds,
        'bannedIds': bannedIds,
        'coverUrl': coverUrl,
        'createdAt': createdAt.toIso8601String(),
        'latestMessage': latestMessage,
        'latestSenderName': latestSenderName,
        'latestMessageAt': latestMessageAt?.toIso8601String(),
        'unreadCounts': unreadCounts,
        'isLocked': isLocked,
        'isVerified': isVerified,
        'status': status,
      };
}

enum MessageType {
  text('text'),
  image('image'),
  video('video'),
  voice('voice'),
  location('location');

  const MessageType(this.value);
  final String value;
  static MessageType fromString(String v) => MessageType.values
      .firstWhere((e) => e.value == v, orElse: () => MessageType.text);
}

class GroupMessage {
  final String id, groupId, userId, userName;
  final String? userPhotoUrl;
  final String text;
  final MessageType messageType;
  final String? mediaUrl, mediaThumbnail;
  final int? mediaDuration;
  final double? locationLat, locationLng;
  final String? locationAddress;
  final DateTime? locationExpiresAt;
  final DateTime createdAt;
  final String? replyToMessageId, replyToSenderName, replyToText, replyToType;
  final Map<String, List<String>> reactions;
  final List<String> deliveredTo, readBy, deletedFor;
  final bool isDeleted, isPinned;
  final String? pinnedBy;
  final DateTime? pinnedAt;

  const GroupMessage({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.text,
    this.messageType = MessageType.text,
    this.mediaUrl,
    this.mediaThumbnail,
    this.mediaDuration,
    this.locationLat,
    this.locationLng,
    this.locationAddress,
    this.locationExpiresAt,
    this.replyToMessageId,
    this.replyToSenderName,
    this.replyToText,
    this.replyToType,
    this.reactions = const {},
    this.deliveredTo = const [],
    this.readBy = const [],
    this.deletedFor = const [],
    this.isDeleted = false,
    this.isPinned = false,
    this.pinnedBy,
    this.pinnedAt,
    required this.createdAt,
  });

  bool get isLocationExpired =>
      locationExpiresAt != null && DateTime.now().isAfter(locationExpiresAt!);

  factory GroupMessage.fromMap(String id, Map<String, dynamic> map) =>
      GroupMessage(
        id: id,
        groupId: map['groupId'] as String? ?? '',
        userId: map['userId'] as String? ?? '',
        userName: map['userName'] as String? ?? 'Member',
        userPhotoUrl: map['userPhotoUrl'] as String?,
        text: map['text'] as String? ?? '',
        messageType:
            MessageType.fromString(map['messageType'] as String? ?? 'text'),
        mediaUrl: map['mediaUrl'] as String?,
        mediaThumbnail: map['mediaThumbnail'] as String?,
        mediaDuration: map['mediaDuration'] as int?,
        locationLat: (map['locationLat'] as num?)?.toDouble(),
        locationLng: (map['locationLng'] as num?)?.toDouble(),
        locationAddress: map['locationAddress'] as String?,
        locationExpiresAt: map['locationExpiresAt'] != null
            ? DateTime.tryParse(map['locationExpiresAt'] as String)
            : null,
        replyToMessageId: map['replyToMessageId'] as String?,
        replyToSenderName: map['replyToSenderName'] as String?,
        replyToText: map['replyToText'] as String?,
        replyToType: map['replyToType'] as String?,
        reactions: Map<String, List<String>>.from(((map['reactions'] as Map?) ?? {})
            .map((key, value) => MapEntry(key.toString(), List<String>.from((value as List?) ?? [])))),
        deliveredTo: List<String>.from((map['deliveredTo'] as List?) ?? []),
        readBy: List<String>.from((map['readBy'] as List?) ?? []),
        deletedFor: List<String>.from((map['deletedFor'] as List?) ?? []),
        isDeleted: map['isDeleted'] as bool? ?? false,
        isPinned: map['isPinned'] as bool? ?? false,
        pinnedBy: map['pinnedBy'] as String?,
        pinnedAt: DateTime.tryParse(map['pinnedAt'] as String? ?? ''),
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'groupId': groupId,
        'userId': userId,
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        'text': text,
        'messageType': messageType.value,
        'mediaUrl': mediaUrl,
        'mediaThumbnail': mediaThumbnail,
        'mediaDuration': mediaDuration,
        'locationLat': locationLat,
        'locationLng': locationLng,
        'locationAddress': locationAddress,
        'locationExpiresAt': locationExpiresAt?.toIso8601String(),
        'replyToMessageId': replyToMessageId,
        'replyToSenderName': replyToSenderName,
        'replyToText': replyToText,
        'replyToType': replyToType,
        'reactions': reactions,
        'deliveredTo': deliveredTo,
        'readBy': readBy,
        'deletedFor': deletedFor,
        'isDeleted': isDeleted,
        'isPinned': isPinned,
        'pinnedBy': pinnedBy,
        'pinnedAt': pinnedAt?.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
      };
}

class UpdateModel {
  final String id, userId, userName;
  final String? userPhotoUrl;
  final String content;
  final String? location;
  final List<String> imageUrls;
  final String? videoUrl;
  final DateTime createdAt;
  final int reportCount;

  const UpdateModel({
    required this.id,
    required this.userId,
    required this.userName,
    this.userPhotoUrl,
    required this.content,
    this.location,
    this.imageUrls = const [],
    this.videoUrl,
    required this.createdAt,
    this.reportCount = 0,
  });

  factory UpdateModel.fromMap(String id, Map<String, dynamic> map) =>
      UpdateModel(
        id: id,
        userId: map['userId'] as String? ?? '',
        userName: map['userName'] as String? ?? 'User',
        userPhotoUrl: map['userPhotoUrl'] as String?,
        content: map['content'] as String? ?? '',
        location: map['location'] as String?,
        imageUrls: List<String>.from((map['imageUrls'] as List?) ?? []),
        videoUrl: map['videoUrl'] as String?,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        reportCount: (map['reportCount'] as int?) ?? 0,
      );

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'userName': userName,
        'userPhotoUrl': userPhotoUrl,
        'content': content,
        'location': location,
        'imageUrls': imageUrls,
        'videoUrl': videoUrl,
        'createdAt': createdAt.toIso8601String(),
        'reportCount': reportCount,
      };
}

/// Mirrors backend AnnouncementModel — admin-broadcast messages.
class AnnouncementModel {
  final String id, title, message, audience, createdBy;
  final DateTime createdAt;
  final bool isActive;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.message,
    this.audience = 'everyone',
    required this.createdBy,
    required this.createdAt,
    this.isActive = true,
  });

  factory AnnouncementModel.fromMap(String id, Map<String, dynamic> map) =>
      AnnouncementModel(
        id: id,
        title: map['title'] as String? ?? '',
        message: map['message'] as String? ?? '',
        audience: map['audience'] as String? ?? 'everyone',
        createdBy: map['createdBy'] as String? ?? '',
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ??
            DateTime.now(),
        isActive: map['isActive'] as bool? ?? true,
      );
}
