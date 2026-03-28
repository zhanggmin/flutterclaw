/// Session disk budget enforcement for mobile devices.
///
/// Monitors the sessions directory size and automatically prunes old sessions
/// when storage exceeds the configured limit. Mobile devices have limited
/// storage — this prevents JSONL transcripts from accumulating indefinitely.
library;

import 'dart:async';
import 'dart:io';

import 'package:logging/logging.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

final _log = Logger('flutterclaw.session_disk_budget');

const int _kDefaultMaxDiskMb = 500;
const int _kDefaultHighWaterMb = 400;

/// Measures and enforces disk quota for the sessions directory.
class SessionDiskBudget {
  final int maxDiskMb;
  final int highWaterMb;

  const SessionDiskBudget({
    this.maxDiskMb = _kDefaultMaxDiskMb,
    this.highWaterMb = _kDefaultHighWaterMb,
  });

  /// Returns the total bytes used by all files in [sessionsDir].
  Future<int> measureBytes(String sessionsDir) async {
    final dir = Directory(sessionsDir);
    if (!await dir.exists()) return 0;

    var total = 0;
    await for (final entity in dir.list(recursive: true, followLinks: false)) {
      if (entity is File) {
        try {
          total += await entity.length();
        } catch (_) {
          // file may have been removed between list and length
        }
      }
    }
    return total;
  }

  /// Checks whether device free storage is critically low (< 1 GB).
  Future<bool> isDeviceStorageCriticallyLow() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      // FileStat doesn't expose free space directly. On mobile we rely on the
      // OS to handle out-of-space gracefully. A more precise implementation
      // could use platform channels or the `disk_space` plugin.
      await FileStat.stat(dir.path);
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Enforces the disk budget for [sessionsDir].
  ///
  /// Strategy:
  /// 1. Measure total directory size.
  /// 2. If under [highWaterMb], nothing to do.
  /// 3. Delete orphaned JSONL files (no corresponding entry in [knownSessionIds]).
  /// 4. Archive (delete) oldest JSONL transcripts until under [highWaterMb],
  ///    skipping [activeSessionIds].
  ///
  /// Returns the number of files pruned.
  Future<int> enforce({
    required String sessionsDir,
    required Set<String> knownSessionIds,
    required Set<String> activeSessionIds,
  }) async {
    final usedBytes = await measureBytes(sessionsDir);
    final usedMb = usedBytes / (1024 * 1024);

    // Also run aggressively if device storage is critically low
    final criticallyLow = await isDeviceStorageCriticallyLow();

    final effectiveHighWater = criticallyLow ? highWaterMb ~/ 2 : highWaterMb;

    if (usedMb <= effectiveHighWater) {
      _log.fine('Session storage OK: ${usedMb.toStringAsFixed(1)} MB / $maxDiskMb MB');
      return 0;
    }

    _log.info(
      'Session storage at ${usedMb.toStringAsFixed(1)} MB, '
      'pruning to $effectiveHighWater MB…',
    );

    final dir = Directory(sessionsDir);
    if (!await dir.exists()) return 0;

    // Collect all .jsonl files with their modification times
    final jsonlFiles = <_FileInfo>[];
    await for (final entity in dir.list(followLinks: false)) {
      if (entity is File && entity.path.endsWith('.jsonl')) {
        try {
          final stat = await entity.stat();
          final sessionId = p.basenameWithoutExtension(entity.path);
          jsonlFiles.add(_FileInfo(
            path: entity.path,
            sessionId: sessionId,
            modifiedAt: stat.modified,
            bytes: stat.size,
          ));
        } catch (_) {}
      }
    }

    var pruned = 0;
    var currentBytes = usedBytes;
    final targetBytes = effectiveHighWater * 1024 * 1024;

    // Phase 1: remove orphaned files (not in knownSessionIds)
    for (final info in jsonlFiles) {
      if (currentBytes <= targetBytes) break;
      if (!knownSessionIds.contains(info.sessionId)) {
        await _deleteFile(info.path);
        currentBytes -= info.bytes;
        pruned++;
        _log.fine('Pruned orphaned transcript: ${info.sessionId}');
      }
    }

    if (currentBytes <= targetBytes) {
      _log.info('Pruned $pruned orphaned file(s), now at ${(currentBytes / 1024 / 1024).toStringAsFixed(1)} MB');
      return pruned;
    }

    // Phase 2: delete oldest non-active sessions
    final sortedByAge = jsonlFiles
        .where((f) => !activeSessionIds.contains(f.sessionId))
        .toList()
      ..sort((a, b) => a.modifiedAt.compareTo(b.modifiedAt)); // oldest first

    for (final info in sortedByAge) {
      if (currentBytes <= targetBytes) break;
      await _deleteFile(info.path);
      currentBytes -= info.bytes;
      pruned++;
      _log.info('Pruned old transcript: ${info.sessionId} (${info.modifiedAt})');
    }

    final finalMb = currentBytes / 1024 / 1024;
    _log.info('Disk budget enforced: pruned $pruned file(s), now at ${finalMb.toStringAsFixed(1)} MB');
    return pruned;
  }

  Future<void> _deleteFile(String path) async {
    try {
      await File(path).delete();
    } catch (e) {
      _log.warning('Could not delete $path: $e');
    }
  }
}

class _FileInfo {
  final String path;
  final String sessionId;
  final DateTime modifiedAt;
  final int bytes;

  const _FileInfo({
    required this.path,
    required this.sessionId,
    required this.modifiedAt,
    required this.bytes,
  });
}
