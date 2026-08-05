import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/group_model.dart';
import '../../providers/group_provider.dart';
import '../../providers/user_provider.dart';
import '../../services/firebase_service.dart';
import '../../theme/app_theme.dart';

class CreateGroupSheet extends StatefulWidget {
  const CreateGroupSheet({super.key});
  @override
  State<CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<CreateGroupSheet> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _desc = TextEditingController();
  GroupType _type = GroupType.open;

  // Group cover image chosen before creation
  File? _coverFile;
  bool _uploadingCover = false;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker()
        .pickImage(source: ImageSource.gallery, imageQuality: 80);
    if (picked != null && mounted) {
      setState(() => _coverFile = File(picked.path));
    }
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final user = context.read<UserProvider>().user;
    if (user == null) return;

    // 1. Create the group — provider now returns the new doc ID
    final newGroupId = await context.read<GroupProvider>().createGroup(
          adminId: user.id,
          adminName: user.name,
          name: _name.text,
          description: _desc.text,
          type: _type,
        );

    if (!mounted) return;

    if (newGroupId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to create group. Try again.'),
          backgroundColor: AppTheme.cutRed));
      return;
    }

    // 2. Upload cover image if one was selected
    if (_coverFile != null) {
      setState(() => _uploadingCover = true);
      try {
        await FirebaseService.instance
            .uploadGroupCover(newGroupId, _coverFile!);
      } catch (_) {
        // Non-fatal — group was created, image just didn't upload
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Group created, but cover image failed to upload.'),
              backgroundColor: Colors.orange));
        }
      } finally {
        if (mounted) setState(() => _uploadingCover = false);
      }
    }

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Group created!')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<GroupProvider>().isLoading || _uploadingCover;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                    child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                            color: AppTheme.cutBorder,
                            borderRadius: BorderRadius.circular(2)))),

                const Text('Create Group',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 20),

                // ── Cover image picker ──────────────────────────
                Center(
                  child: GestureDetector(
                    onTap: loading ? null : _pickImage,
                    child: Stack(children: [
                      Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppTheme.cutBlue.withValues(alpha: 0.08),
                          border: Border.all(
                              color: AppTheme.cutBlue.withValues(alpha: 0.3),
                              width: 2),
                          image: _coverFile != null
                              ? DecorationImage(
                                  image: FileImage(_coverFile!),
                                  fit: BoxFit.cover)
                              : null,
                        ),
                        child: _coverFile == null
                            ? const Icon(Icons.group_outlined,
                                size: 36, color: AppTheme.cutBlue)
                            : null,
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: const BoxDecoration(
                              color: AppTheme.cutBlue, shape: BoxShape.circle),
                          child: const Icon(Icons.camera_alt,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                    child: Text(
                  _coverFile != null
                      ? 'Tap to change'
                      : 'Add group icon (optional)',
                  style:
                      const TextStyle(fontSize: 11, color: AppTheme.cutMuted),
                )),
                const SizedBox(height: 20),

                // ── Name ───────────────────────────────────────────
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Group name *'),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 12),

                // ── Description ────────────────────────────────────
                TextFormField(
                  controller: _desc,
                  maxLines: 3,
                  decoration: const InputDecoration(
                      labelText: 'Description *', alignLabelWithHint: true),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
                const SizedBox(height: 16),

                // ── Privacy selector ───────────────────────────────
                Row(
                  children: GroupType.values.map((t) {
                    final sel = t == _type;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _type = t),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: sel ? AppTheme.cutBlue : AppTheme.cutGrey,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: sel
                                    ? AppTheme.cutBlue
                                    : AppTheme.cutBorder),
                          ),
                          child: Column(children: [
                            Icon(
                              t == GroupType.open
                                  ? Icons.lock_open
                                  : Icons.lock_outline,
                              color: sel ? Colors.white : AppTheme.cutMuted,
                            ),
                            const SizedBox(height: 4),
                            Text(t.label,
                                style: TextStyle(
                                    color:
                                        sel ? Colors.white : AppTheme.cutDark,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13)),
                            Text(
                              t == GroupType.open
                                  ? 'Anyone can join'
                                  : 'Admin approves',
                              style: TextStyle(
                                  color:
                                      sel ? Colors.white70 : AppTheme.cutMuted,
                                  fontSize: 10),
                            ),
                          ]),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                // ── Create button ──────────────────────────────────
                ElevatedButton(
                  onPressed: loading ? null : _submit,
                  child: loading
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2)),
                            const SizedBox(width: 10),
                            Text(_uploadingCover
                                ? 'Uploading image…'
                                : 'Creating…'),
                          ],
                        )
                      : const Text('Create Group'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
