import 'package:flutter/material.dart';
import '../models/settings_model.dart';
import '../services/firebase_service.dart';

/// EXTEND: mirrors backend SettingsController / PlatformSettings.
/// Listens to settings/platform in real time so the app can:
///  - instantly switch into Maintenance Mode when an admin enables it
///  - load Emergency Numbers dynamically instead of hardcoding them
class SettingsProvider extends ChangeNotifier {
  final _svc = FirebaseService.instance;

  PlatformSettings _settings = PlatformSettings.fallback;
  PlatformSettings get settings => _settings;

  bool get isMaintenance => _settings.maintenanceMode;

  SettingsProvider() {
    _svc.settingsStream().listen((s) {
      _settings = s;
      notifyListeners();
    });
  }
}
