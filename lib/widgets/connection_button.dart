import 'package:flutter/material.dart';
import '../models/connection_model.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';

/// Handles the full connect / pending / connected button lifecycle for
/// a user profile screen.
class ConnectionButton extends StatefulWidget {
  final String meUid, meName;
  final String? mePhotoUrl;
  final String otherUid, otherName;
  final String? otherPhotoUrl;
  const ConnectionButton({
    super.key,
    required this.meUid, required this.meName, this.mePhotoUrl,
    required this.otherUid, required this.otherName, this.otherPhotoUrl,
  });

  @override
  State<ConnectionButton> createState() => _ConnectionButtonState();
}

class _ConnectionButtonState extends State<ConnectionButton> {
  ConnectionStatus _status = ConnectionStatus.none;
  bool _loading = true;
  bool _busy = false;
  bool _errored = false;

  @override
  void initState() { super.initState(); _refresh(); }

  Future<void> _refresh() async {
    if (mounted) setState(() { _loading = true; _errored = false; });
    try {
      final s = await FirebaseService.instance.getConnectionStatus(widget.meUid, widget.otherUid);
      if (mounted) setState(() { _status = s; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _errored = true; });
    }
  }

  Future<void> _onTap() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      switch (_status) {
        case ConnectionStatus.none:
          await FirebaseService.instance.sendConnectionRequest(
            fromUid: widget.meUid, fromName: widget.meName, fromPhotoUrl: widget.mePhotoUrl,
            toUid: widget.otherUid, toName: widget.otherName, toPhotoUrl: widget.otherPhotoUrl,
          );
          if (mounted) {
            setState(() => _status = ConnectionStatus.pendingOutgoing);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request sent')));
          }
          break;
        case ConnectionStatus.pendingOutgoing:
          await FirebaseService.instance.cancelConnectionRequest(widget.meUid, widget.otherUid);
          if (mounted) {
            setState(() => _status = ConnectionStatus.none);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Request cancelled')));
          }
          break;
        case ConnectionStatus.pendingIncoming:
          await FirebaseService.instance.acceptConnectionRequest(widget.otherUid, widget.meUid);
          if (mounted) {
            setState(() => _status = ConnectionStatus.connected);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connected!')));
          }
          break;
        case ConnectionStatus.connected:
          final ok = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
            title: const Text('Remove connection?'),
            content: Text('Remove ${widget.otherName} from your connections?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cutRed),
                  onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
            ],
          ));
          if (ok == true) {
            await FirebaseService.instance.removeConnection(widget.meUid, widget.otherUid);
            if (mounted) setState(() => _status = ConnectionStatus.none);
          }
          break;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Action failed: $e'), backgroundColor: AppTheme.cutRed));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.meUid == widget.otherUid) return const SizedBox.shrink();

    if (_loading) {
      return SizedBox(width: 140, height: 42,
        child: DecoratedBox(
          decoration: BoxDecoration(color: AppTheme.cutGrey, borderRadius: BorderRadius.circular(21)),
          child: const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
        ),
      );
    }

    if (_errored) {
      return _Pill(
        onTap: _refresh,
        icon: Icons.refresh,
        label: 'Retry',
        background: AppTheme.cutGrey,
        foreground: AppTheme.cutMuted,
        border: AppTheme.cutBorder,
      );
    }

    // FIX: the "Connected" state used a transparent OutlinedButton, which
    // read as "plain and see-through". Every state now renders as a
    // solid, rounded pill with a subtle shadow — a consistent, modern
    // look instead of mixing outlined/filled styles across states.
    return switch (_status) {
      ConnectionStatus.none => _Pill(
        onTap: _busy ? null : _onTap, busy: _busy,
        icon: Icons.person_add_alt_1, label: 'Connect',
        background: AppTheme.cutBlue, foreground: Colors.white, elevated: true,
      ),
      ConnectionStatus.pendingOutgoing => _Pill(
        onTap: _busy ? null : _onTap, busy: _busy,
        icon: Icons.hourglass_top_rounded, label: 'Cancel Request',
        background: Colors.white, foreground: AppTheme.cutMuted, border: AppTheme.cutBorder,
      ),
      ConnectionStatus.pendingIncoming => _Pill(
        onTap: _busy ? null : _onTap, busy: _busy,
        icon: Icons.check_circle_rounded, label: 'Accept Request',
        background: AppTheme.cutBlue, foreground: Colors.white, elevated: true,
      ),
      ConnectionStatus.connected => _Pill(
        onTap: _busy ? null : _onTap, busy: _busy,
        icon: Icons.how_to_reg_rounded, label: 'Connected',
        background: Colors.green, foreground: Colors.white, elevated: true,
      ),
    };
  }
}

/// Shared modern pill button used for every connection state.
class _Pill extends StatelessWidget {
  final VoidCallback? onTap;
  final bool busy;
  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;
  final Color? border;
  final bool elevated;

  const _Pill({
    required this.onTap,
    this.busy = false,
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    this.border,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) => Material(
    color: background,
    borderRadius: BorderRadius.circular(21),
    elevation: elevated ? 1.5 : 0,
    shadowColor: elevated ? background.withOpacity(0.4) : Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(21),
      child: Container(
        height: 42,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(21),
          border: border != null ? Border.all(color: border!, width: 1.3) : null,
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (busy)
            SizedBox(width: 16, height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: foreground))
          else
            Icon(icon, size: 17, color: foreground),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(color: foreground, fontWeight: FontWeight.w700, fontSize: 13)),
        ]),
      ),
    ),
  );
}
