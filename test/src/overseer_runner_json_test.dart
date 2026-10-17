import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:overseer/overseer.dart';
import 'package:overseer/src/lock_file/lock_file.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String matrixPath;
  late List<int> generated;
  late List<String?> generatedVersions;
  final revision = 'a' * 40;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('overseer_runner_json_');
    matrixPath = p.join(tempDir.path, 'test.matrix.yaml');
    generated = [];
    generatedVersions = [];
    File(matrixPath).writeAsStringSync('''
name: json_test
parameters:
  color: [red, blue]
mode: list
checklist:
  - Looks good
''');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  Future<Map<String, dynamic>> runJson({
    List<String?> inputs = const ['y', 'y'],
    String? commitSha,
    int maxRetries = 5,
    ArtifactGenerator? generator,
  }) async {
    var readIndex = 0;
    final runner = OverseerRunner(
      matrixPath: matrixPath,
      outputDir: tempDir.path,
      reportFormat: ReportFormat.json,
      commitSha: commitSha ?? revision,
      autoOpen: false,
      maxRetries: maxRetries,
      reader: () => inputs[readIndex++],
      printer: (_) {},
      generator: (testCase) async {
        generated.add(testCase.index);
        generatedVersions.add(testCase.matrixVersion);
        if (generator != null) return generator(testCase);
        return ArtifactResult(path: 'artifact_${testCase.index}.txt');
      },
    );
    final path = await runner.run();
    expect(path, endsWith('.json'));
    expect(readIndex, inputs.length);
    final report =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    validateReport(report);
    expect(report['overseer_version'], overseerVersion);
    expect(report['commit_sha'], commitSha ?? revision);
    return report;
  }

  test('completed JSON run includes matrix identity and every expanded case',
      () async {
    final expectedHash =
        sha256.convert(File(matrixPath).readAsBytesSync()).toString();
    final json = await runJson();
    expect(json['commit_sha'], revision);
    expect(json['matrix'], {'path': matrixPath, 'sha256': expectedHash});
    expect(json['expected_case_count'], 2);
    expect(json['completed_case_count'], 2);
    expect(json['successful'], isTrue);
    expect(json['cases'][0]['params'], {'color': 'red'});
    expect(json['cases'][1]['params'], {'color': 'blue'});
    expect(File(p.join(tempDir.path, '.overseer.lock')).existsSync(), isFalse);
  });

  test('matrix version reaches generators, partial reports, locks, and resume',
      () async {
    final file = File(matrixPath);
    file.writeAsStringSync("version: '1.0.0'\n${file.readAsStringSync()}");
    final partial = await runJson(inputs: ['y', 'q']);
    expect(partial['matrix']['version'], '1.0.0');
    expect(partial['complete'], isFalse);
    expect(generatedVersions, ['1.0.0', '1.0.0']);
    final lock =
        LockFile.tryResume(matrixPath: matrixPath, directory: tempDir.path);
    expect(lock!.results.single.testCase.matrixVersion, '1.0.0');
    generated.clear();
    generatedVersions.clear();
    final resumed = await runJson(inputs: ['y']);
    expect(generated, [1]);
    expect(generatedVersions, ['1.0.0']);
    expect(resumed['matrix']['version'], '1.0.0');
    expect(resumed['completed_case_count'], 2);
    expect(resumed['successful'], isTrue);
  });

  for (final change in ['added', 'changed', 'removed', 'unchanged']) {
    test('starts a fresh review when the matrix version is $change', () async {
      final file = File(matrixPath);
      final original = file.readAsStringSync();
      file.writeAsStringSync(
          change == 'added' ? original : "version: '1.0.0'\n$original");
      await runJson(inputs: ['y', 'q']);
      final String? nextVersion;
      switch (change) {
        case 'added':
        case 'changed':
          nextVersion = '2.0.0';
          file.writeAsStringSync("version: '$nextVersion'\n$original");
        case 'removed':
          nextVersion = null;
          file.writeAsStringSync(original);
        default:
          nextVersion = '1.0.0';
          file.writeAsStringSync(
              "version: '1.0.0'\n${original.replaceFirst('red', 'green')}");
      }
      generated.clear();
      final json = await runJson();
      expect(generated, [0, 1]);
      expect(json['matrix']['version'], nextVersion);
      expect(json['successful'], isTrue);
    });
  }

  test('ignores locks written before matrix version tags were recognized',
      () async {
    final matrix = File(matrixPath);
    matrix.writeAsStringSync("version: '1.0.0'\n${matrix.readAsStringSync()}");
    await runJson(inputs: ['y', 'q']);
    final lock = File(p.join(tempDir.path, '.overseer.lock'));
    final data = jsonDecode(lock.readAsStringSync()) as Map<String, dynamic>;
    data['results'][0].remove('matrixVersion');
    lock.writeAsStringSync(jsonEncode(data));
    generated.clear();
    final json = await runJson();
    expect(generated, [0, 1]);
    expect(json['matrix']['version'], '1.0.0');
    expect(json['successful'], isTrue);
  });

  test('captures version before the generator can edit the matrix', () async {
    final file = File(matrixPath);
    file.writeAsStringSync("version: '1.0.0'\n${file.readAsStringSync()}");
    final json = await runJson(generator: (testCase) async {
      file.writeAsStringSync(
          file.readAsStringSync().replaceFirst('1.0.0', '2.0.0'));
      return ArtifactResult(path: 'artifact');
    });
    expect(json['matrix']['version'], '1.0.0');
    expect(generatedVersions, ['1.0.0', '1.0.0']);
    expect(file.readAsStringSync(), contains("version: '2.0.0'"));
  });

  test('completed failed and skipped reviews do not satisfy strict policy',
      () async {
    final json = await runJson(inputs: ['n', 's']);
    expect(json['complete'], isTrue);
    expect(json['successful'], isFalse);
    expect(json['summary'],
        {'passed': 0, 'failed': 1, 'skipped': 1, 'error': 0, 'pending': 0});
  });

  for (final input in <String?>['q', null]) {
    test('quit or EOF before reviewing retains every pending case: $input',
        () async {
      final json = await runJson(inputs: [input]);
      expect(json['expected_case_count'], 2);
      expect(json['completed_case_count'], 0);
      expect(json['complete'], isFalse);
      expect(json['successful'], isFalse);
      expect(json['summary']['pending'], 2);
    });

    test('partial review cannot count as completed: $input', () async {
      File(matrixPath).writeAsStringSync(
          '${File(matrixPath).readAsStringSync()}  - Second item\n');
      final json = await runJson(inputs: ['y', input]);
      expect(json['completed_case_count'], 0);
      expect(json['complete'], isFalse);
      expect(json['summary']['skipped'], 1);
      expect(json['summary']['pending'], 1);
      expect(json['cases'][0]['checklist'][1]['verdict'], 'skipped');
    });
  }

  test('hot retry exhaustion leaves the current and future cases pending',
      () async {
    final json = await runJson(inputs: ['r'], maxRetries: 0);
    expect(json['complete'], isFalse);
    expect(json['summary']['pending'], 2);
    expect(json['completed_case_count'], 0);
  });

  test('terminal generator errors are visible and preserve earlier progress',
      () async {
    final json = await runJson(
        inputs: ['y', 'r', null],
        maxRetries: 1,
        generator: (testCase) async {
          if (testCase.index == 1) throw StateError('generation failed');
          return ArtifactResult(path: 'artifact');
        });
    expect(generated, [0, 1, 1]);
    expect(json['complete'], isFalse);
    expect(json['successful'], isFalse);
    expect(json['summary'],
        {'passed': 1, 'failed': 0, 'skipped': 0, 'error': 1, 'pending': 0});
    expect(json['cases'][1]['error'], contains('generation failed'));
    expect(json['cases'][1]['retry_count'], 1);
    final lock =
        LockFile.tryResume(matrixPath: matrixPath, directory: tempDir.path);
    expect(lock!.lastCompletedIndex, 0);
    generated.clear();
    final resumed = await runJson(inputs: ['y']);
    expect(generated, [1]);
    expect(resumed['successful'], isTrue);
    expect(resumed['summary']['error'], 0);
  });

  test('a recovered generator failure is represented by the final review',
      () async {
    var attempts = 0;
    final json = await runJson(
        inputs: ['r', 'y', 'y'],
        generator: (testCase) async {
          if (attempts++ == 0) throw StateError('transient failure');
          return ArtifactResult(path: 'artifact');
        });
    expect(json['successful'], isTrue);
    expect(json['summary']['error'], 0);
    expect(json['cases'][0]['retry_count'], 1);
  });

  test('resuming includes each completed case exactly once', () async {
    final partial = await runJson(inputs: ['y', 'q']);
    expect(partial['complete'], isFalse);
    generated.clear();
    final resumed = await runJson(inputs: ['y']);
    expect(generated, [1]);
    expect(resumed['cases'].map((dynamic c) => c['index']), [0, 1]);
    expect(resumed['successful'], isTrue);
  });

  for (final change in ['matrix', 'commit', 'legacy']) {
    test('does not reuse progress from a different $change', () async {
      await runJson(inputs: ['y', 'q']);
      if (change == 'matrix') {
        File(matrixPath).writeAsStringSync(
            File(matrixPath).readAsStringSync().replaceFirst('red', 'green'));
      } else if (change == 'legacy') {
        final file = File(p.join(tempDir.path, '.overseer.lock'));
        final data =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        data.remove('matrixSha256');
        data.remove('commitSha');
        file.writeAsStringSync(jsonEncode(data));
      }
      generated.clear();
      final json =
          await runJson(commitSha: change == 'commit' ? 'b' * 40 : revision);
      expect(generated, [0, 1]);
      expect(json['successful'], isTrue);
    });
  }

  test('fingerprint is captured before the generator can edit the matrix',
      () async {
    final originalHash =
        sha256.convert(File(matrixPath).readAsBytesSync()).toString();
    final json = await runJson(generator: (testCase) async {
      File(matrixPath).writeAsStringSync('# changed during review\n');
      return ArtifactResult(path: 'artifact');
    });
    expect(json['matrix']['sha256'], originalHash);
    expect(json['matrix']['sha256'],
        isNot(sha256.convert(File(matrixPath).readAsBytesSync()).toString()));
  });

  test('report write failure keeps the completed lock for recovery', () async {
    File(p.join(tempDir.path, 'reports'))
        .writeAsStringSync('blocks report directory');
    await expectLater(runJson(), throwsA(isA<FileSystemException>()));
    final lock =
        LockFile.tryResume(matrixPath: matrixPath, directory: tempDir.path);
    expect(lock!.lastCompletedIndex, 1);
    expect(lock.results, hasLength(2));
  });
}
