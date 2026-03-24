/// Sandbox shell tool — lets the agent execute Linux commands on the device.
///
/// Android: full execution via PRoot + Alpine ARM64 rootfs (auto-provisioned
/// on first use, full internet access, `apk add` works).
/// iOS: TinyEMU RISC-V emulator + Alpine 3.21 userspace via wazero/WAMR.
/// With C2WNet (wazero + gvisor-tap-vsock): full internet access.
/// With WAMR fallback: no internet, packages pre-installed at image build time.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutterclaw/services/sandbox_service.dart';
import 'package:flutterclaw/tools/registry.dart';

class RunShellCommandTool extends Tool {
  final SandboxService _svc;
  RunShellCommandTool(this._svc);

  @override
  String get name => 'run_shell_command';

  @override
  String get description =>
      'Execute a shell command in a sandboxed Linux (Alpine 3.21) environment.\n\n'
      'CAPABILITY: Before saying you cannot do something, try this tool first.\n'
      'This is a full Alpine Linux environment with internet access. You can:\n'
      '  - Run bash, Python, Node.js, Ruby, Perl, and other scripts\n'
      '  - Install any package: `apk add <pkg>`, `pip install <pkg>`, `npm install -g <pkg>`\n'
      '  - Download files, clone repos: curl, wget, git clone\n'
      '  - Parse, transform, compress, or encrypt data\n'
      '  - Call external APIs via curl or scripts\n'
      '  - Compile and run code in almost any language\n'
      'Never refuse a task that could be attempted here without trying first.\n\n'
      'IMPORTANT: This is an isolated Alpine Linux sandbox — NOT Android\'s shell.\n'
      'Android system commands (am, input, monkey, dumpsys, adb, getprop, etc.) do NOT exist here.\n'
      'For Android UI automation (tap, swipe, type text, screenshot, find elements), use the ui_* tools instead:\n'
      '  ui_tap, ui_swipe, ui_type_text, ui_find_elements, ui_click_element, ui_screenshot, ui_global_action\n\n'
      '=== ANDROID ===\n'
      'Runs in a PRoot sandbox (Alpine ARM64, native speed).\n'
      '`apk add <pkg>` downloads and installs at runtime — e.g. `apk add python3`, `apk add nodejs`.\n'
      'Full internet access from inside the sandbox (curl, wget, apk all work).\n'
      'Installed packages and files in /root/ persist across calls.\n\n'
      '=== iOS ===\n'
      'Runs in a TinyEMU RISC-V emulator (Alpine 3.21 userspace, ~10-100x slower than Android).\n'
      'NETWORKING:\n'
      '- Internet access is available: curl, wget, apk add, pip install, git clone all work.\n'
      '- DNS resolves via the virtual gateway (192.168.127.1).\n'
      '- Network operations are slower due to emulation — use longer timeout_ms (60000-120000).\n'
      'LIMITATIONS:\n'
      '- Architecture: riscv64 (not ARM64). `uname -m` returns riscv64.\n'
      '- Single-core CPU (no SMP). Parallel workloads do not benefit from multiple cores.\n'
      '- Performance: simple commands ~0.5-2s, python scripts ~2-10s, heavy operations minutes.\n'
      '- Pre-installed packages: python3, pip, git, curl, wget, jq, bash, file. Install more with `apk add`.\n'
      'FILE SHARING (host app <-> VM):\n'
      '- Call sandbox_status first to get shared_path.\n'
      '- Files written to shared_path by the host app are visible inside the VM at the same absolute path.\n'
      '- Files written by the VM to that path are readable by the host app.\n'
      '- Use this to pass input files into the VM or retrieve output files.\n'
      'Persistent filesystem: files in /root/ survive between calls (same as Android).';

  @override
  Map<String, dynamic> get parameters => {
        'type': 'object',
        'properties': {
          'command': {
            'type': 'string',
            'description': 'Shell command to execute (passed to sh -c).',
          },
          'timeout_ms': {
            'type': 'integer',
            'description':
                'Timeout in milliseconds (default 30000, max 120000).',
          },
          'working_dir': {
            'type': 'string',
            'description':
                'Working directory inside the sandbox (default /root).',
          },
        },
        'required': ['command'],
      };

  @override
  bool get supportsStreaming => true;

