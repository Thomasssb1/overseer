import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:overseer/overseer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File matrix;
  late Map<String, dynamic> report;
  final revision = 'a' * 40;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('overseer_verify_');
    matrix = File(p.join(tempDir.path, 'test.matrix.yaml'));
    matrix.writeAsStringSync('''
name: suite
mode: list
parameters:
  color: [red, blue]
checklist: [Looks good, Sounds good]
''');
    report = {
      r'$schema': Reporter.schemaUrl,
      'schema_version': 3,
      'generated_at': '2026-10-25T12:00:00Z',
      'overseer_version': '1.1.0',
      'commit_sha': revision,
      'matrix': {
        'path': 'a/different/checkout/test.matrix.yaml',
        'sha256': sha256.convert(matrix.readAsBytesSync()).toString(),
      },
      'expected_case_count': 2,
      'completed_case_count': 2,
      'complete': true,
      'successful': true,
      'summary': {
        'passed': 2,
        'failed': 0,
        'skipped': 0,
        'error': 0,
        'pending': 0
      },
      'cases': [
        for (var i = 0; i < 2; i++)
          {
            'index': i,
            'name': 'suite',
            'params': <String, dynamic>{'color': i == 0 ? 'red' : 'blue'},
            'artifact_path': 'artifact_$i.txt',
            'retry_count': 0,
            'completed': true,
            'status': 'passed',
            'error': null,
            'checklist': [
              <String, dynamic>{'item': 'Looks good', 'verdict': 'pass'},
              <String, dynamic>{'item': 'Sounds good', 'verdict': 'pass'},
            ],
          },
      ],
    };
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  VerificationResult verify({
    bool allowFailures = false,
    bool allowSkips = false,
    bool allowErrors = false,
  }) =>
      verifyReport(report,
          matrixPath: matrix.path,
          expectedSha: revision,
          allowFailures: allowFailures,
          allowSkips: allowSkips,
          allowErrors: allowErrors);

  void expectRejected(VerificationResult result, String diagnostic) {
    expect(result.valid, isFalse);
    expect(result.errors, contains(contains(diagnostic)));
  }

  void outcome(String status, {bool completed = true}) {
    final testCase = report['cases'][0];
    testCase['status'] = status;
    testCase['completed'] = completed;
    testCase['checklist'][0]['verdict'] = switch (status) {
      'failed' => 'fail',
      'skipped' => 'skipped',
      _ => null,
    };
    if (status == 'pending' || status == 'error') {
      testCase['artifact_path'] = null;
      testCase['checklist'][1]['verdict'] = null;
    }
    if (status == 'error') testCase['error'] = 'Generator failed';
    report['summary']['passed'] = 1;
    report['summary'][status] = 1;
    report['completed_case_count'] = completed ? 2 : 1;
    report['complete'] = completed;
    report['successful'] = false;
  }

  test(
      'accepts complete coverage with matching provenance across checkout paths',
      () {
    final result = verify();
    expect(result.valid, isTrue, reason: result.errors.join('\n'));
    expect(result.errors, isEmpty);
    expect(result.expectedCaseCount, 2);
    expect(result.reportedCaseCount, 2);
  });

  test('matches cases by index even when report order differs', () {
    report['cases'] = (report['cases'] as List).reversed.toList();
    expect(verify().valid, isTrue);
  });

  for (final version in [1, 2, 3]) {
    test('accepts supported schema version $version with its required fields',
        () {
      report['schema_version'] = version;
      report[r'$schema'] = 'https://raw.githubusercontent.com/Thomasssb1/'
          'overseer/main/schema/report.v$version.json';
      if (version < 3) report.remove('overseer_version');
      expect(verify().valid, isTrue);
    });
  }

  for (final invalid in <Object?>[
    null,
    [],
    'report',
    42,
    {},
    {'cases': []}
  ]) {
    test('rejects malformed report root without a type error: $invalid', () {
      expectRejected(
          verifyReport(invalid, matrixPath: matrix.path, expectedSha: revision),
          'Invalid report');
    });
  }

  for (final change in <String, Object?>{
    'schema_version': 999,
    r'$schema': 'https://example.com/unknown.json',
    'matrix': [],
    'summary': [],
    'cases': [null],
    'commit_sha': 'short',
  }.entries) {
    test('rejects malformed ${change.key} before semantic verification', () {
      report[change.key] = change.value;
      expectRejected(verify(), 'Invalid report');
    });
  }

  for (final invalid in <Object?>[-1, 0.5, '0', null, []]) {
    test('rejects invalid index $invalid without a type error', () {
      report['cases'][0]['index'] = invalid;
      expectRejected(verify(), 'Invalid report');
    });
  }

  test('accepts integral JSON numbers without unsafe integer casts', () {
    report['cases'][0]['index'] = 0.0;
    report['expected_case_count'] = 2.0;
    expect(verify().valid, isTrue);
  });

  for (final invalid in <Object?>[null, 'b' * 40]) {
    test('rejects missing or mismatched report commit: $invalid', () {
      report['commit_sha'] = invalid;
      expectRejected(verify(), 'Commit SHA mismatch');
    });
  }

  for (final invalid in ['', 'a' * 7, 'z' * 40, ' a${'a' * 39}']) {
    test('rejects invalid expected commit SHA: $invalid', () {
      expectRejected(
          verifyReport(report, matrixPath: matrix.path, expectedSha: invalid),
          'Commit SHA must be a full Git object ID');
    });
  }

  test('accepts a full SHA-256 Git object ID', () {
    report['commit_sha'] = 'b' * 64;
    expect(
        verifyReport(report, matrixPath: matrix.path, expectedSha: 'b' * 64)
            .valid,
        isTrue);
  });

  test('rejects matrix byte changes even when expanded cases are identical',
      () {
    matrix.writeAsStringSync('# new comment\n', mode: FileMode.append);
    expectRejected(verify(), 'Matrix SHA-256');
  });

  test('rejects mismatched matrix hash metadata', () {
    report['matrix']['sha256'] = 'b' * 64;
    expectRejected(verify(), 'Matrix SHA-256');
  });

  for (final mode in ['list', 'permutations']) {
    test('accepts reports produced by Reporter for $mode matrices', () async {
      matrix.writeAsStringSync('''
name: scalar_suite
version: '2.0.0'
mode: $mode
parameters:
  enabled: [true, false]
  threshold: [1.5, 2]
  optional: [null, text]
checklist: [Good]
''');
      final cases = MatrixEngine.load(matrix.path);
      final reporter = Reporter(
          outputDir: tempDir.path,
          format: ReportFormat.json,
          context: ReportContext.capture(
              matrixPath: matrix.path, cases: cases, commitSha: revision));
      for (final testCase in cases) {
        reporter.record(ChecklistResult(
            testCase: testCase,
            artifactPath: 'artifact',
            verdicts: {'Good': ChecklistVerdict.pass}));
      }
      final produced =
          jsonDecode(File(await reporter.writeReport()).readAsStringSync());
      final result = verifyReport(produced,
          matrixPath: matrix.path, expectedSha: revision);
      expect(result.valid, isTrue, reason: result.errors.join('\n'));
      expect(result.expectedCaseCount, mode == 'list' ? 2 : 8);
    });
  }

  for (final version in <String?>[null, 'other']) {
    test('rejects missing or mismatched matrix version metadata: $version', () {
      matrix
          .writeAsStringSync("version: '2.0.0'\n${matrix.readAsStringSync()}");
      report['matrix']['sha256'] =
          sha256.convert(matrix.readAsBytesSync()).toString();
      if (version != null) report['matrix']['version'] = version;
      expectRejected(verify(), 'Matrix version');
    });
  }

  test('rejects invented version metadata for an unversioned matrix', () {
    report['matrix']['version'] = 'invented';
    expectRejected(verify(), 'Matrix version');
  });

  test('v1 verifies byte provenance without requiring newer version metadata',
      () {
    matrix.writeAsStringSync("version: '2.0.0'\n${matrix.readAsStringSync()}");
    report['matrix']['sha256'] =
        sha256.convert(matrix.readAsBytesSync()).toString();
    report['schema_version'] = 1;
    report[r'$schema'] = Reporter.schemaUrl.replaceFirst('v3', 'v1');
    report.remove('overseer_version');
    expect(verify().valid, isTrue);
  });

  test('rejects a missing matrix with a descriptive diagnostic', () {
    matrix.deleteSync();
    expectRejected(verify(), 'Matrix file not found');
  });

  for (final invalid in [
    'name: [',
    '[]',
    'name: suite\nparameters: {x: [1], y: [2, 3]}\nchecklist: [Good]',
    'name: suite\nparameters: {x: [{nested: bad}]}\nchecklist: [Good]',
    'name: suite\nparameters: {x: [.nan]}\nchecklist: [Good]',
  ]) {
    test('rejects invalid matrix input: $invalid', () {
      matrix.writeAsStringSync(invalid);
      final result = verify();
      expect(result.valid, isFalse);
      expect(result.errors, isNotEmpty);
    });
  }

  test('rejects a missing case even if reported counts and flags claim success',
      () {
    report['cases'].removeLast();
    expectRejected(verify(), 'Missing expected case 1');
  });

  test('rejects an empty report rather than treating it as vacuous success',
      () {
    report['cases'] = [];
    report['expected_case_count'] = 0;
    report['completed_case_count'] = 0;
    report['summary']['passed'] = 0;
    expectRejected(verify(), 'Missing expected case 0');
  });

  test('rejects duplicate indices that preserve total report length', () {
    report['cases'][1] = jsonDecode(jsonEncode(report['cases'][0]));
    final result = verify();
    expectRejected(result, 'Duplicate case index: 0');
    expectRejected(result, 'Missing expected case 1');
  });

  test('rejects extra indices beyond the expanded matrix', () {
    final extra = jsonDecode(jsonEncode(report['cases'][0]));
    extra['index'] = 2;
    report['cases'].add(extra);
    expectRejected(verify(), 'Unexpected case index: 2');
  });

  for (final change in <String, Object?>{
    'name': 'other suite',
    'params': {'color': 'blue'},
  }.entries) {
    test('rejects a case whose ${change.key} differs from the matrix', () {
      report['cases'][0][change.key] = change.value;
      expectRejected(verify(), 'name or parameters do not match');
    });
  }

  test('distinguishes missing parameter keys from explicit null values', () {
    matrix.writeAsStringSync(
        matrix.readAsStringSync().replaceFirst('red', 'null'));
    report['matrix']['sha256'] =
        sha256.convert(matrix.readAsBytesSync()).toString();
    report['cases'][0]['params'] = {'wrong': null};
    expectRejected(verify(), 'parameters do not match');
    report['cases'][0]['params'] = {'color': null};
    expect(verify().valid, isTrue);
  });

  test('rejects extra parameter keys', () {
    report['cases'][0]['params']['extra'] = 1;
    expectRejected(verify(), 'parameters do not match');
  });

  for (final change in ['missing', 'extra', 'reordered', 'renamed']) {
    test('rejects $change checklist items', () {
      final items = report['cases'][0]['checklist'] as List;
      switch (change) {
        case 'missing':
          items.removeLast();
        case 'extra':
          items.add({'item': 'Extra', 'verdict': 'pass'});
        case 'reordered':
          report['cases'][0]['checklist'] = items.reversed.toList();
        case 'renamed':
          items[0]['item'] = 'Different';
      }
      expectRejected(verify(), 'checklist does not match');
    });
  }

  for (final entry in {
    'failed': 'failed checklist',
    'skipped': 'skipped checklist',
    'error': 'terminal generator error'
  }.entries) {
    test(
        'rejects ${entry.key} by default and accepts its explicit policy override',
        () {
      outcome(entry.key, completed: entry.key != 'error');
      expectRejected(verify(), entry.value);
      final result = verify(
          allowFailures: entry.key == 'failed',
          allowSkips: entry.key == 'skipped',
          allowErrors: entry.key == 'error');
      expect(result.valid, isTrue, reason: result.errors.join('\n'));
    });
  }

  test('mixed failed and skipped verdicts require both policy overrides', () {
    outcome('failed');
    report['cases'][0]['checklist'][1]['verdict'] = 'skipped';
    expectRejected(verify(allowFailures: true), 'skipped checklist');
    expectRejected(verify(allowSkips: true), 'failed checklist');
    expect(verify(allowFailures: true, allowSkips: true).valid, isTrue);
  });

  for (final status in ['failed', 'skipped', 'pending']) {
    test('rejects unfinished $status cases even under every policy override',
        () {
      outcome(status, completed: false);
      expectRejected(
          verify(allowFailures: true, allowSkips: true, allowErrors: true),
          'unfinished review');
    });
  }

  test('rejects missing verdicts despite completed=true and allowed skips', () {
    outcome('skipped');
    report['cases'][0]['checklist'][0]['verdict'] = null;
    expectRejected(verify(allowSkips: true), 'unfinished review');
  });

  test('rejects claimed passing status hiding a failed verdict', () {
    report['cases'][0]['checklist'][0]['verdict'] = 'fail';
    expectRejected(verify(allowFailures: true), 'status does not match');
  });

  test('rejects passed verdicts on an interrupted review', () {
    report['cases'][0]['completed'] = false;
    expectRejected(verify(allowSkips: true), 'unfinished review');
  });

  test('rejects terminal errors with contradictory review data', () {
    outcome('error', completed: false);
    report['cases'][0]['artifact_path'] = 'artifact';
    expectRejected(verify(allowErrors: true),
        'both a generator error and a review artifact');
  });

  for (final field in ['completed', 'checklist']) {
    test(
        'rejects terminal errors with $field data even when errors are allowed',
        () {
      outcome('error', completed: false);
      if (field == 'completed') {
        report['cases'][0]['completed'] = true;
      } else {
        report['cases'][0]['checklist'][0]['verdict'] = 'pass';
      }
      expectRejected(
          verify(allowErrors: true), 'review data without a review outcome');
    });
  }

  for (final field in [
    'expected_case_count',
    'completed_case_count',
    'complete',
    'successful'
  ]) {
    test('rejects inconsistent top-level $field', () {
      report[field] = field.endsWith('count') ? 99 : false;
      expect(verify().valid, isFalse);
    });
  }

  for (final status in ['passed', 'failed', 'skipped', 'error', 'pending']) {
    test('rejects an inconsistent $status summary count', () {
      report['summary'][status] = 99;
      expectRejected(verify(), 'Summary $status count does not match');
    });
  }
}
