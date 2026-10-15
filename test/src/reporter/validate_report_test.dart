import 'dart:convert';
import 'dart:io';

import 'package:overseer/overseer.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late Map<String, dynamic> report;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('overseer_validate_report_');
    const testCase = TestCase(
        name: 'suite',
        index: 0,
        params: {'color': 'red'},
        checklist: ['Looks good']);
    final reporter = Reporter(
        outputDir: tempDir.path,
        format: ReportFormat.json,
        context: ReportContext(
            matrixPath: 'matrix.yaml',
            matrixSha256: 'a' * 64,
            commitSha: 'b' * 40,
            cases: [testCase]));
    reporter.record(const ChecklistResult(
        testCase: testCase,
        artifactPath: 'artifact.txt',
        verdicts: {'Looks good': ChecklistVerdict.pass}));
    final path = await reporter.writeReport();
    report = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('accepts a generated report', () {
    expect(() => validateReport(report), returnsNormally);
  });

  test('loaded schema matches the report format', () {
    final schema = jsonDecode(reportSchema) as Map<String, dynamic>;
    expect(schema[r'$id'], Reporter.schemaUrl);
    expect(schema['properties']['schema_version']['const'],
        Reporter.schemaVersion);
  });

  for (final value in <Object?>[null, [], 'raw JSON text', 42, true]) {
    test('rejects a non-object report: $value', () {
      expect(() => validateReport(value), throwsA(isA<ReportException>()));
    });
  }

  test('rejects every missing required top-level field', () {
    for (final key in report.keys.toList()) {
      final invalid = {...report}..remove(key);
      expect(() => validateReport(invalid), throwsA(isA<ReportException>()),
          reason: key);
    }
  });

  test('rejects unsupported versions and invalid metadata', () {
    for (final entry in <String, Object?>{
      'schema_version': 2,
      r'$schema': 'unknown-schema',
      'generated_at': 'not a timestamp',
      'commit_sha': 'short SHA',
      'expected_case_count': -1,
      'completed_case_count': 0.5,
      'complete': 'yes',
      'successful': null,
      'extra': 'unknown field',
    }.entries) {
      expect(() => validateReport({...report, entry.key: entry.value}),
          throwsA(isA<ReportException>()),
          reason: entry.key);
    }
  });

  test('rejects invalid matrix and summary fields', () {
    final matrix = report['matrix'] as Map<String, dynamic>;
    for (final invalid in <Object?>[
      null,
      [],
      {},
      {...matrix, 'sha256': 'bad hash'},
      {...matrix, 'path': 42},
      {...matrix, 'extra': true}
    ]) {
      expect(() => validateReport({...report, 'matrix': invalid}),
          throwsA(isA<ReportException>()));
    }
    final summary = report['summary'] as Map<String, dynamic>;
    for (final key in summary.keys) {
      expect(
          () => validateReport({
                ...report,
                'summary': {...summary}..remove(key)
              }),
          throwsA(isA<ReportException>()));
      expect(
          () => validateReport({
                ...report,
                'summary': {...summary, key: -1}
              }),
          throwsA(isA<ReportException>()));
    }
  });

  test('rejects malformed case fields and checklist verdicts', () {
    final testCase = report['cases'][0] as Map<String, dynamic>;
    for (final key in testCase.keys) {
      expect(
          () => validateReport({
                ...report,
                'cases': [
                  {...testCase}..remove(key)
                ]
              }),
          throwsA(isA<ReportException>()),
          reason: key);
    }
    for (final entry in <String, Object?>{
      'index': -1,
      'name': 42,
      'params': {'nested': []},
      'artifact_path': [],
      'retry_count': -1,
      'completed': 'yes',
      'status': 'unknown',
      'error': {},
      'checklist': [
        {'item': 'Looks good', 'verdict': 'unknown'}
      ],
      'extra': true,
    }.entries) {
      expect(
          () => validateReport({
                ...report,
                'cases': [
                  {...testCase, entry.key: entry.value}
                ]
              }),
          throwsA(isA<ReportException>()),
          reason: entry.key);
    }
  });

  test('reports useful schema errors through ReportException', () {
    expect(
        () => validateReport({...report, 'schema_version': 999}),
        throwsA(isA<ReportException>().having((e) => e.message, 'message',
            allOf(contains('Invalid report:'), contains('schema_version')))));
  });

  test('structural validation leaves provenance comparisons to CI', () {
    report['commit_sha'] = 'c' * 40;
    report['matrix']['sha256'] = 'd' * 64;
    expect(() => validateReport(report), returnsNormally);
  });
}