  @override
  Stream<String>? executeStream(Map<String, dynamic> args) async* {
    final command = args['command'] as String?;
    if (command == null || command.isEmpty) {
      yield '\x00CLEAR\x00${jsonEncode({"exit_code": 1, "stdout": "", "stderr": "Error: command is required", "timed_out": false})}';
      return;
    }

    final timeoutMs = (args['timeout_ms'] as num?)?.toInt() ?? 30000;
    if (timeoutMs < 1000 || timeoutMs > 120000) {
      yield '\x00CLEAR\x00${jsonEncode({"exit_code": 1, "stdout": "", "stderr": "Error: timeout_ms must be between 1000 and 120000", "timed_out": false})}';
      return;
    }

    final workingDir = args['working_dir'] as String?;

    // Check sandbox availability and auto-provision.
    final status = await _svc.status();
    if (status['error'] == true) {
      yield '\x00CLEAR\x00${jsonEncode({"exit_code": 1, "stdout": "", "stderr": status['message'] ?? 'Status check failed', "timed_out": false})}';
      return;
    }
    if (status['ready'] != true) {
      yield 'Setting up sandbox...\n';
      final setup = await _svc.setup();
      if (setup['error'] == true) {
        yield '\x00CLEAR\x00${jsonEncode({"exit_code": 1, "stdout": "", "stderr": "Sandbox setup failed: ${setup['message'] ?? 'unknown error'}", "timed_out": false})}';
        return;
      }
    }

    // Stream execution output via EventChannel
    final stdoutBuf = StringBuffer(); // ANSI-stripped — for LLM context
    final stderrBuf = StringBuffer(); // ANSI-stripped — for LLM context
    int exitCode = 0;
    bool timedOut = false;
    int chunkCount = 0;

    debugPrint('[SandboxTool] execStream starting for: $command');
    await for (final event in _svc.execStream(
      command: command,
      timeoutMs: timeoutMs,
      workingDir: workingDir,
    )) {
      final type = event['type'] as String?;
      debugPrint('[SandboxTool] event type=$type, keys=${event.keys.toList()}');
      if (type == 'stdout') {
        final data = event['data'] as String? ?? '';
        chunkCount++;
        debugPrint('[SandboxTool] stdout chunk #$chunkCount len=${data.length}');
        stdoutBuf.write(_stripAnsi(data)); // Strip ANSI for LLM
        yield _stripStreamNoise(data); // Noise-filtered for xterm
      } else if (type == 'stderr') {
        final data = event['data'] as String? ?? '';
        chunkCount++;
        debugPrint('[SandboxTool] stderr chunk #$chunkCount len=${data.length}');
        stderrBuf.write(_stripAnsi(data));
        yield _stripStreamNoise(data);
      } else if (type == 'exit') {
        exitCode = (event['exit_code'] as int?) ?? 0;
        timedOut = event['timed_out'] == true;
        debugPrint('[SandboxTool] exit code=$exitCode timedOut=$timedOut');
      }
    }

    debugPrint('[SandboxTool] stream done, $chunkCount chunks, stdout=${stdoutBuf.length} stderr=${stderrBuf.length}');
    // Final authoritative JSON (replaces accumulated text for the LLM)
    yield '\x00CLEAR\x00${jsonEncode({
      "exit_code": exitCode,
      "stdout": stdoutBuf.toString(),
      "stderr": stderrBuf.toString(),
      "timed_out": timedOut,
    })}';
  }

  // Strips TinyEMU serial noise from streaming output for the xterm widget:
  // - ash prompt/echo lines (e.g. "~ # cmd", "/root # cmd")
  // - internal wrapper commands (cd to workdir, echo sentinel)
  // - the exit sentinel itself (__WAMR_EXIT__<code>)
  // Preserves ANSI escape codes so xterm renders colors correctly.
  static final _streamPromptRe = RegExp(r'^[~/][^ ]*? # .*', multiLine: true);
  static final _sentinelRe = RegExp(r'__WAMR_EXIT__[^\n]*');
  static final _cdWrapperRe = RegExp(r"cd '[^']*' 2>/dev/null \|\| cd /root\r?\n?");
  static String _stripStreamNoise(String s) => s
      .replaceAll(_streamPromptRe, '')
      .replaceAll(_sentinelRe, '')
      .replaceAll(_cdWrapperRe, '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n');

  // Strips ANSI escape sequences and TinyEMU/ash prompt lines so the LLM
  // receives clean plain text. The xterm widget gets the raw output via yield.
  static final _ansiRe = RegExp(
    r'\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07]*\x07)',
  );
  // TinyEMU ash prompt pattern: "~ # " or "/path # " (no spaces in path).
  static final _promptRe = RegExp(r'^[~/][^ ]*? # .*', multiLine: true);
  static String _stripAnsi(String s) => s
      .replaceAll(_ansiRe, '')
      .replaceAll(_promptRe, '')
      .replaceAll(_sentinelRe, '')
      .replaceAll(_cdWrapperRe, '')
      .replaceAll('\r', '')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();

  @override
  Future<ToolResult> execute(Map<String, dynamic> args) async {
    final command = args['command'] as String?;
    if (command == null || command.isEmpty) {
      return ToolResult.error('command is required');
    }

    final timeoutMs = (args['timeout_ms'] as num?)?.toInt() ?? 30000;
    if (timeoutMs < 1000 || timeoutMs > 120000) {
      return ToolResult.error(
        'timeout_ms must be between 1000 and 120000',
      );
    }

    final workingDir = args['working_dir'] as String?;

    // Check sandbox availability and platform.
    final status = await _svc.status();
    if (status['error'] == true) {
      return ToolResult.error(status['message'] as String? ?? 'Status check failed');
    }
    // Auto-provision on first call.
    if (status['ready'] != true) {
      final setup = await _svc.setup();
      if (setup['error'] == true) {
        return ToolResult.error(
          'Sandbox setup failed: ${setup['message'] ?? 'unknown error'}\n'
          'Status: ${jsonEncode(status)}',
        );
      }
    }

    // Execute the command.
    final result = await _svc.exec(
      command: command,
      timeoutMs: timeoutMs,
      workingDir: workingDir,
    );
    if (result['error'] == true) {
      return ToolResult.error(
        result['message'] as String? ?? 'Execution failed',
      );
    }
    return ToolResult.success(jsonEncode(result));
  }
}
