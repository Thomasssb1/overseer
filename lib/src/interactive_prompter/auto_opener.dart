import 'dart:io';

/// Opens an artifact file using the OS-native default application.
///
/// - **Windows**: `start "" "<path>"`
/// - **macOS**: `open "<path>"`
/// - **Linux**: `xdg-open "<path>"`
///
/// Prints a warning if the platform is unrecognised or the command fails.
Future<void> openArtifact(
  String path, {
  String? operatingSystem,
  Future<ProcessResult> Function(String, List<String>)? processRunner,
  void Function(String)? warningPrinter,
}) async {
  final platform = operatingSystem ?? Platform.operatingSystem;
  final runProcess = processRunner ?? Process.run;
  final warn = warningPrinter ?? _warn;
  try {
    if (platform == 'windows') {
      // 'start' is a cmd.exe built-in, so we must invoke via cmd.
      final result = await runProcess('cmd', ['/c', 'start', '', path]);
      if (result.exitCode != 0) {
        warn(
            'Could not auto-open artifact on Windows ($path): exit code ${result.exitCode}.');
      }
    } else if (platform == 'macos') {
      final result = await runProcess('open', [path]);
      if (result.exitCode != 0) {
        warn(
            'Could not auto-open artifact on macOS ($path): exit code ${result.exitCode}.');
      }
    } else if (platform == 'linux') {
      final result = await runProcess('xdg-open', [path]);
      if (result.exitCode != 0) {
        warn(
            'Could not auto-open artifact on Linux ($path): exit code ${result.exitCode}.');
      }
    } else {
      warn('Auto-open is not supported on this platform. '
          'Please open $path manually.');
    }
  } catch (e) {
    warn('Could not auto-open artifact ($path): $e');
  }
}

void _warn(String msg) {
  stderr.writeln('\x1B[33m$msg\x1B[0m');
}
