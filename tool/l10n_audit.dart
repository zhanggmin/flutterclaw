import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

typedef ArbMap = Map<String, Object?>;

void main(List<String> args) async {
  final repoRoot = Directory.current.path;
  final l10nDir = Directory(p.join(repoRoot, 'lib', 'l10n'));
  final templateFile = File(p.join(l10nDir.path, 'app_en.arb'));

  if (!await l10nDir.exists()) {
    stderr.writeln('Missing l10n dir: ${l10nDir.path}');
    exitCode = 2;
    return;
  }
  if (!await templateFile.exists()) {
    stderr.writeln('Missing template ARB: ${templateFile.path}');
    exitCode = 2;
    return;
  }

  final outPath = _readArg(args, '--out');
  final jsonOutPath = _readArg(args, '--json-out');
  final strict = args.contains('--strict');

  final templateArb = await _readArb(templateFile);
  final templateKeys = _arbValueKeys(templateArb).toList()..sort();

  final arbFiles = await l10nDir
      .list()
      .where((e) => e is File && e.path.endsWith('.arb'))
      .cast<File>()
      .toList();
  arbFiles.sort((a, b) => a.path.compareTo(b.path));

  final locales = <String, ArbAuditReport>{};

  for (final arbFile in arbFiles) {
    final base = p.basename(arbFile.path);
    if (!base.startsWith('app_') || base == 'app_en.arb') continue;
    final locale = base.replaceFirst('app_', '').replaceFirst('.arb', '');

    final arb = await _readArb(arbFile);
    final missingKeys = <String>[];
    for (final k in templateKeys) {
      if (!arb.containsKey(k)) missingKeys.add(k);
    }

    final englishLeftovers = <EnglishLeftover>[];
    for (final k in templateKeys) {
      if (_englishAllowedKeys.contains(k)) continue;
      final enVal = templateArb[k];
      final localVal = arb[k];
      if (enVal is! String || localVal is! String) continue;
      if (_isEnglishResidual(enVal, localVal)) {
        englishLeftovers.add(EnglishLeftover(key: k, value: localVal));
      }
    }

    locales[locale] = ArbAuditReport(
      file: p.relative(arbFile.path, from: repoRoot),
      missingKeys: missingKeys,
      englishLeftovers: englishLeftovers,
    );
  }

  final report = AuditReport(
    templateFile: p.relative(templateFile.path, from: repoRoot),
    templateKeyCount: templateKeys.length,
    locales: locales,
  );

  final text = report.toMarkdown();

  if (outPath != null) {
    await File(outPath).writeAsString(text);
  } else {
    stdout.writeln(text);
  }

  if (jsonOutPath != null) {
    await File(jsonOutPath).writeAsString(
      const JsonEncoder.withIndent('  ').convert(report.toJson()),
    );
  }

  if (strict) {
    final hasIssues = locales.values.any(
      (r) => r.missingKeys.isNotEmpty || r.englishLeftovers.isNotEmpty,
    );
    if (hasIssues) exitCode = 1;
  }
}

const _englishAllowedKeys = <String>{
  // Product + brand names are intentionally not localized.
  'appTitle',
  'telegram',
  'discord',
  'whatsAppTitle',

  // Common UI abbreviations.
  'ok',

  // This is a formatting string that is typically kept as-is.
  'appVersionSubtitle',

  // Prefix labels that may intentionally remain short/Latin.
  'idPrefix',

  // Widely used technical terms that are often intentionally kept in English.
  'agent',
  'agents',
  'chat',
  'emoji',
  'model',
  'modelId',
  'gateway',
  'host',
  'port',
  'tokenFieldLabel',
  'status',
  'version',
  'webChat',
  'modelLabel',
  'interval',
  'intervalMinutes',
  'viaProvider',

  // Internal channel names / technical labels.
  'channelApp',
  'channelCron',
  'channelHeartbeat',
  'channelSubagent',
  'channelSystem',

  // MCP transport label is a protocol name.
  'mcpTransport',
  'mcpToolsCount',

  // Commonly-abbreviated labels that may stay English.
  'messagesAbbrev',

  // Token/message counters often intentionally keep English unit words.
  'tokensCount',
  'messagesCount',

  // Common media type labels.
  'photoImage',
  'documentPdfTxt',

  // Some apps keep these short labels in English.
  'sessions',
  'sessionsCount',
  'pause',

  // Tool category labels / feature labels.
  'systemCategory',
  'toolScreenshots',
  'toolContacts',

  // Generic error prefix sometimes left as English.
  'errorGeneric',

  // Misc UI labels frequently kept as-is.
  'accountTooltip',
  'defaultBadge',
  'default_',
  'editAction',
  'restartGateway',
  'openAccess',
  'openBotFather',
  'providers',
  'start',
  'stop',
  'startFlutterClaw',
  'uptimeLabel',
  'maxTokens',

  // Sometimes identical across locales.
  'camera',
  'clawHubAccount',
  'toolSandboxShell',
};

