import 'dart:io';

import 'execution_wrapper/execution_wrapper.dart';
import 'interactive_prompter/interactive_prompter.dart';
import 'interactive_prompter/prompt_outcome.dart';
import 'lock_file/lock_file.dart';
import 'matrix_engine/matrix_engine.dart';
import 'models.dart';
import 'reporter/reporter.dart';

export 'exceptions.dart';
export 'execution_wrapper/execution_wrapper.dart'
    show ExecutionWrapper, ArtifactGenerator;
export 'interactive_prompter/interactive_prompter.dart'
    show InteractivePrompter;
export 'interactive_prompter/prompt_outcome.dart'
    show PromptOutcome, PromptCompleted, PromptRetry, PromptQuit;
export 'lock_file/lock_file.dart' show LockFile;
export 'matrix_engine/matrix_engine.dart' show MatrixEngine;
export 'matrix_engine/matrix_mode.dart' show MatrixMode;
export 'models.dart';
export 'reporter/reporter.dart' show Reporter;

/// Top-level orchestrator that wires all four components together.
///
/// ```dart
/// final runner = OverseerRunner(
///   matrixPath: 'tests/my_test.matrix.yaml',
///   generator: (tc) async {
///     final path = await myGenerate(tc.params);
///     return ArtifactResult(path: path);
///   },
/// );
/// await runner.run();
/// ```
class OverseerRunner {
  OverseerRunner({
    required this.matrixPath,
    required this.generator,
    this.outputDir,
    this.autoOpen = true,
    int maxRetries = 5,
    this.reader,
    this.printer,
  }) : _maxRetries = maxRetries;

  /// Path to the `.matrix.yaml` file that defines the test permutations.
  final String matrixPath;

  /// User-supplied artifact generator.
  final ArtifactGenerator generator;

  /// Directory where the report and lock file are written.
  /// Defaults to the current working directory.
  final String? outputDir;

  /// Whether to auto-open artifacts with the OS default application.
  final bool autoOpen;

  final int _maxRetries;

  /// Optional injected reader. Overrides `stdin.readLineSync` for testing.
  final String? Function()? reader;

  /// Optional injected printer. Overrides `stdout.write`/`writeln` for testing.
  final void Function(String)? printer;

  /// Runs the full session: load matrix → generate → prompt → report.
  ///
  /// Returns the path to the written report file.
  Future<String> run() async {
    final cases = MatrixEngine.load(matrixPath);
    final reporter = Reporter(outputDir: outputDir);
    final prompter = InteractivePrompter(
      autoOpen: autoOpen,
      reader: reader,
      printer: printer,
    );
    final wrapper = ExecutionWrapper();

    // Check for a resumable lock file.
    final lock = LockFile.tryResume(
          matrixPath: matrixPath,
          directory: outputDir,
        ) ??
        LockFile.create(matrixPath: matrixPath, directory: outputDir);

    for (final pastResult in lock.results) {
      reporter.record(pastResult);
    }

    final startIndex = lock.lastCompletedIndex + 1;
    if (startIndex > 0) {
      _println(
        '\x1B[36m⏩  Resuming from case ${startIndex + 1} / ${cases.length}\x1B[0m',
      );
    }

    for (var i = startIndex; i < cases.length; i++) {
      final testCase = cases[i];
      int retryCount = 0;
      bool retry = true;

      while (retry) {
        retry = false;

        // 1. Generate the artifact.
        ArtifactResult artifact;
        try {
          artifact = await wrapper.run(testCase, generator);
        } catch (e) {
          _println('\x1B[31m  ✖ Generator error: $e\x1B[0m');
          _print('  Retry this case? [r=yes / any key=skip]: ');
          final key = _readLine()?.trim().toLowerCase();
          if (key == 'r' && retryCount < _maxRetries) {
            retryCount++;
            retry = true;
          }
          continue;
        }

        // 2. Prompt the reviewer.
        final outcome = await prompter.prompt(
          artifact,
          testCase,
          retryCount: retryCount,
        );

        switch (outcome) {
          case PromptCompleted(:final result):
            reporter.record(result);
            lock.advance(i, result);

          case PromptRetry():
            if (retryCount < _maxRetries) {
              retryCount++;
              retry = true;
            } else {
              _println(
                  '\x1B[33m  Max retries reached for this case.\x1B[0m');
            }

          case PromptQuit(:final partial):
            if (partial != null) reporter.record(partial);
            final reportPath = await reporter.writeReport();
            _println('\n\x1B[36m📄 Report saved to: $reportPath\x1B[0m');
            // Keep the lock file so the run can be resumed.
            return reportPath;
        }
      }
    }

    // All cases done — finalise.
    lock.clear();
    final reportPath = await reporter.writeReport();
    _println(
      '\n\x1B[32m✅ All ${cases.length} case(s) complete.\x1B[0m'
      '\n\x1B[36m📄 Report: $reportPath\x1B[0m',
    );
    return reportPath;
  }

  void _println(String msg) {
    if (printer != null) {
      printer!('$msg\n');
    } else {
      stdout.writeln(msg);
    }
  }

  void _print(String msg) {
    if (printer != null) {
      printer!(msg);
    } else {
      stdout.write(msg);
    }
  }

  String? _readLine() {
    if (reader != null) return reader!();
    return stdin.readLineSync();
  }
}
