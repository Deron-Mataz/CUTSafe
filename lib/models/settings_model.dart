class EmergencyNumber {
  final String label, number;
  const EmergencyNumber({required this.label, required this.number});

  factory EmergencyNumber.fromMap(Map<String, dynamic> m) => EmergencyNumber(
    label: m['label'] as String? ?? '',
    number: m['number'] as String? ?? '',
  );
}

/// Mirrors backend PlatformSettings (CUTPulseAdmin.Models.PlatformSettings).
/// Stored in Firestore doc settings/platform — controlled from the Admin
/// Dashboard's Settings screen.
class PlatformSettings {
  final List<EmergencyNumber> emergencyNumbers;
  final bool    maintenanceMode;
  final String? maintenanceMessage;

  const PlatformSettings({
    this.emergencyNumbers = const [],
    this.maintenanceMode = false,
    this.maintenanceMessage,
  });

  factory PlatformSettings.fromMap(Map<String, dynamic> map) => PlatformSettings(
    emergencyNumbers: ((map['emergencyNumbers'] as List?) ?? [])
        .map((e) => EmergencyNumber.fromMap(Map<String, dynamic>.from(e as Map)))
        .toList(),
    maintenanceMode: map['maintenanceMode'] as bool? ?? false,
    maintenanceMessage: map['maintenanceMessage'] as String?,
  );

  /// Sensible fallback if Firestore doc doesn't exist yet.
  static const fallback = PlatformSettings(
    emergencyNumbers: [
      EmergencyNumber(label: 'SAPS',             number: '10111'),
      EmergencyNumber(label: 'Ambulance',        number: '10177'),
      EmergencyNumber(label: 'Fire Dept',        number: '080011133'),
      EmergencyNumber(label: 'CUT Security BFN', number: '0514073911'),
      EmergencyNumber(label: 'CUT Security WLK', number: '0573914444'),
      EmergencyNumber(label: 'Lifeline SA',      number: '0861322322'),
    ],
  );
}
