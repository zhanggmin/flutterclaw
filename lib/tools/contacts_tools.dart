/// Contacts tools for FlutterClaw agents.
///
/// Search the device address book using flutter_contacts.
library;

import 'dart:convert';

import 'package:flutter_contacts/flutter_contacts.dart';
import 'registry.dart';

/// Search device contacts by name, phone number, or email.
class ContactsSearchTool extends Tool {
  @override
  String get name => 'contacts_search';

  @override
  String get description =>
      'Search the device address book for contacts matching a name, '
      'phone number, or email address. '
      'Returns up to 20 matching contacts with their display name, '
      'phone numbers, and email addresses. '
      'Requires contacts permission (will prompt the user if needed).\n\n'
      '**Android — SMS to a contact:** resolve the number from results, call '
      '`open_external_uri` with `smsto:<digits>` or `sms:<digits>?body=...`, then complete '
      'send with `ui_*` (wait → type if needed → tap Send in the device language).';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description':
                'Name, phone number, or email to search for (partial match).',
          },
        },
        'required': ['query'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final query = (args['query'] as String?)?.trim() ?? '';
    if (query.isEmpty) return ToolResult.error('query is required');

    try {
      final status = await FlutterContacts.permissions.request(PermissionType.read);
      final granted = status == PermissionStatus.granted || status == PermissionStatus.limited;
      if (!granted) {
        return ToolResult.error(
          'Contacts permission denied. '
          'Please grant contacts access in Settings.',
        );
      }

      final all = await FlutterContacts.getAll(
        properties: {ContactProperty.name, ContactProperty.phone, ContactProperty.email},
      );

      // Filter by query against name, phone numbers, and email addresses.
      final q = query.toLowerCase();
      final filtered = all.where((c) {
        if ((c.displayName ?? '').toLowerCase().contains(q)) return true;
        if (c.phones.any((p) => p.number.replaceAll(' ', '').contains(q))) return true;
        if (c.emails.any((e) => e.address.toLowerCase().contains(q))) return true;
        return false;
      }).toList();

      final limited = filtered.take(20).toList();

      final result = limited.map((c) {
        return {
          'id': c.id,
          'display_name': c.displayName ?? '',
          'phones': c.phones.map((p) => {
                'label': p.label.label.name,
                'number': p.number,
              }).toList(),
          'emails': c.emails.map((e) => {
                'label': e.label.label.name,
                'address': e.address,
              }).toList(),
        };
      }).toList();

      if (result.isEmpty) {
        return ToolResult.success(
          'No contacts found matching "$query".',
        );
      }

      return ToolResult.success(jsonEncode(result));
    } catch (e) {
      return ToolResult.error('Contacts error: $e');
    }
  }
}
