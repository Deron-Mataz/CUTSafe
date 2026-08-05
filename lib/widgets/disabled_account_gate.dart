import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../theme/app_theme.dart';

/// EXTEND: backend UsersController.Disable/Enable sets UserModel.IsDisabled.
/// If an admin disables this user's account while they're using the app,
/// UserProvider's live userStream listener force-signs them out, but there
/// is a brief window where the UI should explain why. This screen is shown
/// during that window before the login screen takes over.
class DisabledAccountGate extends StatelessWidget {
  final Widget child;
  const DisabledAccountGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final disabled = context.watch<UserProvider>().isAccountDisabled;
    if (!disabled) return child;

    return Scaffold(
      backgroundColor: AppTheme.cutRed,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.block, size: 64, color: Colors.white),
              const SizedBox(height: 24),
              const Text('Account Disabled', style: TextStyle(
                  color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              const Text(
                'Your account has been disabled by an administrator. '
                'Please contact CUT Safety support if you believe this is a mistake.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
