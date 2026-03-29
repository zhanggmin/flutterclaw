/// Email service for FlutterClaw — SMTP send + lightweight IMAP read.
///
/// Uses the `mailer` package for SMTP.
/// IMAP is implemented inline using dart:io SecureSocket to avoid
/// pulling in `enough_mail` (conflicts with pointycastle ^3.x used by
/// the WhatsApp Noise protocol).
///
/// Credentials are stored securely via [SecureKeyStore].
library;

import 'dart:convert';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:mailer/mailer.dart' as smtp;
import 'package:mailer/smtp_server.dart' as smtp_server;

import 'secure_key_store.dart';

final _log = Logger('flutterclaw.email');

// ---------------------------------------------------------------------------
// Email Account model
// ---------------------------------------------------------------------------

/// Persisted SMTP/IMAP account configuration.
class EmailAccount {
  final String id;
  final String label;
  final String email;

  // SMTP
  final String smtpHost;
  final int smtpPort;
  final bool smtpSsl;

  // IMAP
  final String imapHost;
  final int imapPort;
  final bool imapSsl;

  const EmailAccount({
    required this.id,
    required this.label,
    required this.email,
    required this.smtpHost,
    this.smtpPort = 587,
    this.smtpSsl = true,
    required this.imapHost,
    this.imapPort = 993,
    this.imapSsl = true,
  });

  factory EmailAccount.fromJson(Map<String, dynamic> json) => EmailAccount(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        email: json['email'] as String,
        smtpHost: json['smtp_host'] as String,
        smtpPort: json['smtp_port'] as int? ?? 587,
        smtpSsl: json['smtp_ssl'] as bool? ?? true,
        imapHost: json['imap_host'] as String,
        imapPort: json['imap_port'] as int? ?? 993,
        imapSsl: json['imap_ssl'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'email': email,
        'smtp_host': smtpHost,
        'smtp_port': smtpPort,
        'smtp_ssl': smtpSsl,
        'imap_host': imapHost,
        'imap_port': imapPort,
        'imap_ssl': imapSsl,
      };

  /// Secure storage key for this account's password.
  String get _secretKey => 'email_$id';

  Future<void> savePassword(String password) =>
      SecureKeyStore.saveSecret(_secretKey, password);

  Future<String?> getPassword() => SecureKeyStore.getSecret(_secretKey);

  Future<void> deletePassword() => SecureKeyStore.deleteSecret(_secretKey);
}

// ---------------------------------------------------------------------------
// Lightweight IMAP client (text protocol over TLS socket)
// ---------------------------------------------------------------------------

class _ImapClient {
  SecureSocket? _socket;
  int _tag = 0;
  final StringBuffer _buffer = StringBuffer();

  Future<void> connect(String host, int port) async {
    _socket = await SecureSocket.connect(host, port);
    // Read greeting.
    await _readResponse('*');
  }

  Future<String> _command(String cmd) async {
    _tag++;
    final tag = 'A$_tag';
    final line = '$tag $cmd\r\n';
    _socket!.add(utf8.encode(line));
    return _readResponse(tag);
  }

  Future<String> _readResponse(String tag) async {
    _buffer.clear();
    await for (final chunk in _socket!) {
      _buffer.write(utf8.decode(chunk, allowMalformed: true));
      final full = _buffer.toString();
      // Check if we have the tagged completion line.
      if (tag == '*') {
        // Just read until we get a complete line.
        if (full.contains('\r\n')) return full;
      } else {
        // Look for "A<n> OK", "A<n> NO", or "A<n> BAD".
        final lines = full.split('\r\n');
        for (final l in lines) {
          if (l.startsWith('$tag ')) return full;
        }
      }
      // Safety: don't accumulate more than 512 KB.
      if (full.length > 512 * 1024) return full;
    }
    return _buffer.toString();
  }

  Future<String> login(String user, String pass) async {
    // Quote password to handle special characters.
    final escapedPass = pass.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
    return _command('LOGIN "$user" "$escapedPass"');
  }

  Future<String> select(String mailbox) => _command('SELECT "$mailbox"');

  Future<String> search(String criteria) => _command('SEARCH $criteria');

  Future<String> fetch(String sequence, String items) =>
      _command('FETCH $sequence ($items)');

  Future<String> list() => _command('LIST "" "*"');

