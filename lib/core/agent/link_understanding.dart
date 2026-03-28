/// Link understanding — auto-detects URLs in user messages and pre-fetches
/// their content before the LLM call.
///
/// Port of OpenClaw's link-understanding/detect.ts and runner.ts.
/// Injects fetched page summaries as additional context so the agent can
/// reason about shared links without an explicit "fetch this URL" instruction.
library;

import 'package:flutterclaw/services/ssrf_guard.dart';
import 'package:logging/logging.dart';

final _log = Logger('flutterclaw.link_understanding');

const int _kDefaultMaxLinks = 3;
const int _kDefaultMaxChars = 2000;

// Matches bare https?:// URLs not already wrapped in markdown link syntax.
final _markdownLinkRe = RegExp(r'\[[^\]]*\]\((https?://\S+?)\)', caseSensitive: false);
final _bareLinkRe = RegExp(r'https?://\S+', caseSensitive: false);

// ---------------------------------------------------------------------------
// Link extraction
// ---------------------------------------------------------------------------

/// Extracts up to [maxLinks] safe bare URLs from [message].
///
/// Strips Markdown link syntax first so only bare URLs outside `[text](url)`
/// constructs are considered. Deduplicates and filters SSRF-blocked hosts.
List<String> extractLinksFromMessage(
  String message, {
  int maxLinks = _kDefaultMaxLinks,
}) {
  final source = message.trim();
  if (source.isEmpty) return [];

  // Strip markdown links — replace the whole `[text](url)` with a space
  final sanitized = source.replaceAllMapped(_markdownLinkRe, (_) => ' ');

  final seen = <String>{};
  final results = <String>[];

  for (final match in _bareLinkRe.allMatches(sanitized)) {
    if (results.length >= maxLinks) break;
    final raw = match.group(0)?.trim();
    if (raw == null || raw.isEmpty) continue;
    // Strip trailing punctuation that may be part of the sentence
    final url = _stripTrailingPunctuation(raw);
    if (seen.contains(url)) continue;
    if (validateFetchUrl(url) != null) continue; // SSRF-blocked
    seen.add(url);
    results.add(url);
  }

  return results;
}

String _stripTrailingPunctuation(String url) {
  // Remove trailing . , ) ] > that are likely sentence punctuation
  return url.replaceAll(RegExp(r'[.,)\]>]+$'), '');
}

// ---------------------------------------------------------------------------
// Link fetching
// ---------------------------------------------------------------------------

/// Fetches each URL and returns a combined context string, or null if no
/// links are found / fetching is disabled / offline.
///
/// [fetchUrl] is an async function that returns the page content for a URL
/// (injected so the caller can reuse the existing WebFetchTool logic).
Future<String?> runLinkUnderstanding(
  String message, {
  required Future<String?> Function(String url) fetchUrl,
  int maxLinks = _kDefaultMaxLinks,
  int maxCharsPerPage = _kDefaultMaxChars,
}) async {
  final links = extractLinksFromMessage(message, maxLinks: maxLinks);
  if (links.isEmpty) return null;

  final parts = <String>[];

  for (final url in links) {
    try {
      final content = await fetchUrl(url);
      if (content == null || content.trim().isEmpty) continue;
      final truncated = content.length > maxCharsPerPage
          ? '${content.substring(0, maxCharsPerPage)}…'
          : content;
      parts.add('[Auto-fetched: $url]\n$truncated');
      _log.fine('Link understanding: fetched $url (${truncated.length} chars)');
    } catch (e) {
      _log.fine('Link understanding: failed to fetch $url: $e');
    }
  }

  if (parts.isEmpty) return null;
  return parts.join('\n\n---\n\n');
}
