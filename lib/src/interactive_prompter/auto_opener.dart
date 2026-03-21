import 'dart:io';

/// Opens an artifact file using the OS-native default application.
///
/// - **Windows**: `start "" "<path>"`
/// - **macOS**: `open "<path>"`
/// - **Linux**: `xdg-open "<path>"`
///
/// Prints a warning if the platform is unrecognised or the command fails.
Future<void> openArtifact(String path) async {
  try {
    if (Platform.isWindows) {
      // 'start' is a cmd.exe built-in, so we must invoke via cmd.
      final result =
          await Process.run('cmd', ['/c', 'start', '', path]);
      if (result.exitCode != 0) {
        _warn(
            'Could not auto-open artifact on Windows ($path): exit code ${result.exitCode}.');
      }
    } else if (Platform.isMacOS) {
      final result = await Process.run('open', [path]);
      if (result.exitCode != 0) {
        _warn(
            'Could not auto-open artifact on macOS ($path): exit code ${result.exitCode}.');
      }
    } else if (Platform.isLinux) {
      final result = await Process.run('xdg-open', [path]);
      if (result.exitCode != 0) {
        _warn(
            'Could not auto-open artifact on Linux ($path): exit code ${result.exitCode}.');
      }
    } else {
      _warn('Auto-open is not supported on this platform. '
          'Please open $path manually.');
    }
  } catch (e) {
    _warn('Could not auto-open artifact ($path): $e');
  }
}

void _warn(String msg) {
  stderr.writeln('\x1B[33m$msg\x1B[0m');
}