  Future<void> logout() async {
    try {
      await _command('LOGOUT');
    } catch (_) {}
    try {
      await _socket?.close();
    } catch (_) {}
    _socket = null;
  }
}

// ---------------------------------------------------------------------------
// Email Service
// ---------------------------------------------------------------------------

/// Lightweight email service wrapping SMTP send and IMAP read.
class EmailService {
  /// Send an email via SMTP.
  Future<String> send({
    required EmailAccount account,
    required String to,
    required String subject,
    required String body,
    String? cc,
    String? bcc,
    bool isHtml = false,
  }) async {
    final password = await account.getPassword();
    if (password == null || password.isEmpty) {
      throw Exception(
        'No password stored for email account "${account.label}". '
        'Configure it in Settings → Email.',
      );
    }

    final smtpServer = smtp_server.SmtpServer(
      account.smtpHost,
      port: account.smtpPort,
      username: account.email,
      password: password,
      ssl: account.smtpSsl,
      allowInsecure: false,
    );

    final message = smtp.Message()
      ..from = smtp.Address(account.email, account.label)
      ..recipients.addAll(to.split(',').map((e) => e.trim()))
      ..subject = subject;

    if (cc != null && cc.isNotEmpty) {
      message.ccRecipients.addAll(cc.split(',').map((e) => e.trim()));
    }
    if (bcc != null && bcc.isNotEmpty) {
      message.bccRecipients.addAll(bcc.split(',').map((e) => e.trim()));
    }

    if (isHtml) {
      message.html = body;
    } else {
      message.text = body;
    }

    final result = await smtp.send(message, smtpServer);
    _log.info('Email sent to $to — ${result.mail.subject}');
    return 'Email sent successfully to $to.';
  }

  /// Read emails from IMAP inbox.
  ///
  /// Returns up to [limit] messages from [folder] (default INBOX).
  /// If [since] is provided, only messages after that date are returned.
  /// If [searchQuery] is provided, performs an IMAP TEXT search.
  Future<List<Map<String, dynamic>>> read({
    required EmailAccount account,
    String folder = 'INBOX',
    int limit = 10,
    DateTime? since,
    String? searchQuery,
  }) async {
    final password = await account.getPassword();
    if (password == null || password.isEmpty) {
      throw Exception(
        'No password stored for email account "${account.label}". '
        'Configure it in Settings → Email.',
      );
    }

    final client = _ImapClient();
    try {
      await client.connect(account.imapHost, account.imapPort);
      final loginResp = await client.login(account.email, password);
      if (loginResp.contains(' NO ') || loginResp.contains(' BAD ')) {
        throw Exception('IMAP login failed. Check credentials.');
      }

      await client.select(folder);

      // Build search criteria.
      final parts = <String>[];
      if (since != null) parts.add('SINCE ${_imapDate(since)}');
      if (searchQuery != null && searchQuery.isNotEmpty) {
        parts.add('TEXT "$searchQuery"');
      }
      final criteria = parts.isEmpty ? 'ALL' : parts.join(' ');
      final searchResp = await client.search(criteria);

      // Parse UIDs from "* SEARCH 1 2 3 ..." line.
      final uids = <int>[];
      for (final line in searchResp.split('\r\n')) {
        if (line.startsWith('* SEARCH')) {
          final nums = line.substring(8).trim().split(RegExp(r'\s+'));
          for (final n in nums) {
            final parsed = int.tryParse(n);
            if (parsed != null) uids.add(parsed);
          }
        }
      }

      if (uids.isEmpty) {
        await client.logout();
        return [];
      }

      // Take the last `limit` (most recent).
      final toFetch =
          uids.length > limit ? uids.sublist(uids.length - limit) : uids;
      final seqSet = toFetch.join(',');

      final fetchResp = await client.fetch(
        seqSet,
        'ENVELOPE BODY.PEEK[TEXT]<0.2000>',
      );

      final messages = _parseEnvelopes(fetchResp);
      await client.logout();
      return messages.reversed.toList();
    } catch (e) {
      try {
        await client.logout();
      } catch (_) {}
      rethrow;
    }
  }

  /// List IMAP mailbox folders.
  Future<List<String>> listFolders({
    required EmailAccount account,
  }) async {
    final password = await account.getPassword();
    if (password == null || password.isEmpty) {
      throw Exception(
        'No password stored for email account "${account.label}".',
      );
    }

    final client = _ImapClient();
    try {
      await client.connect(account.imapHost, account.imapPort);
      await client.login(account.email, password);
      final resp = await client.list();
      final folders = <String>[];
      for (final line in resp.split('\r\n')) {
        if (!line.startsWith('* LIST')) continue;
        // Format: * LIST (\Flags) "delimiter" "name"
        final match = RegExp(r'\* LIST \([^)]*\) "[^"]*" "?([^"\r]+)"?')
            .firstMatch(line);
        if (match != null) folders.add(match.group(1)!.trim());
      }
      await client.logout();
      return folders;
    } catch (e) {
      try {
        await client.logout();
      } catch (_) {}
      rethrow;
    }
  }

