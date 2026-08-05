import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/app_theme.dart';

// ─── UserAvatar ───────────────────────────────────────────────────
/// Shows a cached network photo or falls back to initials.
class UserAvatar extends StatelessWidget {
  final String? photoUrl;
  final String initials;
  final double radius;

  const UserAvatar({
    super.key,
    this.photoUrl,
    required this.initials,
    this.radius = 20,
  });

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppTheme.cutBlue.withValues(alpha: 0.15),
      child: photoUrl != null && photoUrl!.isNotEmpty
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: photoUrl!,
                width: radius * 2,
                height: radius * 2,
                fit: BoxFit.cover,
                placeholder: (_, __) => _initials(),
                errorWidget: (_, __, ___) => _initials(),
              ),
            )
          : _initials(),
    );
  }

  Widget _initials() => Text(
        initials,
        style: TextStyle(
          fontSize: radius * 0.7,
          fontWeight: FontWeight.w700,
          color: AppTheme.cutBlue,
        ),
      );
}

// ─── TimeAgoText ─────────────────────────────────────────────────
class TimeAgoText extends StatelessWidget {
  final DateTime dateTime;
  final TextStyle? style;
  const TimeAgoText(this.dateTime, {super.key, this.style});

  String _fmt() {
    final d = DateTime.now().difference(dateTime);
    if (d.inSeconds < 60) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    if (d.inDays < 7) return '${d.inDays}d ago';
    return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
  }

  @override
  Widget build(BuildContext context) => Text(
        _fmt(),
        style: style ?? const TextStyle(fontSize: 12, color: AppTheme.cutMuted),
      );
}

// ─── CategoryBadge ───────────────────────────────────────────────
class CategoryBadge extends StatelessWidget {
  final String label;
  final Color color;
  const CategoryBadge({super.key, required this.label, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600, color: color)),
      );
}

// ─── LocationRow ─────────────────────────────────────────────────
class LocationRow extends StatelessWidget {
  final String location;
  const LocationRow(this.location, {super.key});

  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.location_on_outlined,
            size: 13, color: AppTheme.cutMuted),
        const SizedBox(width: 3),
        Flexible(
            child: Text(location,
                style: const TextStyle(fontSize: 12, color: AppTheme.cutMuted),
                overflow: TextOverflow.ellipsis)),
      ]);
}

// ─── EmptyState ──────────────────────────────────────────────────
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const EmptyState(
      {super.key,
      required this.icon,
      required this.title,
      required this.subtitle});

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 56, color: AppTheme.cutBorder),
            const SizedBox(height: 16),
            Text(title,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.cutMuted)),
            const SizedBox(height: 6),
            Text(subtitle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppTheme.cutMuted)),
          ]),
        ),
      );
}

// ─── SectionHeader ───────────────────────────────────────────────
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? action;
  const SectionHeader(this.title, {super.key, this.action});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.cutMuted,
                    letterSpacing: 0.8)),
            if (action != null) action!,
          ],
        ),
      );
}
