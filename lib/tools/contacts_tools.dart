/// Contacts tools for FlutterClaw agents.
///
/// Search, create, and update the device address book using flutter_contacts.
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

/// Create a new contact in the device address book.
class ContactsCreateTool extends Tool {
  @override
  String get name => 'contacts_create';

  @override
  String get description =>
      'Create a new contact in the device address book. '
      'Requires contacts permission (will prompt the user if needed).';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'first_name': {
            'type': 'string',
            'description': 'First / given name.',
          },
          'last_name': {
            'type': 'string',
            'description': 'Last / family name. Optional.',
          },
          'phones': {
            'type': 'array',
            'description': 'Phone numbers to add.',
            'items': {
              'type': 'object',
              'properties': {
                'number': {'type': 'string'},
                'label': {
                  'type': 'string',
                  'description': 'e.g. mobile, work, home. Default: mobile.',
                },
              },
              'required': ['number'],
            },
          },
          'emails': {
            'type': 'array',
            'description': 'Email addresses to add.',
            'items': {
              'type': 'object',
              'properties': {
                'address': {'type': 'string'},
                'label': {
                  'type': 'string',
                  'description': 'e.g. work, home, other. Default: work.',
                },
              },
              'required': ['address'],
            },
          },
          'company': {
            'type': 'string',
            'description': 'Company / organization name. Optional.',
          },
          'notes': {
            'type': 'string',
            'description': 'Free-form notes. Optional.',
          },
        },
        'required': ['first_name'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final firstName = (args['first_name'] as String?)?.trim() ?? '';
    if (firstName.isEmpty) return ToolResult.error('first_name is required');

    try {
      final status =
          await FlutterContacts.permissions.request(PermissionType.write);
      final granted = status == PermissionStatus.granted ||
          status == PermissionStatus.limited;
      if (!granted) {
        return ToolResult.error(
          'Contacts write permission denied. '
          'Please grant contacts access in Settings.',
        );
      }

      final contact = Contact(
        name: Name(first: firstName, last: (args['last_name'] as String?) ?? ''),
        phones: _parsePhones(args['phones']),
        emails: _parseEmails(args['emails']),
        organizations: [
          if (args['company'] != null)
            Organization(name: args['company'] as String),
        ],
        notes: [
          if (args['notes'] != null) Note(note: args['notes'] as String),
        ],
      );

      final savedId = await FlutterContacts.create(contact);
      return ToolResult.success(
        'Contact created: $firstName (id: $savedId)',
      );
    } catch (e) {
      return ToolResult.error('Failed to create contact: $e');
    }
  }

  List<Phone> _parsePhones(dynamic phones) {
    if (phones == null) return [];
    final list = phones as List<dynamic>;
    return list.map((p) {
      final map = p as Map<String, dynamic>;
      final label = _phoneLabel(map['label'] as String? ?? 'mobile');
      return Phone(number: map['number'] as String, label: label);
    }).toList();
  }

  List<Email> _parseEmails(dynamic emails) {
    if (emails == null) return [];
    final list = emails as List<dynamic>;
    return list.map((e) {
      final map = e as Map<String, dynamic>;
      final label = _emailLabel(map['label'] as String? ?? 'work');
      return Email(address: map['address'] as String, label: label);
    }).toList();
  }

  Label<PhoneLabel> _phoneLabel(String s) => switch (s.toLowerCase()) {
        'home' => const Label(PhoneLabel.home),
        'work' => const Label(PhoneLabel.work),
        'main' => const Label(PhoneLabel.main),
        _ => const Label(PhoneLabel.mobile),
      };

  Label<EmailLabel> _emailLabel(String s) => switch (s.toLowerCase()) {
        'home' => const Label(EmailLabel.home),
        'work' => const Label(EmailLabel.work),
        _ => const Label(EmailLabel.work),
      };
}

/// Update an existing contact in the device address book.
class ContactsUpdateTool extends Tool {
  @override
  String get name => 'contacts_update';

  @override
  String get description =>
      'Update an existing contact. Use contacts_search first to find the '
      'contact ID. Only the fields you provide will be overwritten; omitted '
      'fields are left unchanged.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'id': {
            'type': 'string',
            'description':
                'Contact ID (from contacts_search results).',
          },
          'first_name': {'type': 'string', 'description': 'New first name.'},
          'last_name': {'type': 'string', 'description': 'New last name.'},
          'phones': {
            'type': 'array',
            'description':
                'Replace all phone numbers with this list. '
                'Omit to keep existing phones.',
            'items': {
              'type': 'object',
              'properties': {
                'number': {'type': 'string'},
                'label': {'type': 'string'},
              },
              'required': ['number'],
            },
          },
          'emails': {
            'type': 'array',
            'description':
                'Replace all emails with this list. '
                'Omit to keep existing emails.',
            'items': {
              'type': 'object',
              'properties': {
                'address': {'type': 'string'},
                'label': {'type': 'string'},
              },
              'required': ['address'],
            },
          },
          'company': {'type': 'string', 'description': 'New company name.'},
          'notes': {'type': 'string', 'description': 'New notes.'},
        },
        'required': ['id'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final id = (args['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) return ToolResult.error('id is required');

    try {
      final status =
          await FlutterContacts.permissions.request(PermissionType.write);
      final granted = status == PermissionStatus.granted ||
          status == PermissionStatus.limited;
      if (!granted) {
        return ToolResult.error(
          'Contacts write permission denied. '
          'Please grant contacts access in Settings.',
        );
      }

      final contact = await FlutterContacts.get(
        id,
        properties: {
          ContactProperty.name,
          ContactProperty.phone,
          ContactProperty.email,
          ContactProperty.organization,
          ContactProperty.note,
        },
      );
      if (contact == null) {
        return ToolResult.error('Contact with id "$id" not found.');
      }

      // Build updated contact via copyWith.
      final helper = ContactsCreateTool();
      var updated = contact;

      if (args.containsKey('first_name') || args.containsKey('last_name')) {
        updated = updated.copyWith(
          name: Name(
            first: (args['first_name'] as String?) ?? contact.name?.first ?? '',
            last: (args['last_name'] as String?) ?? contact.name?.last ?? '',
          ),
        );
      }

      if (args.containsKey('phones')) {
        updated = updated.copyWith(
          phones: helper._parsePhones(args['phones']),
        );
      }

      if (args.containsKey('emails')) {
        updated = updated.copyWith(
          emails: helper._parseEmails(args['emails']),
        );
      }

      if (args.containsKey('company')) {
        updated = updated.copyWith(
          organizations: [Organization(name: args['company'] as String)],
        );
      }

      if (args.containsKey('notes')) {
        updated = updated.copyWith(
          notes: [Note(note: args['notes'] as String)],
        );
      }

      await FlutterContacts.update(updated);
      return ToolResult.success(
        'Contact updated: ${updated.displayName ?? id}',
      );
    } catch (e) {
      return ToolResult.error('Failed to update contact: $e');
    }
  }
}
