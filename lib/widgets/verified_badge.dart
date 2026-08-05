import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum VerifiedBadgeTone {
  brand,
  onPrimary,
}

/// EXTEND: backend UserModel.IsVerified (set via UsersController.Verify) and
/// AdminGroupModel.IsVerified (set via GroupsController.Verify/Unverify)
/// were tracked in Firestore but never surfaced anywhere in the Flutter UI.
/// This is the single shared badge used everywhere a verified user or
/// group name is displayed.
class VerifiedBadge extends StatelessWidget {
  final double size;
  final Color? color;
  final VerifiedBadgeTone tone;

  const VerifiedBadge({
    super.key,
    this.size = 14,
    this.color,
    this.tone = VerifiedBadgeTone.brand,
  });

  const VerifiedBadge.onPrimary({
    super.key,
    this.size = 14,
  })  : color = null,
        tone = VerifiedBadgeTone.onPrimary;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Verified by CUT Safety',
        child: Icon(
          Icons.verified,
          size: size,
          color: _resolvedColor(context),
          shadows: tone == VerifiedBadgeTone.onPrimary
              ? const [
                  Shadow(
                    color: Colors.black26,
                    blurRadius: 2,
                    offset: Offset(0, 1),
                  ),
                ]
              : null,
        ),
      );

  Color _resolvedColor(BuildContext context) {
    if (color != null) return color!;
    return switch (tone) {
      VerifiedBadgeTone.brand => AppTheme.cutBlue,
      VerifiedBadgeTone.onPrimary => Theme.of(context).colorScheme.onPrimary,
    };
  }
}

/// Small inline row helper: name + optional verified badge, used in lists.
class NameWithBadge extends StatelessWidget {
  final String name;
  final bool isVerified;
  final TextStyle? style;
  final double badgeSize;
  const NameWithBadge({
    super.key,
    required this.name,
    required this.isVerified,
    this.style,
    this.badgeSize = 14,
  });

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
              child: Text(name, style: style, overflow: TextOverflow.ellipsis)),
          if (isVerified) ...[
            const SizedBox(width: 4),
            VerifiedBadge(size: badgeSize),
          ],
        ],
      );
}

/// Locked-group banner, shown at the top of a chat when
/// AdminGroupModel.IsLocked is true (GroupsController.Lock).
class GroupLockedBanner extends StatelessWidget {
  const GroupLockedBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Colors.orange.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          const Icon(Icons.lock_outline, size: 16, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This group has been locked by an administrator. New messages cannot be sent.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ),
        ]),
      );
}

/// Suspended-group banner, shown when AdminGroupModel.Status == 'suspended'.
class GroupSuspendedBanner extends StatelessWidget {
  const GroupSuspendedBanner({super.key});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Colors.red.withValues(alpha: 0.12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: const Row(children: [
          Icon(Icons.block, size: 16, color: Colors.red),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This group has been suspended by an administrator.',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ),
        ]),
      );
}
