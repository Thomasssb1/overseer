import 'dart:convert';
import 'dart:io';

import 'package:overseer/overseer.dart';
import 'package:test/test.dart';

void main() {
  const legacySchemaUrl =
      'https://raw.githubusercontent.com/Thomasssb1/overseer/main/schema/report.v1.json';
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

  test('continues to validate reports using the original v1 schema', () {
    final legacy = {
      ...report,
      r'$schema': legacySchemaUrl,
      'schema_version': 1,
    }..remove('overseer_version');
    expect(() => validateReport(legacy), returnsNormally);
    final matrix = legacy['matrix'] as Map<String, dynamic>;
    for (final invalid in [
      {...matrix, 'version': '1.0.0'},
      {...matrix, 'sha256': 'invalid'},
      {...matrix}..remove('path'),
    ]) {
      expect(() => validateReport({...legacy, 'matrix': invalid}),
          throwsA(isA<ReportException>()));
    }
  });

  test('continues to validate v2 reports without an Overseer version', () {
    final legacy = {
      ...report,
      r'$schema':
          'https://raw.githubusercontent.com/Thomasssb1/overseer/main/schema/report.v2.json',
      'schema_version': 2,
    }..remove('overseer_version');
    legacy['matrix']['version'] = 'review-2';
    expect(() => validateReport(legacy), returnsNormally);
    expect(
        () => validateReport({...legacy, 'overseer_version': overseerVersion}),
        throwsA(isA<ReportException>()));
    expect(() => validateReport({...legacy, 'commit_sha': 'invalid'}),
        throwsA(isA<ReportException>()));
  });

  test('rejects a schema URL that does not match the declared version', () {
    expect(() => validateReport({...report, 'schema_version': 1}),
        throwsA(isA<ReportException>()));
    expect(() => validateReport({...report, r'$schema': legacySchemaUrl}),
        throwsA(isA<ReportException>()));
  });

  for (final version in <Object?>[null, 0, 4, '1', '2', '3', true, [], {}]) {
    test('rejects unsupported or malformed schema version: $version', () {
      expect(() => validateReport({...report, 'schema_version': version}),
          throwsA(isA<ReportException>()));
    });
  }

  test('accepts an optional non-empty matrix version tag', () {
    report['matrix']['version'] = 'review-2';
    expect(() => validateReport(report), returnsNormally);
    report['matrix'].remove('version');
    expect(() => validateReport(report), returnsNormally);
  });

  for (final invalid in <Object?>[null, '', '   ', '\n\t', 1, true, [], {}]) {
    test('rejects an invalid matrix version in a report: $invalid', () {
      report['matrix']['version'] = invalid;
      expect(() => validateReport(report), throwsA(isA<ReportException>()));
    });
  }

  for (final invalid in <Object?>[null, '', '   ', '\n\t', 1, true, [], {}]) {
    test('rejects an invalid Overseer version in a report: $invalid', () {
      report['overseer_version'] = invalid;
      expect(() => validateReport(report), throwsA(isA<ReportException>()));
    });
  }

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
      'schema_version': 4,
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
