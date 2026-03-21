import 'dart:io';

import '../models.dart';
import 'auto_opener.dart';

import 'prompt_outcome.dart';

/// Drives the interactive CLI session for a single [TestCase].
///
/// Responsibilities:
/// 1. Print a formatted case header.
/// 2. Auto-open the artifact with the OS default app.
/// 3. Walk through each checklist item, collecting y/n/s/r/q responses.
/// 4. Return a [PromptOutcome] to the orchestrator.
class InteractivePrompter {
  const InteractivePrompter({
    this.autoOpen = true,
    this.reader,
    this.printer,
  });

  final bool autoOpen;

  /// Optional injected reader. Overrides `stdin.readLineSync` for unit tests.
  final String? Function()? reader;

  /// Optional injected printer. Overrides `stdout.write`/`writeln` for unit tests.
  final void Function(String)? printer;

  Future<PromptOutcome> prompt(
    ArtifactResult artifact,
    TestCase testCase, {
    int retryCount = 0,
  }) async {
    _printHeader(testCase, artifact, retryCount);

    if (autoOpen) {
      openArtifact(artifact.path);
    }

    final verdicts = <String, ChecklistVerdict>{};
    PromptOutcome? earlyExit;

    for (final item in testCase.checklist) {
      final outcome =
          await _promptItem(item, testCase, artifact, verdicts, retryCount);
      if (outcome != null) {
        earlyExit = outcome;
        break;
      }
    }

    if (earlyExit != null) return earlyExit;

    final result = ChecklistResult(
      testCase: testCase,
      artifactPath: artifact.path,
      verdicts: verdicts,
      retryCount: retryCount,
    );
    return PromptCompleted(result);
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  Future<PromptOutcome?> _promptItem(
    String item,
    TestCase testCase,
    ArtifactResult artifact,
    Map<String, ChecklistVerdict> verdicts,
    int retryCount,
  ) async {
    while (true) {
      _print('${_style('  › ', _cyan)}$item${_style('  [y/n/s/r/q]: ', _dim)}');

      final input = _readLine()?.trim().toLowerCase();
      switch (input) {
        case 'y':
          verdicts[item] = ChecklistVerdict.pass;
          _println(_style('    ✅ pass', _green));
          return null;
        case 'n':
          verdicts[item] = ChecklistVerdict.fail;
          _println(_style('    ❌ fail', _red));
          return null;
        case 's':
          verdicts[item] = ChecklistVerdict.skipped;
          _println(_style('    ⏭  skipped', _yellow));
          return null;
        case 'r':
          _println(
              _style('\n  ↺  Hot-retry — regenerating artifact…\n', _yellow));
          return PromptRetry();
        case 'q':
          _println(_style('\n  ⏸  Saving progress and quitting…\n', _yellow));
          // Build a partial result with what we have so far.
          final partial = verdicts.isNotEmpty
              ? ChecklistResult(
                  testCase: testCase,
                  artifactPath: artifact.path,
                  verdicts: Map.unmodifiable(verdicts),
                  retryCount: retryCount,
                )
              : null;
          return PromptQuit(partial);
        default:
          _println(_style('    Please enter y, n, s, r, or q.', _dim));
      }
    }
  }

  void _printHeader(
      TestCase testCase, ArtifactResult artifact, int retryCount) {
    final caseLine = '  Case ${testCase.index + 1}: ${testCase.label}';
    final artifactLine = '  Artifact: ${artifact.path}';
    final retryLine = retryCount > 0 ? '  Retry #$retryCount' : '';
    final keysLine =
        '  Keys: [y] pass  [n] fail  [s] skip  [r] retry  [q] save & quit';

    final textLengths = [
      caseLine.length,
      artifactLine.length,
      retryLine.length,
      keysLine.length,
      60 // Absolute minimum fallback bound
    ];
    final width = textLengths
            .reduce((value, element) => value > element ? value : element) +
        2;

    final bar = '─' * width;
    _println(_style('\n$bar', _cyan));
    _println(_style(caseLine, _bold));
    _println('${_style('  Artifact: ', _dim)}${artifact.path}');
    if (retryCount > 0) {
      _println(_style(retryLine, _yellow));
    }
    _println(_style(bar, _cyan));
    _println(_style('$keysLine\n', _dim));
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

// ---------------------------------------------------------------------------
// Tiny ANSI helpers (avoids a heavy dependency just for colours)
// ---------------------------------------------------------------------------
const _reset = '\x1B[0m';
const _bold = '\x1B[1m';
const _dim = '\x1B[2m';
const _green = '\x1B[32m';
const _red = '\x1B[31m';
const _yellow = '\x1B[33m';
const _cyan = '\x1B[36m';
const _reset = '\x1B[0m';

String _style(String text, String code) => '$code$text$_reset';
