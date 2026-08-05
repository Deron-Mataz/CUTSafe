enum ConnectionStatus { none, pendingOutgoing, pendingIncoming, connected }

/// Doc id format: "${fromUid}__${toUid}"
/// `participants` duplicates [fromUid, toUid] as an array so a user can
/// query all their connections/requests with a single arrayContains query
/// without needing an OR across two different fields, and — critically —
/// without ever writing to another user's own document (which Firestore
/// rules cannot safely allow).
class ConnectionRequest {
  final String id;
  final String fromUid, fromName;
  final String? fromPhotoUrl;
  final String toUid, toName;
  final String? toPhotoUrl;
  final String status; // pending | accepted | declined
  final DateTime createdAt;

  const ConnectionRequest({
    required this.id, required this.fromUid, required this.fromName, this.fromPhotoUrl,
    required this.toUid, required this.toName, this.toPhotoUrl,
    required this.status, required this.createdAt,
  });

  factory ConnectionRequest.fromMap(String id, Map<String, dynamic> m) => ConnectionRequest(
    id: id,
    fromUid: m['fromUid'] as String? ?? '',
    fromName: m['fromName'] as String? ?? '',
    fromPhotoUrl: m['fromPhotoUrl'] as String?,
    toUid: m['toUid'] as String? ?? '',
    toName: m['toName'] as String? ?? '',
    toPhotoUrl: m['toPhotoUrl'] as String?,
    status: m['status'] as String? ?? 'pending',
    createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
  );

  Map<String, dynamic> toMap() => {
    'fromUid': fromUid, 'fromName': fromName, 'fromPhotoUrl': fromPhotoUrl,
    'toUid': toUid, 'toName': toName, 'toPhotoUrl': toPhotoUrl,
    'status': status, 'createdAt': createdAt.toIso8601String(),
    'participants': [fromUid, toUid],
  };
}
