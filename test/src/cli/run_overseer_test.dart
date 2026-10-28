import 'dart:convert';
import 'dart:io';

import 'package:overseer/overseer.dart';
import 'package:overseer/src/cli/run_overseer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File matrix;
  late File report;
  late StringBuffer output;
  late StringBuffer errorOutput;
  final revision = 'a' * 40;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('overseer_cli_');
    matrix = File(p.join(tempDir.path, 'matrix with spaces.yaml'));
    matrix.writeAsStringSync('''
name: suite
parameters: {color: [red]}
checklist: [Good]
''');
    final cases = MatrixEngine.load(matrix.path);
    final reporter = Reporter(
        outputDir: tempDir.path,
        format: ReportFormat.json,
        context: ReportContext.capture(
            matrixPath: matrix.path, cases: cases, commitSha: revision));
    reporter.record(ChecklistResult(
        testCase: cases.single,
        artifactPath: 'artifact.txt',
        verdicts: {'Good': ChecklistVerdict.pass}));
    report = File(await reporter.writeReport());
    output = StringBuffer();
    errorOutput = StringBuffer();
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  List<String> arguments() => [
        'verify',
        '--report',
        report.path,
        '--matrix',
        matrix.path,
        '--expected-sha',
        revision,
      ];

  Future<int> run(List<String> args) =>
      runOverseer(args, output: output, errorOutput: errorOutput);

  Future<void> expectFailure(List<String> args, String diagnostic) async {
    expect(await run(args), 1);
    final result = jsonDecode(output.toString());
    expect(result['valid'], isFalse);
    expect(result['errors'], contains(contains(diagnostic)));
    expect(errorOutput.toString(), contains('Verification failed'));
    expect(errorOutput.toString(), contains(diagnostic));
  }

  test('returns success with JSON on stdout and a readable summary on stderr',
      () async {
    expect(await run(arguments()), 0);
    final result = jsonDecode(output.toString());
    expect(result['valid'], isTrue);
    expect(result['expected_case_count'], 1);
    expect(result['reported_case_count'], 1);
    expect(result['errors'], isEmpty);
    expect(errorOutput.toString(), '${result['summary']}\n');
  });

  test('returns JSON diagnostics for an unknown command', () async {
    await expectFailure(['wat'], 'Could not find a command named "wat"');
  });

  test('shows global help when invoked without a command', () async {
    expect(await run([]), 0);
    expect(output.toString(), contains('Usage: overseer <command>'));
    expect(output.toString(), contains('verify'));
    expect(errorOutput.isEmpty, isTrue);
  });

  test('shows command help without requiring report inputs', () async {
    expect(await run(['verify', '--help']), 0);
    expect(output.toString(), contains('Usage: overseer verify'));
    for (final option in ['report', 'matrix', 'expected-sha']) {
      expect(output.toString(), contains('--$option (mandatory)'));
    }
    expect(output.toString(), contains('--allow-errors'));
    expect(errorOutput.isEmpty, isTrue);
  });

  for (final option in ['report', 'matrix', 'expected-sha']) {
    test('rejects omitted required option --$option', () async {
      final args = arguments();
      final index = args.indexOf('--$option');
      args.removeRange(index, index + 2);
      await expectFailure(args, 'Option $option is mandatory.');
    });

    test('rejects whitespace-only --$option values', () async {
      final args = arguments();
      args[args.indexOf('--$option') + 1] = '   ';
      await expectFailure(args, 'Option --$option must not be blank.');
    });
  }

  test('rejects unexpected positional values following valid options',
      () async {
    await expectFailure(
        [...arguments(), 'extra'], 'does not take any arguments');
  });

  test('rejects unrecognized policy flags', () async {
    await expectFailure([...arguments(), '--allow-skip'], 'allow-skip');
  });

  test('rejects a missing report with machine-readable diagnostics', () async {
    report.deleteSync();
    await expectFailure(arguments(), 'Cannot read report');
  });

  test('rejects malformed JSON with machine-readable diagnostics', () async {
    report.writeAsStringSync('{bad json');
    await expectFailure(arguments(), 'Unexpected character');
  });

  test('returns schema diagnostics for structurally invalid JSON', () async {
    report.writeAsStringSync('null');
    await expectFailure(arguments(), 'Invalid report');
  });

  test('rejects a valid but mismatched expected SHA', () async {
    final args = arguments();
    args[args.indexOf('--expected-sha') + 1] = 'b' * 40;
    await expectFailure(args, 'Commit SHA mismatch');
  });

  for (final (status, verdict, flag) in [
    ('failed', 'fail', '--allow-failures'),
    ('skipped', 'skipped', '--allow-skips'),
    ('error', null, '--allow-errors'),
  ]) {
    test('allows $status outcomes only when $flag is supplied', () async {
      final data = jsonDecode(report.readAsStringSync());
      final isError = status == 'error';
      data['cases'][0]['status'] = status;
      data['cases'][0]['checklist'][0]['verdict'] = verdict;
      data['cases'][0]['completed'] = !isError;
      if (isError) {
        data['cases'][0]['artifact_path'] = null;
        data['cases'][0]['error'] = 'generation failed';
      }
      data['completed_case_count'] = isError ? 0 : 1;
      data['complete'] = !isError;
      data['successful'] = false;
      data['summary']['passed'] = 0;
      data['summary'][status] = 1;
      report.writeAsStringSync(jsonEncode(data));
      expect(await run(arguments()), 1);
      expect(jsonDecode(output.toString())['valid'], isFalse);
      output.clear();
      errorOutput.clear();
      expect(await run([...arguments(), flag]), 0);
      expect(jsonDecode(output.toString())['valid'], isTrue);
    });
  }

  test(
      'executable exits 0/1 and emits parseable JSON without waiting for stdin',
      () async {
    final executable = p.join(Directory.current.path, 'bin', 'overseer.dart');
    for (final expectedExitCode in [0, 1]) {
      if (expectedExitCode == 1) {
        matrix.writeAsStringSync('# changed\n', mode: FileMode.append);
      }
      final process = await Process.start(
          Platform.resolvedExecutable, [executable, ...arguments()]);
      final stdoutText = process.stdout.transform(utf8.decoder).join();
      final stderrText = process.stderr.transform(utf8.decoder).join();
      try {
        // Leave stdin open: verification must exit without requesting input.
        final code =
            await process.exitCode.timeout(const Duration(seconds: 20));
        final diagnostics = await stderrText;
        expect(code, expectedExitCode, reason: diagnostics);
        expect(jsonDecode(await stdoutText)['valid'], expectedExitCode == 0);
        expect(diagnostics, contains('Verification'));
        if (expectedExitCode == 1) {
          expect(diagnostics, contains('Matrix SHA-256'));
        }
      } finally {
        process.kill();
        await process.stdin.close();
      }
    }
  });
}
