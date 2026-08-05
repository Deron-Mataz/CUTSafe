import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user_model.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_theme.dart';

class EmergencyContactsScreen extends StatefulWidget {
  const EmergencyContactsScreen({super.key});
  @override
  State<EmergencyContactsScreen> createState() =>
      _EmergencyContactsScreenState();
}

class _EmergencyContactsScreenState extends State<EmergencyContactsScreen> {
  late List<EmergencyContact> _contacts;

  @override
  void initState() {
    super.initState();
    _contacts =
        List.from(context.read<UserProvider>().user?.emergencyContacts ?? []);
  }

  Future<void> _saveContacts() async {
    final prov = context.read<UserProvider>();
    final user = prov.user;
    if (user == null) return;
    final updated = user.copyWith(emergencyContacts: _contacts);
    await prov.updateProfile(name: updated.name, campus: updated.campus);
    // Save emergency contacts directly
    await prov.saveEmergencyContacts(_contacts);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Emergency contacts saved.')));
      Navigator.of(context).pop();
    }
  }

  void _addContact() {
    _showContactSheet();
  }

  void _editContact(int index) {
    _showContactSheet(existing: _contacts[index], index: index);
  }

  void _deleteContact(int index) {
    setState(() => _contacts.removeAt(index));
  }

  void _showContactSheet({EmergencyContact? existing, int? index}) {
    final nameCtrl = TextEditingController(text: existing?.name);
    final phoneCtrl = TextEditingController(text: existing?.phone);
    final relCtrl = TextEditingController(text: existing?.relationship);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final bottom = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(existing == null ? 'Add Contact' : 'Edit Contact',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Full name *',
                      prefixIcon: Icon(Icons.person_outline))),
              const SizedBox(height: 12),
              TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Phone number *',
                      prefixIcon: Icon(Icons.phone_outlined))),
              const SizedBox(height: 12),
              TextField(
                  controller: relCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Relationship (e.g. Parent, Friend)',
                      prefixIcon: Icon(Icons.people_outline))),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isEmpty ||
                      phoneCtrl.text.trim().isEmpty) {
                    return;
                  }
                  final contact = EmergencyContact(
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim(),
                    relationship: relCtrl.text.trim(),
                  );
                  setState(() {
                    if (index != null) {
                      _contacts[index] = contact;
                    } else {
                      _contacts.add(contact);
                    }
                  });
                  Navigator.of(ctx).pop();
                },
                child: Text(existing == null ? 'Add Contact' : 'Save'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loading = context.watch<UserProvider>().isLoading;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergency Contacts'),
        actions: [
          TextButton(
            onPressed: loading ? null : _saveContacts,
            child: const Text('Save',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addContact,
        backgroundColor: AppTheme.cutBlue,
        tooltip: 'Add Contact',
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: _contacts.isEmpty
          ? const Center(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  Icon(Icons.contacts_outlined,
                      size: 64, color: AppTheme.cutBorder),
                  SizedBox(height: 16),
                  Text('No emergency contacts yet',
                      style: TextStyle(color: AppTheme.cutMuted, fontSize: 15)),
                  SizedBox(height: 8),
                  Text('Tap + to add someone',
                      style: TextStyle(color: AppTheme.cutMuted, fontSize: 13)),
                ]))
          : ReorderableListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _contacts.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _contacts.removeAt(oldIndex);
                  _contacts.insert(newIndex, item);
                });
              },
              itemBuilder: (_, i) {
                final c = _contacts[i];
                return Card(
                  key: ValueKey(i),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppTheme.cutBlue.withValues(alpha: 0.1),
                      child: Text(c.name.isNotEmpty ? c.name[0] : '?',
                          style: const TextStyle(
                              color: AppTheme.cutBlue,
                              fontWeight: FontWeight.w700)),
                    ),
                    title: Text(c.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${c.relationship} · ${c.phone}'),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined,
                            size: 18, color: AppTheme.cutMuted),
                        onPressed: () => _editContact(i),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18, color: AppTheme.cutRed),
                        onPressed: () => _deleteContact(i),
                      ),
                    ]),
                  ),
                );
              },
            ),
    );
  }
}
