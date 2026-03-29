/// Open allowed system URIs and copy user-picked files into the workspace.
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import 'fs_tools.dart';
import 'registry.dart';

const _allowedUriSchemes = {
  'http',
  'https',
  'mailto',
  'tel',
  'sms',
  'smsto',
  'geo',
  'whatsapp',
};

/// Opens a user-agent URL (maps, dialer, email, SMS composer, https pages, etc.).
class OpenExternalUriTool extends Tool {
  @override
  String get name => 'open_external_uri';

  @override
  String get description =>
      'Open a URI in the user\'s default app (browser, phone, SMS composer, email, maps).\n\n'
      '**Android — finish with UI automation when the user asked to actually send:** '
      'after opening `sms:` or `smsto:` (or `mailto:`), do NOT stop at the composer. '
      'Wait briefly, use `ui_type_text` on the message field if the body is not already filled, '
      'then `ui_find_elements` / `ui_click_element` to tap the Send button (use the **device '
      'language** for the button label, e.g. Send / Enviar / Envoyer). Same idea for email send. '
      'Requires Accessibility permission.\n\n'
      '**iOS:** there is no `ui_tap`; the user usually sends manually or use Shortcuts.\n\n'
      'Allowed schemes: ${_allowedUriSchemes.join(", ")}.\n'
      'Examples: smsto:+15551234567, sms:+15551234567?body=Hello, '
      'https://wa.me/15551234567, mailto:a@b.com?subject=Hi, tel:+15551234567, geo:0,0?q=cafe';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'uri': {
            'type': 'string',
            'description': 'Full URI to open (must use an allowed scheme).',
          },
        },
        'required': ['uri'],
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    if (kIsWeb) {
      return ToolResult.error('open_external_uri is not available on web.');
    }
    final uriStr = (args['uri'] as String?)?.trim() ?? '';
    if (uriStr.isEmpty) return ToolResult.error('uri is required');
    final uri = Uri.tryParse(uriStr);
    if (uri == null || uri.scheme.isEmpty) {
      return ToolResult.error('Invalid uri');
    }
    if (!_allowedUriSchemes.contains(uri.scheme.toLowerCase())) {
      return ToolResult.error(
        'Scheme "${uri.scheme}" is not allowed. '
        'Use: ${_allowedUriSchemes.join(", ")}.',
      );
    }
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        return ToolResult.error('Could not launch URI (handler missing or blocked).');
      }
      return ToolResult.success('Opened: $uriStr');
    } catch (e) {
      return ToolResult.error('Launch failed: $e');
    }
  }
}

/// Picks a file via the system picker and copies it under [subdir] in the workspace.
class PickFileToWorkspaceTool extends WorkspaceTool {
  PickFileToWorkspaceTool(super.getWorkspacePath);

  @override
  String get name => 'pick_file_to_workspace';

  @override
  String get description =>
      'Prompt the user to pick a file; copy it into the workspace (default folder `inbox/`). '
      'Use for CSVs, documents, or attachments the agent should read with read_file.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'subdir': {
            'type': 'string',
            'description':
                'Workspace-relative directory (default "inbox"). Must not escape workspace.',
          },
        },
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    if (kIsWeb) {
      return ToolResult.error('pick_file_to_workspace is not available on web.');
    }
    final ws = await getWorkspacePath();
    final sub = ((args['subdir'] as String?)?.trim().isNotEmpty ?? false)
        ? (args['subdir'] as String).trim()
        : 'inbox';
    final destDir = await resolveWithinWorkspace(ws, sub);
    if (destDir == null) {
      return ToolResult.error('subdir must stay inside the workspace.');
    }
    await Directory(destDir).create(recursive: true);

    final pick = await FilePicker.platform.pickFiles();
    if (pick == null || pick.files.isEmpty) {
      return ToolResult.success('No file selected (cancelled).');
    }
    final f = pick.files.first;
    final srcPath = f.path;
    if (srcPath == null || srcPath.isEmpty) {
      return ToolResult.error('Could not access file path after pick.');
    }
    final baseName =
        f.name.isNotEmpty ? f.name : p.basename(srcPath);
    final resolvedDest = await resolveWithinWorkspace(ws, p.join(sub, baseName));
    if (resolvedDest == null) {
      return ToolResult.error('Resolved path left workspace.');
    }
    await File(srcPath).copy(resolvedDest);
    final rel = p.relative(resolvedDest, from: ws);
    return ToolResult.success('Copied to workspace: $rel');
  }
}

/// Picks an image from the gallery and saves it under [subdir] in the workspace.
class PickImageToWorkspaceTool extends WorkspaceTool {
  PickImageToWorkspaceTool(super.getWorkspacePath);

  final _picker = ImagePicker();

  @override
  String get name => 'pick_image_to_workspace';

  @override
  String get description =>
      'Prompt the user to pick an image from the gallery; save it under `inbox/` (or subdir). '
      'Returns workspace-relative path for read_file or vision workflows.';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'subdir': {
            'type': 'string',
            'description': 'Workspace-relative directory (default "inbox").',
          },
        },
      };

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    if (kIsWeb) {
      return ToolResult.error('pick_image_to_workspace is not available on web.');
    }
    final ws = await getWorkspacePath();
    final sub = ((args['subdir'] as String?)?.trim().isNotEmpty ?? false)
        ? (args['subdir'] as String).trim()
        : 'inbox';
    final destDir = await resolveWithinWorkspace(ws, sub);
    if (destDir == null) {
      return ToolResult.error('subdir must stay inside the workspace.');
    }
    await Directory(destDir).create(recursive: true);

    final xfile = await _picker.pickImage(source: ImageSource.gallery);
    if (xfile == null) {
      return ToolResult.success('No image selected (cancelled).');
    }
    final ext = p.extension(xfile.path);
    final safeExt = ext.isNotEmpty ? ext : '.jpg';
    final name =
        'picked_${DateTime.now().millisecondsSinceEpoch}$safeExt';
    final resolvedDest = await resolveWithinWorkspace(ws, p.join(sub, name));
    if (resolvedDest == null) {
      return ToolResult.error('Resolved path left workspace.');
    }
    await File(xfile.path).copy(resolvedDest);
    final rel = p.relative(resolvedDest, from: ws);
    return ToolResult.success('Saved image to workspace: $rel');
  }
}
