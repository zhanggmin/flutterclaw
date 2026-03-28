/// SSRF (Server-Side Request Forgery) protection for web/HTTP tools.
///
/// Blocks requests to private IP ranges, loopback, link-local, and
/// cloud metadata endpoints to prevent LLM-directed network attacks.
library;

/// Returns true if [hostname] resolves to a private/restricted address
/// that should never be fetched by agent tools.
///
/// Covers:
/// - IPv4 private ranges: 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16
/// - Loopback: 127.0.0.0/8, ::1
/// - Link-local: 169.254.0.0/16 (AWS/GCP metadata endpoint lives here)
/// - Unique local (IPv6): fc00::/7
/// - Cloud metadata hostnames
bool isBlockedHostnameOrIp(String hostname) {
  final h = hostname.trim().toLowerCase();
  if (h.isEmpty) return true;

  // Block obvious metadata service hostnames
  if (_blockedHostnames.contains(h)) return true;

  // Try to parse as IPv4
  final ipv4 = _parseIPv4(h);
  if (ipv4 != null) return _isBlockedIPv4(ipv4);

  // Try to parse as IPv6 (strip brackets)
  final ipv6 = h.startsWith('[') && h.endsWith(']') ? h.substring(1, h.length - 1) : h;
  if (_looksLikeIPv6(ipv6)) return _isBlockedIPv6(ipv6);

  return false;
}

/// Validates a URL string for SSRF safety.
///
/// Returns null if the URL is safe. Returns an error message if blocked.
String? validateFetchUrl(String urlStr) {
  final trimmed = urlStr.trim();
  if (trimmed.isEmpty) return 'URL is empty';

  Uri uri;
  try {
    uri = Uri.parse(trimmed);
  } catch (_) {
    return 'Invalid URL: $urlStr';
  }

  // Only allow http/https schemes
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return 'Blocked: only http/https URLs are allowed (got ${uri.scheme}://)';
  }

  final host = uri.host;
  if (host.isEmpty) return 'Blocked: URL has no host';

  if (isBlockedHostnameOrIp(host)) {
    return 'Blocked: URL targets a private or restricted network address ($host)';
  }

  return null; // safe
}

// ---------------------------------------------------------------------------
// Private helpers
// ---------------------------------------------------------------------------

const _blockedHostnames = {
  'localhost',
  'metadata.google.internal',
  'metadata.internal',
  'instance-data',
  '169.254.169.254', // AWS/Azure/GCP metadata
  'fd00:ec2::254', // AWS IPv6 metadata
};

List<int>? _parseIPv4(String s) {
  final parts = s.split('.');
  if (parts.length != 4) return null;
  final octets = <int>[];
  for (final p in parts) {
    final v = int.tryParse(p);
    if (v == null || v < 0 || v > 255) return null;
    octets.add(v);
  }
  return octets;
}

bool _isBlockedIPv4(List<int> ip) {
  final a = ip[0], b = ip[1];

  // Loopback: 127.0.0.0/8
  if (a == 127) return true;
  // Private: 10.0.0.0/8
  if (a == 10) return true;
  // Private: 172.16.0.0/12
  if (a == 172 && b >= 16 && b <= 31) return true;
  // Private: 192.168.0.0/16
  if (a == 192 && b == 168) return true;
  // Link-local: 169.254.0.0/16 (metadata services)
  if (a == 169 && b == 254) return true;
  // Reserved/broadcast: 0.x.x.x
  if (a == 0) return true;
  // Class D/E multicast + reserved: 224-255.x.x.x
  if (a >= 224) return true;

  return false;
}

bool _looksLikeIPv6(String s) {
  return s.contains(':');
}

bool _isBlockedIPv6(String s) {
  final lower = s.toLowerCase();

  // Loopback ::1
  if (lower == '::1' || lower == '0:0:0:0:0:0:0:1') return true;
  // All-zeros ::
  if (lower == '::' || lower == '0:0:0:0:0:0:0:0') return true;
  // Unique local fc00::/7 (fc or fd prefix)
  if (lower.startsWith('fc') || lower.startsWith('fd')) return true;
  // Link-local fe80::/10
  if (lower.startsWith('fe8') || lower.startsWith('fe9') ||
      lower.startsWith('fea') || lower.startsWith('feb')) {
    return true;
  }
  // Multicast ff00::/8
  if (lower.startsWith('ff')) return true;

  return false;
}