  /// Parse FETCH ENVELOPE responses into structured maps.
  List<Map<String, dynamic>> _parseEnvelopes(String raw) {
    final messages = <Map<String, dynamic>>[];
    // Split by "* <n> FETCH" boundaries.
    final blocks = raw.split(RegExp(r'\* \d+ FETCH'));
    for (final block in blocks) {
      if (block.trim().isEmpty) continue;
      final msg = <String, dynamic>{};

      // Extract ENVELOPE fields using quoted-string parsing.
      final envMatch =
          RegExp(r'ENVELOPE \((.+?)\)\s*(BODY|$)', dotAll: true)
              .firstMatch(block);
      if (envMatch != null) {
        final env = envMatch.group(1)!;
        // The ENVELOPE format is:
        // (date subject from sender reply-to to cc bcc in-reply-to message-id)
        // All are either NIL or quoted strings / parenthesized address lists.
        final parts = _splitEnvelopeParts(env);
        if (parts.length >= 6) {
          msg['date'] = _unquote(parts[0]);
          msg['subject'] = _decodeMimeHeader(_unquote(parts[1]));
          msg['from'] = _parseAddressList(parts[2]);
          msg['to'] = _parseAddressList(parts[5]);
        }
      }

      // Extract body text preview.
      final bodyMatch =
          RegExp(r'BODY\[TEXT\]<0> \{(\d+)\}\r?\n([\s\S]*)', dotAll: true)
              .firstMatch(block);
      if (bodyMatch != null) {
        var preview = bodyMatch.group(2) ?? '';
        // Strip HTML tags for a clean preview.
        preview = preview.replaceAll(RegExp(r'<[^>]+>'), ' ');
        preview = preview.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (preview.length > 500) preview = '${preview.substring(0, 500)}…';
        msg['preview'] = preview;
      } else {
        msg['preview'] = '';
      }

      if (msg.containsKey('subject')) messages.add(msg);
    }
    return messages;
  }

  /// Split ENVELOPE top-level parts respecting parens and quotes.
  List<String> _splitEnvelopeParts(String env) {
    final parts = <String>[];
    var depth = 0;
    var inQuote = false;
    var escaped = false;
    final current = StringBuffer();

    for (var i = 0; i < env.length; i++) {
      final c = env[i];
      if (escaped) {
        current.write(c);
        escaped = false;
        continue;
      }
      if (c == '\\' && inQuote) {
        escaped = true;
        current.write(c);
        continue;
      }
      if (c == '"') {
        inQuote = !inQuote;
        current.write(c);
        continue;
      }
      if (!inQuote) {
        if (c == '(') {
          depth++;
          if (depth == 1) {
            current.write(c);
            continue;
          }
        }
        if (c == ')') {
          depth--;
          if (depth == 0) {
            current.write(c);
            parts.add(current.toString().trim());
            current.clear();
            continue;
          }
        }
        if (c == ' ' && depth == 0 && current.isNotEmpty) {
          parts.add(current.toString().trim());
          current.clear();
          continue;
        }
      }
      current.write(c);
    }
    if (current.isNotEmpty) parts.add(current.toString().trim());
    return parts;
  }

  String _unquote(String s) {
    s = s.trim();
    if (s == 'NIL') return '';
    if (s.startsWith('"') && s.endsWith('"')) {
      return s.substring(1, s.length - 1);
    }
    return s;
  }

  /// Parse an IMAP address list like ((name NIL user host)(name NIL user host)).
  String _parseAddressList(String s) {
    s = s.trim();
    if (s == 'NIL') return '';
    final addrs = <String>[];
    final matches = RegExp(r'\(([^)]+)\)').allMatches(s);
    for (final m in matches) {
      final parts = _splitEnvelopeParts(m.group(1)!);
      if (parts.length >= 4) {
        final name = _unquote(parts[0]);
        final user = _unquote(parts[2]);
        final host = _unquote(parts[3]);
        final email = '$user@$host';
        addrs.add(name.isNotEmpty ? '$name <$email>' : email);
      }
    }
    return addrs.join(', ');
  }

  /// Decode MIME encoded-word headers (=?charset?encoding?text?=).
  String _decodeMimeHeader(String s) {
    return s.replaceAllMapped(
      RegExp(r'=\?([^?]+)\?([BbQq])\?([^?]+)\?='),
      (m) {
        final encoding = m.group(2)!.toUpperCase();
        final text = m.group(3)!;
        try {
          if (encoding == 'B') {
            return utf8.decode(base64.decode(text), allowMalformed: true);
          } else {
            // Q encoding: underscores are spaces, =XX is hex byte.
            final decoded = text.replaceAll('_', ' ').replaceAllMapped(
                  RegExp(r'=([0-9A-Fa-f]{2})'),
                  (hm) => String.fromCharCode(
                    int.parse(hm.group(1)!, radix: 16),
                  ),
                );
            return decoded;
          }
        } catch (_) {
          return text;
        }
      },
    );
  }

  /// Format date for IMAP SINCE clause (DD-Mon-YYYY).
  String _imapDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day}-${months[d.month - 1]}-${d.year}';
  }
}
