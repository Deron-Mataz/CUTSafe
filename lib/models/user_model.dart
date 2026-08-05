class EmergencyContact {
  final String name, phone, relationship;
  const EmergencyContact({required this.name, required this.phone, required this.relationship});

  factory EmergencyContact.fromMap(Map<String, dynamic> m) => EmergencyContact(
    name: m['name'] as String? ?? '',
    phone: m['phone'] as String? ?? '',
    relationship: m['relationship'] as String? ?? '',
  );
  Map<String, dynamic> toMap() => {'name': name, 'phone': phone, 'relationship': relationship};
}

/// Mirrors backend UserModel (CUTPulseAdmin.Models.UserModel).
class UserModel {
  final String id;
  final String name;
  final String email;
  final String campus;
  final String? photoUrl;
  final String? coverPhotoUrl;
  final String role;          // user | security | administrator
  final bool isDisabled;
  final bool isVerified;
  final bool isSafe;
  final String? safeMessage;
  final DateTime createdAt;
  final List<EmergencyContact> emergencyContacts;

  // Presence
  final bool isOnline;
  final DateTime? lastSeen;
  final String availability;  // available|responding|busy|offline
  final String? assignedIncidentId;
  final String? assignedIncidentTitle;
  final String? securityId;

  // NEW: social connections feature
  final List<String> connections;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.campus,
    this.photoUrl,
    this.coverPhotoUrl,
    this.role = 'user',
    this.isDisabled = false,
    this.isVerified = false,
    this.isSafe = false,
    this.safeMessage,
    required this.createdAt,
    this.emergencyContacts = const [],
    this.isOnline = false,
    this.lastSeen,
    this.availability = 'offline',
    this.assignedIncidentId,
    this.assignedIncidentTitle,
    this.securityId,
    this.connections = const [],
  });

  String get initials {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) return (parts.first[0] + parts.last[0]).toUpperCase();
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '?';
  }

  bool get isSecurityRole => role == 'security' || role == 'administrator';
  bool get isStudentOrStaff => role == 'user';
  int  get connectionCount => connections.length;

  factory UserModel.fromMap(String id, Map<String, dynamic> m) => UserModel(
    id: id,
    name: m['name'] as String? ?? '',
    email: m['email'] as String? ?? '',
    campus: m['campus'] as String? ?? '',
    photoUrl: m['photoUrl'] as String?,
    coverPhotoUrl: m['coverPhotoUrl'] as String?,
    role: m['role'] as String? ?? 'user',
    isDisabled: m['isDisabled'] as bool? ?? false,
    isVerified: m['isVerified'] as bool? ?? false,
    isSafe: m['isSafe'] as bool? ?? false,
    safeMessage: m['safeMessage'] as String?,
    createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ?? DateTime.now(),
    emergencyContacts: ((m['emergencyContacts'] as List?) ?? [])
        .map((e) => EmergencyContact.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    isOnline: m['isOnline'] as bool? ?? false,
    lastSeen: m['lastSeen'] != null ? DateTime.tryParse(m['lastSeen'] as String) : null,
    availability: m['availability'] as String? ?? 'offline',
    assignedIncidentId: m['assignedIncidentId'] as String?,
    assignedIncidentTitle: m['assignedIncidentTitle'] as String?,
    securityId: m['securityId'] as String?,
    connections: List<String>.from((m['connections'] as List?) ?? []),
  );

  Map<String, dynamic> toMap() => {
    'name': name,
    'email': email,
    'campus': campus,
    'photoUrl': photoUrl,
    'coverPhotoUrl': coverPhotoUrl,
    'role': role,
    'isDisabled': isDisabled,
    'isVerified': isVerified,
    'isSafe': isSafe,
    'safeMessage': safeMessage,
    'createdAt': createdAt.toIso8601String(),
    'emergencyContacts': emergencyContacts.map((e) => e.toMap()).toList(),
    'isOnline': isOnline,
    'lastSeen': lastSeen?.toIso8601String(),
    'availability': availability,
    'assignedIncidentId': assignedIncidentId,
    'assignedIncidentTitle': assignedIncidentTitle,
    'securityId': securityId,
    'connections': connections,
  };

  UserModel copyWith({
    String? name, String? campus, String? photoUrl, String? coverPhotoUrl,
    bool? isSafe, String? safeMessage,
    List<EmergencyContact>? emergencyContacts,
    bool? isOnline, DateTime? lastSeen, String? availability,
    List<String>? connections,
  }) => UserModel(
    id: id, name: name ?? this.name, email: email, campus: campus ?? this.campus,
    photoUrl: photoUrl ?? this.photoUrl,
    coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
    role: role, isDisabled: isDisabled,
    isVerified: isVerified, isSafe: isSafe ?? this.isSafe,
    safeMessage: safeMessage ?? this.safeMessage, createdAt: createdAt,
    emergencyContacts: emergencyContacts ?? this.emergencyContacts,
    isOnline: isOnline ?? this.isOnline, lastSeen: lastSeen ?? this.lastSeen,
    availability: availability ?? this.availability,
    assignedIncidentId: assignedIncidentId, assignedIncidentTitle: assignedIncidentTitle,
    securityId: securityId,
    connections: connections ?? this.connections,
  );
}
