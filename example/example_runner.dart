/// Example overseer run using a stub generator.
///
/// Run with:
///   dart run example/example_runner.dart
///
/// This demo:
/// 1. Loads the example matrix (2 models × 2 temperatures = 4 cases).
/// 2. Uses a stub generator that writes a small .txt file as the "artifact".
/// 3. Walks you through the interactive checklist for each case.
/// 4. Writes a Markdown report to example/reports/.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:overseer/overseer.dart';

void main() async {
  // Resolve the matrix path relative to this script's location.
  final scriptDir = p.dirname(Platform.script.toFilePath());
  final matrixPath = p.join(scriptDir, 'tests', 'example.matrix.yaml');

  final runner = OverseerRunner(
    matrixPath: matrixPath,
    outputDir: p.join(scriptDir, 'output'),
    // Disable auto-open for the stub demo (we write a .txt, not a media file).
    autoOpen: false,
    generator: (TestCase testCase) async {
      // Stub: simulate generation by writing a text file.
      final outDir = Directory(
        p.join(scriptDir, 'output', 'artifacts'),
      )..createSync(recursive: true);

      final fileName =
          'response_${testCase.params['model']}_t${testCase.params['temperature']}.txt';
      final file = File(p.join(outDir.path, fileName));

      // Fake generated content.
      file.writeAsStringSync(
        'Model: ${testCase.params['model']}\n'
        'Temperature: ${testCase.params['temperature']}\n\n'
        'The quick brown fox jumps over the lazy dog.\n'
        '[Stub AI output — replace this with your real generator.]\n',
      );

      return ArtifactResult(
        path: file.path,
        metadata: {
          'model': testCase.params['model'],
          'temperature': testCase.params['temperature'],
        },
      );
    },
  );

  final reportPath = await runner.run();
  stdout.writeln('\nDone! Open your report: $reportPath');
}
