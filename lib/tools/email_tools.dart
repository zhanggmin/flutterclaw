/// Email tools for FlutterClaw agents.
///
/// Provides `email_send` (SMTP) and `email_read` (IMAP) tools,
/// plus `email_folders` for listing mailbox folders.
library;

import 'dart:convert';

import '../services/email_service.dart';
import 'registry.dart';

/// Send an email via SMTP.
class EmailSendTool extends Tool {
  final List<EmailAccount> Function() _accountsGetter;

  EmailSendTool(this._accountsGetter);

  @override
  String get name => 'email_send';

  @override
  String get description =>
      'Send an email via SMTP. Requires an email account configured in '
      'Settings → Email with valid SMTP credentials.\n\n'
      'Supports plain text and HTML bodies, CC, and BCC.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'to': {
            'type': 'string',
            'description':
                'Recipient email address(es), comma-separated for multiple.',
          },
          'subject': {
            'type': 'string',
            'description': 'Email subject line.',
          },
          'body': {
            'type': 'string',
            'description': 'Email body text.',
          },
          'account_id': {
            'type': 'string',
            'description':
                'Email account ID to send from. Omit to use the first '
                'configured account.',
          },
          'cc': {
            'type': 'string',
            'description': 'CC recipients, comma-separated. Optional.',
          },
          'bcc': {
            'type': 'string',
            'description': 'BCC recipients, comma-separated. Optional.',
          },
          'html': {
            'type': 'boolean',
            'description':
                'If true, body is treated as HTML. Default: false (plain text).',
          },
        },
        'required': ['to', 'subject', 'body'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final to = (args['to'] as String?)?.trim() ?? '';
    final subject = (args['subject'] as String?)?.trim() ?? '';
    final body = (args['body'] as String?) ?? '';
    final accountId = args['account_id'] as String?;
    final cc = args['cc'] as String?;
    final bcc = args['bcc'] as String?;
    final isHtml = args['html'] == true;

    if (to.isEmpty) return ToolResult.error('"to" is required.');
    if (subject.isEmpty) return ToolResult.error('"subject" is required.');

    final accounts = _accountsGetter();
    if (accounts.isEmpty) {
      return ToolResult.error(
        'No email accounts configured. '
        'Add one in Settings → Email first.',
      );
    }

    final account = accountId != null
        ? accounts.where((a) => a.id == accountId).firstOrNull
        : accounts.first;
    if (account == null) {
      return ToolResult.error(
        'Email account "$accountId" not found. '
        'Available: ${accounts.map((a) => a.id).join(", ")}',
      );
    }

    try {
      final result = await EmailService().send(
        account: account,
        to: to,
        subject: subject,
        body: body,
        cc: cc,
        bcc: bcc,
        isHtml: isHtml,
      );
      return ToolResult.success(result);
    } catch (e) {
      return ToolResult.error('Email send failed: $e');
    }
  }
}

/// Read emails from an IMAP mailbox.
class EmailReadTool extends Tool {
  final List<EmailAccount> Function() _accountsGetter;

  EmailReadTool(this._accountsGetter);

  @override
  String get name => 'email_read';

  @override
  String get description =>
      'Read emails from an IMAP mailbox. Returns subject, from, to, date, '
      'and a text preview for each message.\n\n'
      'Supports searching by keyword and filtering by date. '
      'Requires an email account configured in Settings → Email.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'account_id': {
            'type': 'string',
            'description':
                'Email account ID. Omit to use the first configured account.',
          },
          'folder': {
            'type': 'string',
            'description':
                'Mailbox folder to read from. Default: "INBOX". '
                'Use email_folders to discover available folders.',
          },
          'limit': {
            'type': 'integer',
            'description': 'Max number of messages to return (1-50). Default: 10.',
          },
          'search': {
            'type': 'string',
            'description':
                'Search query — matches against message text (IMAP TEXT search).',
          },
          'since': {
            'type': 'string',
            'description':
                'Only return messages since this date (ISO 8601, e.g. "2026-03-01").',
          },
        },
        'required': [],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final accountId = args['account_id'] as String?;
    final folder = (args['folder'] as String?)?.trim().toUpperCase();
    final limit = (args['limit'] as int?) ?? 10;
    final searchQuery = args['search'] as String?;
    final sinceStr = args['since'] as String?;

    final accounts = _accountsGetter();
    if (accounts.isEmpty) {
      return ToolResult.error(
        'No email accounts configured. '
        'Add one in Settings → Email first.',
      );
    }

    final account = accountId != null
        ? accounts.where((a) => a.id == accountId).firstOrNull
        : accounts.first;
    if (account == null) {
      return ToolResult.error(
        'Email account "$accountId" not found. '
        'Available: ${accounts.map((a) => a.id).join(", ")}',
      );
    }

    DateTime? since;
    if (sinceStr != null) {
      since = DateTime.tryParse(sinceStr);
      if (since == null) {
        return ToolResult.error(
          'Invalid date format for "since". Use ISO 8601 (e.g. "2026-03-01").',
        );
      }
    }

    try {
      final messages = await EmailService().read(
        account: account,
        folder: folder ?? 'INBOX',
        limit: limit.clamp(1, 50),
        since: since,
        searchQuery: searchQuery,
      );

      if (messages.isEmpty) {
        return ToolResult.success('No messages found.');
      }

      return ToolResult.success(
        const JsonEncoder.withIndent('  ').convert(messages),
      );
    } catch (e) {
      return ToolResult.error('Email read failed: $e');
    }
  }
}

/// List IMAP mailbox folders.
class EmailFoldersTool extends Tool {
  final List<EmailAccount> Function() _accountsGetter;

  EmailFoldersTool(this._accountsGetter);

  @override
  String get name => 'email_folders';

  @override
  String get description =>
      'List available mailbox folders (INBOX, Sent, Drafts, etc.) '
      'for an email account.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'account_id': {
            'type': 'string',
            'description':
                'Email account ID. Omit to use the first configured account.',
          },
        },
        'required': [],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final accountId = args['account_id'] as String?;

    final accounts = _accountsGetter();
    if (accounts.isEmpty) {
      return ToolResult.error(
        'No email accounts configured. '
        'Add one in Settings → Email first.',
      );
    }

    final account = accountId != null
        ? accounts.where((a) => a.id == accountId).firstOrNull
        : accounts.first;
    if (account == null) {
      return ToolResult.error(
        'Email account "$accountId" not found.',
      );
    }

    try {
      final folders = await EmailService().listFolders(account: account);
      return ToolResult.success(jsonEncode(folders));
    } catch (e) {
      return ToolResult.error('Failed to list folders: $e');
    }
  }
}
