import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/user_provider.dart';
import '../services/firebase_service.dart';
import '../theme/app_theme.dart';

/// EXTEND: mirrors backend ReportModel / Reports Centre.
/// The Admin Dashboard has a full Reports Centre (PendingReview →
/// UnderInvestigation → Resolved/Dismissed) but the mobile app previously
/// only had ad-hoc "report" counters on alerts. This dialog creates a
/// proper `reports` document so reports for posts, users, groups, and
/// incidents all surface in the same Admin Reports Centre with reason,
/// description, and reporter identity — matching ReportModel exactly.
///
/// Usage:
///   showReportDialog(context, itemType: 'post', itemId: post.id, itemName: post.title);
Future<void> showReportDialog(
  BuildContext context, {
  required String itemType, // post | user | group | incident
  required String itemId,
  required String itemName,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => _ReportSheet(itemType: itemType, itemId: itemId, itemName: itemName),
  );
}

const _reasons = [
  'Harassment or bullying',
  'Hate speech',
  'False information',
  'Inappropriate content',
  'Spam',
  'Impersonation',
  'Threat of violence',
  'Other',
];

class _ReportSheet extends StatefulWidget {
  final String itemType, itemId, itemName;
  const _ReportSheet({required this.itemType, required this.itemId, required this.itemName});
  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  String? _reason;
  final _desc = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() { _desc.dispose(); super.dispose(); }

  Future<void> _submit() async {
    if (_reason == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select a reason.')));
      return;
    }
    final user = context.read<UserProvider>().user;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      await FirebaseService.instance.submitReport(
        itemType: widget.itemType,
        itemId: widget.itemId,
        itemName: widget.itemName,
        reportedById: user.id,
        reportedByName: user.name,
        reason: _reason!,
        description: _desc.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Report submitted. Our team will review it shortly.'),
          backgroundColor: Colors.green,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to submit report: $e'), backgroundColor: AppTheme.cutRed));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(child: Container(width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(color: AppTheme.cutBorder, borderRadius: BorderRadius.circular(2)))),
            Row(children: [
              const Icon(Icons.flag_outlined, color: AppTheme.cutRed),
              const SizedBox(width: 8),
              Text('Report ${widget.itemType}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 16),
            const Text('Reason', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: _reasons.map((r) {
              final sel = r == _reason;
              return ChoiceChip(
                label: Text(r), selected: sel,
                onSelected: (_) => setState(() => _reason = r),
                selectedColor: AppTheme.cutRed,
                labelStyle: TextStyle(color: sel ? Colors.white : AppTheme.cutDark, fontSize: 12),
              );
            }).toList()),
            const SizedBox(height: 16),
            TextField(
              controller: _desc, maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Additional details (optional)', alignLabelWithHint: true),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.cutRed,
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _submitting
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Submit Report', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}
