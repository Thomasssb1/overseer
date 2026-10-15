import 'dart:io';

import 'package:overseer/overseer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String matrixPath;
  final revision = 'a' * 40;
  final otherRevision = 'b' * 40;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('overseer_context_test_');
    matrixPath = p.join(tempDir.path, 'matrix.yaml');
    File(matrixPath).writeAsStringSync('abc');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('captures raw-byte SHA-256 and explicit commit override', () {
    final context = ReportContext.capture(
      matrixPath: matrixPath,
      cases: [],
      commitSha: revision,
      environment: {'GITHUB_SHA': otherRevision},
    );
    expect(context.matrixPath, matrixPath);
    expect(context.matrixSha256,
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    expect(context.commitSha, revision);
    File(matrixPath).writeAsStringSync('abcd');
    expect(
        ReportContext.capture(
                matrixPath: matrixPath, cases: [], commitSha: revision)
            .matrixSha256,
        isNot(context.matrixSha256));
  });

  test('uses GITHUB_SHA when no explicit revision is supplied', () {
    final context = ReportContext.capture(
        matrixPath: matrixPath,
        cases: [],
        environment: {'GITHUB_SHA': ' $revision\n'});
    expect(context.commitSha, revision);
  });

  test('leaves revision null outside a Git repository', () {
    final context = ReportContext.capture(
        matrixPath: matrixPath, cases: [], environment: {});
    expect(context.commitSha, isNull);
  });

  test('falls back to Git HEAD in the matrix directory', () {
    for (final args in [
      ['init'],
      ['add', 'matrix.yaml'],
      [
        '-c',
        'user.name=Overseer Test',
        '-c',
        'user.email=test@example.com',
        '-c',
        'commit.gpgsign=false',
        'commit',
        '-m',
        'Test matrix'
      ],
    ]) {
      final result = Process.runSync('git', ['-C', tempDir.path, ...args]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    }
    final head =
        Process.runSync('git', ['-C', tempDir.path, 'rev-parse', 'HEAD']);
    final context = ReportContext.capture(
        matrixPath: matrixPath, cases: [], environment: {'GITHUB_SHA': ''});
    expect(context.commitSha, '${head.stdout}'.trim());
  });

  test('throws a descriptive exception for an unreadable matrix', () {
    expect(
        () =>
            ReportContext.capture(matrixPath: '$matrixPath.missing', cases: []),
        throwsA(isA<ReportException>()));
  });

  test('rejects invalid hashes, revisions, and case indices', () {
    final hash = 'a' * 64;
    expect(
        () => ReportContext(
            matrixPath: matrixPath, matrixSha256: 'invalid', cases: []),
        throwsA(isA<ReportException>()));
    expect(
        () => ReportContext(
            matrixPath: matrixPath,
            matrixSha256: hash,
            commitSha: 'short-sha',
            cases: []),
        throwsA(isA<ReportException>()));
    expect(
        () => ReportContext(matrixPath: matrixPath, matrixSha256: hash, cases: [
              TestCase(name: 'suite', index: 1, params: {}, checklist: ['A'])
            ]),
        throwsA(isA<ReportException>()));
  });

  test('snapshots the expected matrix against later mutation', () {
    final params = <String, dynamic>{'color': 'red'};
    final checklist = ['A'];
    final cases = [
      TestCase(name: 'suite', index: 0, params: params, checklist: checklist)
    ];
    final context = ReportContext(
        matrixPath: matrixPath, matrixSha256: 'a' * 64, cases: cases);
    params['color'] = 'blue';
    checklist.clear();
    cases.clear();
    expect(context.cases.single.params, {'color': 'red'});
    expect(context.cases.single.checklist, ['A']);
    expect(() => context.cases.clear(), throwsUnsupportedError);
  });

  test('rejects complex and non-finite parameters and empty checklists', () {
    for (final value in <dynamic>[[], {}, double.nan, double.infinity]) {
      expect(
          () => ReportContext(
                  matrixPath: matrixPath,
                  matrixSha256: 'a' * 64,
                  cases: [
                    TestCase(
                        name: 'suite',
                        index: 0,
                        params: {'invalid': value},
                        checklist: ['A'])
                  ]),
          throwsA(isA<ReportException>()));
    }
    expect(
        () => ReportContext(
                matrixPath: matrixPath,
                matrixSha256: 'a' * 64,
                cases: [
                  TestCase(name: 'suite', index: 0, params: {}, checklist: [])
                ]),
        throwsA(isA<ReportException>()));
  });
}
