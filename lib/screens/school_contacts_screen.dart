import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/school_contact.dart';
import '../services/contact_service.dart';
import '../theme.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class SchoolContactsScreen extends StatefulWidget {
  final bool canEdit;

  const SchoolContactsScreen({super.key, required this.canEdit});

  @override
  State<SchoolContactsScreen> createState() => _SchoolContactsScreenState();
}

class _SchoolContactsScreenState extends State<SchoolContactsScreen> {
  final ContactService _contactService = ContactService();

  final List<String> _commonRoles = [
    'Principal',
    'Coordinator',
    'Class Teacher',
    'Front Office',
    'Counselor',
    'Bus Driver',
    'Librarian',
    'Accountant',
    'Custom Role'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('School Contacts'),
        actions: widget.canEdit
            ? [
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () => _showContactDialog(),
                ),
              ]
            : null,
      ),
      body: StreamBuilder<List<SchoolContact>>(
        stream: _contactService.getContacts(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final contacts = snapshot.data ?? [];
          if (contacts.isEmpty) {
            return const Center(child: Text('No contacts found.'));
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: contacts.length,
            itemBuilder: (context, index) {
              final contact = contacts[index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  title: Text(
                    contact.name.isEmpty ? contact.role : contact.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (contact.name.isNotEmpty)
                            Text(
                              contact.role,
                              style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w500),
                            ),
                          if (contact.isKey) ...[
                            if (contact.name.isNotEmpty) const SizedBox(width: 8),
                            const Icon(Icons.star, color: Colors.amber, size: 16),
                            const Text(' Key', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                          ],
                        ],
                      ),
                      Text(contact.phoneNumber),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.phone, color: AppTheme.success),
                        onPressed: () => _makeCall(contact.phoneNumber),
                      ),
                      IconButton(
                        icon: const FaIcon(FontAwesomeIcons.whatsapp, color: Colors.green),
                        onPressed: () => _openWhatsApp(contact.phoneNumber),
                      ),
                      if (widget.canEdit)
                        IconButton(
                          icon: const Icon(Icons.edit, color: AppTheme.primary),
                          onPressed: () => _showContactDialog(contact: contact),
                        ),
                    ],
                  ),
                  onLongPress: widget.canEdit
                      ? () => _deleteContact(contact)
                      : null,
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _makeCall(String phoneNumber) async {
    final Uri url = Uri.parse('tel:$phoneNumber');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Future<void> _openWhatsApp(String phoneNumber) async {
    // Remove non-numeric characters for the URL
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'\D'), '');
    final Uri url = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _showContactDialog({SchoolContact? contact}) {
    final nameController = TextEditingController(text: contact?.name);
    final phoneController = TextEditingController(text: contact?.phoneNumber);
    final roleController = TextEditingController(text: contact?.role);

    String? selectedRole = contact != null
        ? (_commonRoles.contains(contact.role) ? contact.role : 'Custom Role')
        : null;

    bool isCustomRole = selectedRole == 'Custom Role';
    bool isKey = contact?.isKey ?? false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(contact == null ? 'Add Contact' : 'Edit Contact'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: phoneController,
                  decoration: const InputDecoration(labelText: 'Phone Number*', hintText: 'e.g. +919876543210'),
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  decoration: const InputDecoration(labelText: 'Role*'),
                  items: _commonRoles.map((role) {
                    return DropdownMenuItem(value: role, child: Text(role));
                  }).toList(),
                  onChanged: (val) {
                    setDialogState(() {
                      selectedRole = val;
                      isCustomRole = val == 'Custom Role';
                      if (!isCustomRole && val != null) {
                        roleController.text = val;
                      }
                    });
                  },
                ),
                if (isCustomRole) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: roleController,
                    decoration: const InputDecoration(labelText: 'Custom Role*', hintText: 'Enter role title'),
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name (Optional)', hintText: 'Enter name'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Key Contact'),
                  subtitle: const Text('Display in Guardian Dashboard'),
                  value: isKey,
                  onChanged: (val) => setDialogState(() => isKey = val),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final roleToSave = isCustomRole ? roleController.text : selectedRole;

                if (phoneController.text.isNotEmpty && roleToSave != null && roleToSave.isNotEmpty) {
                  final newContact = SchoolContact(
                    id: contact?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
                    name: nameController.text.trim(),
                    phoneNumber: phoneController.text.trim(),
                    role: roleToSave.trim(),
                    isKey: isKey,
                  );
                  await _contactService.saveContact(newContact);
                  if (mounted) Navigator.pop(context);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Phone number and Role are required')),
                  );
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteContact(SchoolContact contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Contact'),
        content: Text('Are you sure you want to delete ${contact.name.isEmpty ? contact.role : contact.name}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _contactService.deleteContact(contact.id);
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: AppTheme.danger)),
          ),
        ],
      ),
    );
  }
}
