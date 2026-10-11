/// Review generated text artifacts without API keys or external services.
///
/// Run from the package root:
/// ```sh
/// dart pub get
/// dart run example/overseer_example.dart
/// ```
///
/// This demo:
/// 1. Loads the example matrix (2 models × 2 temperatures = 4 cases).
/// 2. Writes a local .txt artifact for each parameter combination.
/// 3. Prompts for y/n/s verdicts, r to regenerate, or q to save and quit.
/// 4. Writes a Markdown report to example/output/reports/.
///
/// Open each displayed artifact path manually to inspect the text. Run the
/// command again after quitting to resume at the first unfinished case.
/// See example/README.md for the full walkthrough and output locations.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:overseer/overseer.dart';

Future<void> main() async {
  // Resolve the matrix path relative to this script's location.
  final scriptDir = p.dirname(Platform.script.toFilePath());
  final matrixPath = p.join(scriptDir, 'tests', 'example.matrix.yaml');

  final runner = OverseerRunner(
    matrixPath: matrixPath,
    outputDir: p.join(scriptDir, 'output'),
    // Open the displayed path manually, or enable this to use your default app.
    autoOpen: false,
    generator: (TestCase testCase) async {
      // Stub: simulate generation by writing a text file.
      final outDir = Directory(
        p.join(scriptDir, 'output', 'artifacts'),
      )..createSync(recursive: true);

      final fileName =
          'response_${testCase.params['model']}_t${testCase.params['temperature']}.txt';
      final file = File(p.join(outDir.path, fileName));

      // Replace this text generation with your own model or media pipeline.
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
  stdout.writeln('\nOpen your report: $reportPath');
}
