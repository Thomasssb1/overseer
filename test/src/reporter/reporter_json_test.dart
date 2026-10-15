import 'dart:convert';
import 'dart:io';

import 'package:overseer/overseer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late List<TestCase> cases;
  late Reporter reporter;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('overseer_json_test_');
    cases = [
      for (var i = 0; i < 6; i++)
        TestCase(name: 'suite', index: i, params: {
          'text': 'quotes " and \\ and 日本語',
          'number': i,
          'bool': true,
          'null': null
        }, checklist: [
          'A',
          'B'
        ])
    ];
    reporter = Reporter(
        outputDir: tempDir.path,
        format: ReportFormat.json,
        context: ReportContext(
            matrixPath: 'matrix.yaml',
            matrixSha256: 'a' * 64,
            commitSha: 'b' * 40,
            cases: cases));
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  ChecklistResult result(int index, Map<String, ChecklistVerdict> verdicts) =>
      ChecklistResult(
          testCase: cases[index],
          artifactPath: '/tmp/日本語 "file".txt',
          retryCount: 2,
          verdicts: verdicts);

  Future<Map<String, dynamic>> readReport() async {
    final path = await reporter.writeReport();
    expect(p.dirname(path), p.join(tempDir.path, 'reports'));
    expect(path, endsWith('.json'));
    return jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  }

  test('JSON requires expected matrix context', () {
    expect(() => Reporter(format: ReportFormat.json),
        throwsA(isA<ReportException>()));
  });

  test('includes version, provenance, all cases, and exclusive status counts',
      () async {
    reporter.record(
        result(0, {'A': ChecklistVerdict.pass, 'B': ChecklistVerdict.pass}));
    reporter.record(
        result(1, {'A': ChecklistVerdict.fail, 'B': ChecklistVerdict.skipped}));
    reporter.record(
        result(2, {'A': ChecklistVerdict.pass, 'B': ChecklistVerdict.skipped}));
    reporter.record(result(
        3, {'A': ChecklistVerdict.skipped, 'B': ChecklistVerdict.skipped}));
    reporter.recordError(cases[4], StateError('generator broke'),
        retryCount: 3);
    final json = await readReport();
    expect(json[r'$schema'], Reporter.schemaUrl);
    expect(json['schema_version'], 1);
    expect(DateTime.parse(json['generated_at'] as String).isUtc, isTrue);
    expect(json['commit_sha'], 'b' * 40);
    expect(json['matrix'], {'path': 'matrix.yaml', 'sha256': 'a' * 64});
    expect(json['expected_case_count'], 6);
    expect(json['completed_case_count'], 4);
    expect(json['complete'], isFalse);
    expect(json['successful'], isFalse);
    expect(json['summary'],
        {'passed': 1, 'failed': 1, 'skipped': 2, 'error': 1, 'pending': 1});
    final records = json['cases'] as List<dynamic>;
    expect(records.map((dynamic c) => c['index']), [0, 1, 2, 3, 4, 5]);
    expect(records[0]['params'], cases[0].params);
    expect(records[0]['artifact_path'], '/tmp/日本語 "file".txt');
    expect(records[0]['retry_count'], 2);
    expect(records[0]['checklist'], [
      {'item': 'A', 'verdict': 'pass'},
      {'item': 'B', 'verdict': 'pass'}
    ]);
    expect(records[4]['status'], 'error');
    expect(records[4]['error'], contains('generator broke'));
    expect(records[4]['retry_count'], 3);
    expect(records[4]['completed'], isFalse);
    expect(records[5]['artifact_path'], isNull);
    expect(records[5]['checklist'], [
      {'item': 'A', 'verdict': null},
      {'item': 'B', 'verdict': null}
    ]);
  });

  test('strict success requires every item in every case to pass', () async {
    for (var i = 0; i < cases.length; i++) {
      reporter.record(
          result(i, {'A': ChecklistVerdict.pass, 'B': ChecklistVerdict.pass}));
    }
    final json = await readReport();
    expect(json['complete'], isTrue);
    expect(json['successful'], isTrue);
    expect(json['completed_case_count'], 6);
    expect(json['summary'],
        {'passed': 6, 'failed': 0, 'skipped': 0, 'error': 0, 'pending': 0});
  });

  test('an empty session cannot report success', () async {
    final json = await readReport();
    expect(json['summary']['pending'], 6);
    expect(json['completed_case_count'], 0);
    expect(json['successful'], isFalse);
  });

  test('explicit partial and missing answers cannot complete a case', () async {
    reporter.record(
        result(0, {'A': ChecklistVerdict.pass, 'B': ChecklistVerdict.pass}),
        completed: false);
    reporter.record(result(1, {'A': ChecklistVerdict.pass}));
    final json = await readReport();
    expect(json['completed_case_count'], 0);
    expect(json['summary']['skipped'], 2);
    expect(json['summary']['passed'], 0);
    expect(json['cases'][1]['checklist'][1]['verdict'], isNull);
  });

  test('null commit and zero expected cases remain explicit', () async {
    reporter = Reporter(
        outputDir: tempDir.path,
        format: ReportFormat.json,
        context: ReportContext(
            matrixPath: 'matrix.yaml', matrixSha256: 'a' * 64, cases: []));
    final json = await readReport();
    expect(json['commit_sha'], isNull);
    expect(json['expected_case_count'], 0);
    expect(json['cases'], isEmpty);
    expect(json['successful'], isFalse);
  });

  test('rejects duplicate, out-of-range and mismatched cases', () {
    reporter.record(result(0, {'A': ChecklistVerdict.pass}));
    expect(
        () => reporter.record(result(0, {})), throwsA(isA<ReportException>()));
    expect(() => reporter.recordError(cases[0], StateError('duplicate')),
        throwsA(isA<ReportException>()));
    reporter.recordError(cases[1], StateError('error'));
    expect(
        () => reporter.record(result(1, {})), throwsA(isA<ReportException>()));
    for (final badCase in [
      TestCase(name: 'suite', index: -1, params: {}, checklist: ['A']),
      TestCase(name: 'suite', index: 6, params: {}, checklist: ['A']),
      TestCase(
          name: 'wrong',
          index: 2,
          params: cases[2].params,
          checklist: cases[2].checklist),
      TestCase(
          name: 'suite', index: 2, params: {}, checklist: cases[2].checklist),
      TestCase(
          name: 'suite',
          index: 2,
          params: {...cases[2].params, 'number': 99},
          checklist: cases[2].checklist),
      TestCase(
          name: 'suite', index: 2, params: cases[2].params, checklist: ['A']),
      TestCase(
          name: 'suite',
          index: 2,
          params: cases[2].params,
          checklist: ['B', 'A']),
    ]) {
      expect(
          () => reporter.record(ChecklistResult(
              testCase: badCase, artifactPath: 'artifact', verdicts: {})),
          throwsA(isA<ReportException>()));
    }
  });

  test('rejects negative retries and verdicts outside the checklist', () {
    expect(
        () => reporter.record(ChecklistResult(
            testCase: cases[0],
            artifactPath: 'artifact',
            verdicts: {},
            retryCount: -1)),
        throwsA(isA<ReportException>()));
    expect(
        () =>
            reporter.recordError(cases[0], StateError('error'), retryCount: -1),
        throwsA(isA<ReportException>()));
    expect(() => reporter.record(result(0, {'Unknown': ChecklistVerdict.pass})),
        throwsA(isA<ReportException>()));
  });
}
