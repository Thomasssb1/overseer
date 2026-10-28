import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:overseer/overseer.dart';
import 'package:overseer/src/cli/verify_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File matrix;
  late File report;
  late StringBuffer output;
  late CommandRunner<VerificationResult> runner;
  final revision = 'a' * 40;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('overseer_verify_command_');
    matrix = File(p.join(tempDir.path, 'matrix.yaml'));
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
    runner = CommandRunner<VerificationResult>('overseer', 'Verify reports.')
      ..addCommand(VerifyCommand(output));
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

  test('returns verification results for a complete matching report', () async {
    final result = await runner.run(arguments());
    expect(result!.valid, isTrue);
    expect(result.expectedCaseCount, 1);
    expect(result.errors, isEmpty);
    expect(output.isEmpty, isTrue);
  });

  test('rejects provenance mismatch in the supplied report', () async {
    final data = jsonDecode(report.readAsStringSync());
    data['commit_sha'] = 'b' * 40;
    report.writeAsStringSync(jsonEncode(data));

    final result = await runner.run(arguments());
    expect(result!.valid, isFalse);
    expect(result.errors, contains(contains('Commit SHA mismatch')));
  });

  test('shows generated command help without reading report or matrix',
      () async {
    report.deleteSync();
    matrix.deleteSync();

    expect(await runner.run([...arguments(), '--help']), isNull);
    expect(output.toString(), contains('Usage: overseer verify'));
    expect(output.toString(), contains('--expected-sha (mandatory)'));
    expect(output.toString(), contains('Exits 0 on success'));
  });

  test('rejects positional arguments through takesArguments', () async {
    await expectLater(
        runner.run([...arguments(), 'extra']),
        throwsA(isA<UsageException>().having((error) => error.message,
            'message', contains('does not take any arguments'))));
  });
}
