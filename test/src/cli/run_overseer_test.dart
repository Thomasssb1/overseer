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

  int run(List<String> args) =>
      runOverseer(args, output: output, errorOutput: errorOutput);

  void expectFailure(List<String> args, String diagnostic) {
    expect(run(args), 1);
    final result = jsonDecode(output.toString());
    expect(result['valid'], isFalse);
    expect(result['errors'], contains(contains(diagnostic)));
    expect(errorOutput.toString(), contains('Verification failed'));
    expect(errorOutput.toString(), contains(diagnostic));
  }

  test('returns success with JSON on stdout and a readable summary on stderr',
      () {
    expect(run(arguments()), 0);
    final result = jsonDecode(output.toString());
    expect(result['valid'], isTrue);
    expect(result['expected_case_count'], 1);
    expect(result['reported_case_count'], 1);
    expect(result['errors'], isEmpty);
    expect(errorOutput.toString(), '${result['summary']}\n');
  });

  for (final args in [
    <String>[],
    ['wat'],
    ['verify', 'extra']
  ]) {
    test('rejects missing or unexpected subcommand arguments: $args', () {
      expect(run(args), 1);
      expect(jsonDecode(output.toString())['valid'], isFalse);
      expect(errorOutput.toString(), contains('Verification failed'));
    });
  }

  for (final args in [
    ['--help'],
    ['-h'],
    ['verify', '--help'],
    ['verify', '-h']
  ]) {
    test('shows help without accessing required inputs: $args', () {
      expect(run(args), 0);
      expect(output.toString(), contains('Usage: overseer verify'));
      for (final option in ['report', 'matrix', 'expected-sha']) {
        expect(output.toString(), contains('--$option (mandatory)'));
      }
      expect(output.toString(), contains('--allow-errors'));
      expect(errorOutput.isEmpty, isTrue);
    });
  }

  for (final option in ['report', 'matrix', 'expected-sha']) {
    test('rejects omitted required option --$option', () {
      final args = arguments();
      final index = args.indexOf('--$option');
      args.removeRange(index, index + 2);
      expectFailure(args, 'Option $option is mandatory.');
    });

    for (final value in ['', '   ']) {
      test('rejects blank required option --$option: "$value"', () {
        final args = arguments();
        args[args.indexOf('--$option') + 1] = value;
        expectFailure(args, 'Option --$option must not be blank.');
      });
    }
  }

  test('rejects unexpected positional values following valid options', () {
    expectFailure([...arguments(), 'extra'], 'Expected the verify subcommand');
  });

  test('rejects unrecognized policy flags', () {
    expectFailure([...arguments(), '--allow-skip'], 'allow-skip');
  });

  test('rejects option with no value without prompting', () {
    expectFailure(['verify', '--report'], 'report');
  });

  test('rejects a missing report with machine-readable diagnostics', () {
    report.deleteSync();
    expectFailure(arguments(), 'Cannot read report');
  });

  test('rejects a directory supplied as the report', () {
    final args = arguments();
    args[args.indexOf('--report') + 1] = tempDir.path;
    expectFailure(args, 'Cannot read report');
  });

  test('rejects malformed JSON with machine-readable diagnostics', () {
    report.writeAsStringSync('{bad json');
    expectFailure(arguments(), 'Unexpected character');
  });

  test('rejects structurally invalid JSON without a stack trace', () {
    report.writeAsStringSync('null');
    expectFailure(arguments(), 'Invalid report');
    expect(errorOutput.toString(), isNot(contains('StackTrace')));
  });

  test('rejects invalid expected SHA rather than trusting the report', () {
    final args = arguments();
    args[args.indexOf('--expected-sha') + 1] = 'HEAD';
    expectFailure(args, 'Commit SHA must be a full Git object ID');
  });

  test('rejects a valid but mismatched expected SHA', () {
    final args = arguments();
    args[args.indexOf('--expected-sha') + 1] = 'b' * 40;
    expectFailure(args, 'Commit SHA mismatch');
  });

  test('rejects missing matrix with machine-readable diagnostics', () {
    matrix.deleteSync();
    expectFailure(arguments(), 'Matrix file not found');
  });

  for (final (status, verdict, flag) in [
    ('failed', 'fail', '--allow-failures'),
    ('skipped', 'skipped', '--allow-skips'),
    ('error', null, '--allow-errors'),
  ]) {
    test('passes $flag through to the verification policy', () {
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
      expect(run(arguments()), 1);
      expect(jsonDecode(output.toString())['valid'], isFalse);
      output.clear();
      errorOutput.clear();
      expect(run([...arguments(), flag]), 0);
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
