import 'dart:io';

/// Opens an artifact file using the OS-native default application.
///
/// - **Windows**: `start "" "<path>"`
/// - **macOS**: `open "<path>"`
/// - **Linux**: `xdg-open "<path>"`
///
/// Prints a warning if the platform is unrecognised or the command fails.
void openArtifact(String path) {
  try {
    if (Platform.isWindows) {
      // 'start' is a cmd.exe built-in, so we must invoke via cmd.
      Process.run('cmd', ['/c', 'start', '', path]);
    } else if (Platform.isMacOS) {
      Process.run('open', [path]);
    } else if (Platform.isLinux) {
      Process.run('xdg-open', [path]);
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
