import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:overseer/overseer.dart';
import 'package:overseer/src/reporter/reporter.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

ChecklistResult _makeResult({
  String name = 'suite',
  int index = 0,
  Map<String, dynamic> params = const {},
  Map<String, ChecklistVerdict> verdicts = const {},
  int retryCount = 0,
  String artifactPath = '/tmp/artifact.mp4',
}) {
  return ChecklistResult(
    testCase: TestCase(
      name: name,
      index: index,
      params: params,
      checklist: verdicts.keys.toList(),
    ),
    artifactPath: artifactPath,
    verdicts: verdicts,
    retryCount: retryCount,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late Directory tempDir;
  late Reporter reporter;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('overseer_reporter_test_');
    reporter = Reporter(outputDir: tempDir.path);
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  group('Reporter – record and count', () {
    test('starts with 0 records', () {
      expect(reporter.count, 0);
    });

    test('count increments on each record() call', () {
      reporter.record(_makeResult());
      reporter.record(_makeResult(index: 1));
      expect(reporter.count, 2);
    });
  });

  group('Reporter – writeReport creates file', () {
    test('file is created in reports/ subdirectory', () async {
      reporter.record(_makeResult(
        verdicts: {'Item A': ChecklistVerdict.pass},
      ));
      final path = await reporter.writeReport();
      expect(File(path).existsSync(), isTrue);
      expect(path, contains('reports'));
      expect(path, contains('overseer_report_'));
      expect(path, endsWith('.md'));
    });

    test('creates reports/ directory if absent', () async {
      // tempDir has no reports/ yet
      reporter.record(_makeResult());
      await reporter.writeReport();
      expect(Directory(p.join(tempDir.path, 'reports')).existsSync(), isTrue);
    });
  });

  group('Reporter – markdown content', () {
    test('summary totals are correct for mixed results', () async {
      reporter.record(_makeResult(
        verdicts: {
          'Plays': ChecklistVerdict.pass,
          'No artefacts': ChecklistVerdict.pass,
        },
      ));
      reporter.record(_makeResult(
        index: 1,
        verdicts: {
          'Plays': ChecklistVerdict.fail,
        },
      ));
      reporter.record(_makeResult(
        index: 2,
        verdicts: {
          'Plays': ChecklistVerdict.skipped,
        },
      ));
      final path = await reporter.writeReport();
      final content = File(path).readAsStringSync();

      // Summary row: total=3, passed=1, failed=1, skipped=1
      expect(content, contains('| 3 |'));
      expect(content, contains('❌'));
      expect(content, contains('⏭'));
    });

    test('report contains case name and params', () async {
      reporter.record(_makeResult(
        name: 'video_check',
        params: {'resolution': '1080', 'bitrate': 'high'},
        verdicts: {'Plays': ChecklistVerdict.pass},
      ));
      final path = await reporter.writeReport();
      final content = File(path).readAsStringSync();
      expect(content, contains('video_check'));
      expect(content, contains('resolution'));
      expect(content, contains('1080'));
    });

    test('report shows retry count when > 0', () async {
      reporter.record(_makeResult(
        verdicts: {'Item': ChecklistVerdict.pass},
        retryCount: 2,
      ));
      final path = await reporter.writeReport();
      final content = File(path).readAsStringSync();
      expect(content, contains('Retries'));
    });

    test('report does NOT show retry field when retryCount is 0', () async {
      reporter.record(_makeResult(
        verdicts: {'Item': ChecklistVerdict.pass},
      ));
      final path = await reporter.writeReport();
      final content = File(path).readAsStringSync();
      expect(content, isNot(contains('Retries')));
    });

    test('all-pass result has PASS badge', () async {
      reporter.record(_makeResult(
        verdicts: {'Item': ChecklistVerdict.pass},
      ));
      final path = await reporter.writeReport();
      expect(File(path).readAsStringSync(), contains('[✅ PASS]'));
    });

    test('any-fail result has FAIL badge', () async {
      reporter.record(_makeResult(
        verdicts: {
          'Item A': ChecklistVerdict.pass,
          'Item B': ChecklistVerdict.fail,
        },
      ));
      final path = await reporter.writeReport();
      expect(File(path).readAsStringSync(), contains('[❌ FAIL]'));
    });

    test('all-skipped result has SKIPPED badge', () async {
      reporter.record(_makeResult(
        verdicts: {
          'Item A': ChecklistVerdict.skipped,
          'Item B': ChecklistVerdict.skipped,
        },
      ));
      final path = await reporter.writeReport();
      expect(File(path).readAsStringSync(), contains('[⏭ SKIPPED]'));
    });

    test('empty verdicts map produces valid report', () async {
      reporter.record(_makeResult());
      final path = await reporter.writeReport();
      expect(File(path).existsSync(), isTrue);
    });

    test('multiple writeReport() calls succeed', () async {
      reporter.record(_makeResult());
      final path1 = await reporter.writeReport();
      final path2 = await reporter.writeReport();
      expect(File(path1).existsSync(), isTrue);
      expect(File(path2).existsSync(), isTrue);
      expect(path1, isNot(equals(path2)));
    });
  });

  group('ChecklistResult helpers', () {
    test('passed is true when all verdicts are pass/skipped', () {
      final result = _makeResult(
        verdicts: {
          'A': ChecklistVerdict.pass,
          'B': ChecklistVerdict.skipped,
        },
      );
      expect(result.passed, isTrue);
    });

    test('passed is false when any verdict is fail', () {
      final result = _makeResult(
        verdicts: {
          'A': ChecklistVerdict.pass,
          'B': ChecklistVerdict.fail,
        },
      );
      expect(result.passed, isFalse);
    });

    test('fullySkipped is true when all verdicts are skipped', () {
      final result = _makeResult(
        verdicts: {'A': ChecklistVerdict.skipped},
      );
      expect(result.fullySkipped, isTrue);
    });

    test('fullySkipped is false when any verdict is not skipped', () {
      final result = _makeResult(
        verdicts: {
          'A': ChecklistVerdict.pass,
          'B': ChecklistVerdict.skipped,
        },
      );
      expect(result.fullySkipped, isFalse);
    });
  });
}