String? _readArg(List<String> args, String name) {
  final idx = args.indexOf(name);
  if (idx == -1) return null;
  if (idx + 1 >= args.length) return null;
  return args[idx + 1];
}

Future<ArbMap> _readArb(File file) async {
  final raw = await file.readAsString();
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw FormatException('ARB is not a JSON object: ${file.path}');
  }
  return decoded.cast<String, Object?>();
}

Iterable<String> _arbValueKeys(ArbMap arb) sync* {
  for (final k in arb.keys) {
    if (k.startsWith('@')) continue;
    yield k;
  }
}

bool _isEnglishResidual(String enValue, String localValue) {
  if (localValue.trim().isEmpty) return false;

  // Strong signal: exact match to English template.
  if (localValue == enValue) return true;

  // Heuristic: common English phrases that should not appear in localized files.
  const mustNotContain = <String>[
    'Used only when',
    'Choose a chat model',
    'This model is for voice calls only',
    'Chat, agents, and background tasks',
    'Leave blank if no auth required',
    'Server URL',
    'space-separated',
  ];
  for (final phrase in mustNotContain) {
    if (localValue.contains(phrase)) return true;
  }

  // Heuristic: ASCII-heavy strings with English stopwords.
  final asciiLetters = RegExp(r'[A-Za-z]').allMatches(localValue).length;
  final nonSpace = localValue.replaceAll(RegExp(r'\s+'), '');
  if (nonSpace.isEmpty) return false;

  final asciiRatio = asciiLetters / nonSpace.length;
  if (asciiRatio < 0.65) return false;

  final lower = localValue.toLowerCase();
  const stopwords = <String>[
    ' the ',
    ' and ',
    ' only ',
    ' when ',
    ' used ',
    ' choose ',
    ' this ',
    ' that ',
    ' from ',
    ' for ',
    ' with ',
    ' without ',
    ' please ',
  ];
  var hits = 0;
  for (final w in stopwords) {
    if (lower.contains(w)) hits++;
    if (hits >= 2) return true;
  }
  return false;
}

class AuditReport {
  AuditReport({
    required this.templateFile,
    required this.templateKeyCount,
    required this.locales,
  });

  final String templateFile;
  final int templateKeyCount;
  final Map<String, ArbAuditReport> locales;

  Map<String, Object?> toJson() => {
        'templateFile': templateFile,
        'templateKeyCount': templateKeyCount,
        'locales': locales.map((k, v) => MapEntry(k, v.toJson())),
      };

  String toMarkdown() {
    final buf = StringBuffer();
    buf.writeln('## L10n audit report');
    buf.writeln();
    buf.writeln('- **template**: `$templateFile`');
    buf.writeln('- **templateKeys**: $templateKeyCount');
    buf.writeln('- **locales**: ${locales.length}');
    buf.writeln();

    final orderedLocales = locales.keys.toList()..sort();
    for (final locale in orderedLocales) {
      final r = locales[locale]!;
      buf.writeln('### $locale');
      buf.writeln('- **file**: `${r.file}`');
      buf.writeln('- **missingKeys**: ${r.missingKeys.length}');
      buf.writeln('- **englishLeftovers**: ${r.englishLeftovers.length}');

      if (r.missingKeys.isNotEmpty) {
        buf.writeln();
        buf.writeln('**Missing keys**');
        for (final k in r.missingKeys) {
          buf.writeln('- `$k`');
        }
      }

      if (r.englishLeftovers.isNotEmpty) {
        buf.writeln();
        buf.writeln('**English leftovers**');
        for (final e in r.englishLeftovers) {
          buf.writeln('- `${e.key}`: `${_truncate(e.value, 120)}`');
        }
      }

      buf.writeln();
    }

    return buf.toString();
  }
}

class ArbAuditReport {
  ArbAuditReport({
    required this.file,
    required this.missingKeys,
    required this.englishLeftovers,
  });

  final String file;
  final List<String> missingKeys;
  final List<EnglishLeftover> englishLeftovers;

  Map<String, Object?> toJson() => {
        'file': file,
        'missingKeys': missingKeys,
        'englishLeftovers': englishLeftovers.map((e) => e.toJson()).toList(),
      };
}

class EnglishLeftover {
  EnglishLeftover({required this.key, required this.value});

  final String key;
  final String value;

  Map<String, Object?> toJson() => {'key': key, 'value': value};
}

String _truncate(String s, int max) {
  if (s.length <= max) return s;
  return '${s.substring(0, max - 1)}…';
}
