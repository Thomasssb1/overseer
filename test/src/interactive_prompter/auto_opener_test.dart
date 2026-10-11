import 'dart:io';

import 'package:overseer/src/interactive_prompter/auto_opener.dart';
import 'package:test/test.dart';

void main() {
  for (final (platform, executable, prefix, displayName) in [
    ('windows', 'cmd', ['/c', 'start', ''], 'Windows'),
    ('macos', 'open', <String>[], 'macOS'),
    ('linux', 'xdg-open', <String>[], 'Linux'),
  ]) {
    group(platform, () {
      for (final artifactPath in [
        'artifact.mp4',
        'review output/clip with spaces.mp4',
        r'C:\review output\clip (final) & audio.mp4',
        'review output/café 🎬.mp4',
      ]) {
        test('passes the complete path as one argument: $artifactPath',
            () async {
          final calls = <(String, List<String>)>[];
          final warnings = <String>[];

          await openArtifact(
            artifactPath,
            operatingSystem: platform,
            processRunner: (command, arguments) async {
              calls.add((command, List.of(arguments)));
              return ProcessResult(1, 0, '', '');
            },
            warningPrinter: warnings.add,
          );

          expect(calls, hasLength(1));
          expect(calls.single.$1, executable);
          expect(calls.single.$2, [...prefix, artifactPath]);
          expect(warnings, isEmpty);
        });
      }

      test('warns on a nonzero exit without throwing', () async {
        final warnings = <String>[];

        await openArtifact(
          'missing artifact.mp4',
          operatingSystem: platform,
          processRunner: (_, __) async => ProcessResult(1, 7, '', 'failed'),
          warningPrinter: warnings.add,
        );

        expect(warnings, [
          'Could not auto-open artifact on $displayName '
              '(missing artifact.mp4): exit code 7.',
        ]);
      });

      test('warns if the launcher cannot be started', () async {
        final warnings = <String>[];
        final error = ProcessException(executable, [], 'Launcher unavailable');

        await openArtifact(
          'artifact.mp4',
          operatingSystem: platform,
          processRunner: (_, __) => throw error,
          warningPrinter: warnings.add,
        );

        expect(
            warnings, ['Could not auto-open artifact (artifact.mp4): $error']);
      });

      test('warns if the asynchronous launcher result fails', () async {
        final warnings = <String>[];
        final error = StateError('Launcher failed');

        await openArtifact(
          'artifact.mp4',
          operatingSystem: platform,
          processRunner: (_, __) async => throw error,
          warningPrinter: warnings.add,
        );

        expect(
            warnings, ['Could not auto-open artifact (artifact.mp4): $error']);
      });
    });
  }

  test('unsupported platforms warn without launching a process', () async {
    final warnings = <String>[];
    var processCalls = 0;

    await openArtifact(
      'artifact.mp4',
      operatingSystem: 'unsupported',
      processRunner: (_, __) async {
        processCalls++;
        return ProcessResult(1, 0, '', '');
      },
      warningPrinter: warnings.add,
    );

    expect(processCalls, 0);
    expect(warnings, [
      'Auto-open is not supported on this platform. '
          'Please open artifact.mp4 manually.',
    ]);
  });

  test('uses the host platform when no override is provided', () async {
    final calls = <(String, List<String>)>[];
    final warnings = <String>[];

    await openArtifact(
      'artifact.mp4',
      processRunner: (command, arguments) async {
        calls.add((command, arguments));
        return ProcessResult(1, 0, '', '');
      },
      warningPrinter: warnings.add,
    );

    final expected = switch (Platform.operatingSystem) {
      'windows' => ('cmd', ['/c', 'start', '', 'artifact.mp4']),
      'macos' => ('open', ['artifact.mp4']),
      'linux' => ('xdg-open', ['artifact.mp4']),
      _ => null,
    };
    if (expected == null) {
      expect(calls, isEmpty);
      expect(warnings, hasLength(1));
    } else {
      expect(calls, hasLength(1));
      expect(calls.single.$1, expected.$1);
      expect(calls.single.$2, expected.$2);
      expect(warnings, isEmpty);
    }
  });
}
