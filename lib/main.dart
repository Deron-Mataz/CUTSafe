import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'providers/user_provider.dart';
import 'providers/alert_provider.dart';
import 'providers/group_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/report_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/splash/splash_screen.dart';
import 'theme/app_theme.dart';
import 'widgets/maintenance_gate.dart';
import 'widgets/disabled_account_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const CutSafetyApp());
}

class CutSafetyApp extends StatelessWidget {
  const CutSafetyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => UserProvider()),
        ChangeNotifierProvider(create: (_) => AlertProvider()),
        ChangeNotifierProvider(create: (_) => GroupProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => ReportProvider()),
      ],
      child: Builder(builder: (context) {
        final app = MaterialApp(
          title: 'CUT Safety',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          home: Consumer<UserProvider>(
            builder: (_, prov, __) {
              if (!prov.authResolved) return const SplashScreen();

              return prov.isLoggedIn
                  ? const DisabledAccountGate(child: HomeScreen())
                  : const LoginScreen();
            },
          ),
        );

        return MaintenanceGate(child: app);
      }),
    );
  }
}
