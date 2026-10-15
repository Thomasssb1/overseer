import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:overseer/overseer.dart';
import 'package:overseer/src/lock_file/lock_file.dart';

void main() {
  late Directory tempDir;
  late String matrixPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('overseer_runner_test_');
    matrixPath = p.join(tempDir.path, 'test.matrix.yaml');
    File(matrixPath).writeAsStringSync('''
name: "integration_test"
parameters:
  color: [red, blue]
mode: list
checklist:
  - "Item 1"
''');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('matrix version appears in terminal prompts and Markdown reports',
      () async {
    final file = File(matrixPath);
    file.writeAsStringSync("version: '1.0.0'\n${file.readAsStringSync()}");
    final output = StringBuffer();
    final runner = OverseerRunner(
        matrixPath: matrixPath,
        outputDir: tempDir.path,
        autoOpen: false,
        reader: () => 'y',
        printer: output.write,
        generator: (testCase) async => ArtifactResult(path: 'artifact'));
    final path = await runner.run();
    final report = File(path).readAsStringSync();
    expect(output.toString(), contains('integration_test (version 1.0.0)'));
    expect(report, contains('**Matrix version:** 1.0.0'));
    expect(report, contains('integration_test (version 1.0.0) #1'));
    expect(report, contains('integration_test (version 1.0.0) #2'));
  });

  group('EOF', () {
    setUp(() {
      File(matrixPath).writeAsStringSync('''
name: eof_test
parameters:
  color: [red, blue, green]
mode: list
checklist:
  - Item 1
  - Item 2
''');
    });

    for (final completedCases in [0, 1]) {
      for (final partialReview in [false, true]) {
        test(
          'saves and resumes after $completedCases completed cases '
          'with partial review $partialReview',
          () async {
            final inputs = <String?>[
              ...List.filled(completedCases * 2, 'y'),
              if (partialReview) 'n',
              null,
            ];
            var readIndex = 0;
            final generatedIndices = <int>[];
            final output = StringBuffer();
            final runner = OverseerRunner(
              matrixPath: matrixPath,
              outputDir: tempDir.path,
              autoOpen: false,
              reader: () => inputs[readIndex++],
              printer: output.write,
              generator: (testCase) async {
                generatedIndices.add(testCase.index);
                return ArtifactResult(path: '/fake/${testCase.index}.txt');
              },
            );

            final reportPath = await runner.run();

            expect(readIndex, inputs.length);
            expect(generatedIndices, [
              for (var i = 0; i <= completedCases; i++) i,
            ]);
            expect(output.toString(), contains('Saving progress and quitting'));
            expect(output.toString(), contains('Report saved to: $reportPath'));
            expect(output.toString(), isNot(contains('case(s) complete')));
            expect(output.toString(), isNot(contains('Please enter')));
            final report = File(reportPath).readAsStringSync();
            final failedCases = partialReview ? 1 : 0;
            final reportedCases = completedCases + failedCases;
            expect(
              report,
              contains(
                  '| $reportedCases | $completedCases | $failedCases | 0 |'),
            );
            if (partialReview) {
              expect(report,
                  contains('### [❌ FAIL] eof_test #${completedCases + 1}'));
              expect(report, contains('| Item 1 | ❌ |'));
              expect(report, contains('| Item 2 | ⏭ |'));
            }

            final lock = LockFile.tryResume(
              matrixPath: matrixPath,
              directory: tempDir.path,
            );
            if (completedCases > 0) {
              expect(lock, isNotNull);
              expect(lock!.lastCompletedIndex, completedCases - 1);
              expect(lock.results, hasLength(completedCases));
            } else {
              expect(lock?.lastCompletedIndex ?? -1, -1);
            }

            final resumedIndices = <int>[];
            final resumed = OverseerRunner(
              matrixPath: matrixPath,
              outputDir: tempDir.path,
              autoOpen: false,
              reader: () => 'y',
              printer: (_) {},
              generator: (testCase) async {
                resumedIndices.add(testCase.index);
                return ArtifactResult(path: '/fake/${testCase.index}.txt');
              },
            );

            final resumedReportPath = await resumed.run();

            expect(resumedIndices, [
              for (var i = completedCases; i < 3; i++) i,
            ]);
            final resumedReport = File(resumedReportPath).readAsStringSync();
            expect(resumedReport, contains('| 3 | 3 | 0 | 0 |'));
            for (var i = 0; i < 3; i++) {
              expect(
                '### [✅ PASS] eof_test #${i + 1}'.allMatches(resumedReport),
                hasLength(1),
              );
            }
            expect(File(p.join(tempDir.path, '.overseer.lock')).existsSync(),
                isFalse);
          },
        );
      }
    }

    test('stops on EOF at the generator retry prompt and preserves progress',
        () async {
      final inputs = <String?>['y', 'y', null];
      var readIndex = 0;
      final generatedIndices = <int>[];
      final output = StringBuffer();
      final runner = OverseerRunner(
        matrixPath: matrixPath,
        outputDir: tempDir.path,
        autoOpen: false,
        reader: () => inputs[readIndex++],
        printer: output.write,
        generator: (testCase) async {
          generatedIndices.add(testCase.index);
          if (testCase.index == 1) throw StateError('Generation failed');
          return ArtifactResult(path: '/fake/${testCase.index}.txt');
        },
      );

      final reportPath = await runner.run();

      expect(readIndex, inputs.length);
      expect(generatedIndices, [0, 1]);
      expect(output.toString(), contains('Generator error'));
      expect(output.toString(), contains('Report saved to: $reportPath'));
      expect(output.toString(), isNot(contains('case(s) complete')));
      expect(
          File(reportPath).readAsStringSync(), contains('| 1 | 1 | 0 | 0 |'));
      final lock = LockFile.tryResume(
        matrixPath: matrixPath,
        directory: tempDir.path,
      );
      expect(lock, isNotNull);
      expect(lock!.lastCompletedIndex, 0);
      expect(lock.results, hasLength(1));
    });
  });

  group('retry exhaustion', () {
    setUp(() {
      File(matrixPath).writeAsStringSync('''
name: retry_test
parameters:
  color: [red, blue, green]
mode: list
checklist:
  - Item 1
''');
    });

    for (final maxRetries in [0, 2]) {
      for (final exhaustedIndex in [0, 1, 2]) {
        test(
          'stops and resumes case $exhaustedIndex with $maxRetries retries',
          () async {
            final inputs = [
              ...List.filled(exhaustedIndex, 'y'),
              ...List.filled(maxRetries + 1, 'r'),
            ];
            var readIndex = 0;
            final generatedIndices = <int>[];
            final output = StringBuffer();
            final runner = OverseerRunner(
              matrixPath: matrixPath,
              outputDir: tempDir.path,
              autoOpen: false,
              maxRetries: maxRetries,
              reader: () => inputs[readIndex++],
              printer: output.write,
              generator: (testCase) async {
                generatedIndices.add(testCase.index);
                return ArtifactResult(path: '/fake/${testCase.index}.txt');
              },
            );

            final reportPath = await runner.run();

            expect(readIndex, inputs.length);
            expect(generatedIndices, [
              for (var i = 0; i < exhaustedIndex; i++) i,
              ...List.filled(maxRetries + 1, exhaustedIndex),
            ]);
            expect(output.toString(), contains('Max retries reached'));
            expect(output.toString(), contains('Report saved to: $reportPath'));
            expect(output.toString(), isNot(contains('case(s) complete')));
            final report = File(reportPath).readAsStringSync();
            expect(
              report,
              contains('| $exhaustedIndex | $exhaustedIndex | 0 | 0 |'),
            );
            expect(
                report, isNot(contains('retry_test #${exhaustedIndex + 1}')));

            final lock = LockFile.tryResume(
              matrixPath: matrixPath,
              directory: tempDir.path,
            );
            if (exhaustedIndex > 0) {
              expect(lock, isNotNull);
              expect(lock!.lastCompletedIndex, exhaustedIndex - 1);
              expect(
                lock.results.map((result) => result.testCase.index),
                [for (var i = 0; i < exhaustedIndex; i++) i],
              );
            } else {
              // No completed cases need persisting before the first review.
              expect(lock?.lastCompletedIndex ?? -1, -1);
            }

            final resumedIndices = <int>[];
            final resumedOutput = StringBuffer();
            final resumed = OverseerRunner(
              matrixPath: matrixPath,
              outputDir: tempDir.path,
              autoOpen: false,
              reader: () => 'y',
              printer: resumedOutput.write,
              generator: (testCase) async {
                resumedIndices.add(testCase.index);
                return ArtifactResult(path: '/fake/${testCase.index}.txt');
              },
            );

            final resumedReportPath = await resumed.run();

            expect(resumedIndices, [
              for (var i = exhaustedIndex; i < 3; i++) i,
            ]);
            final resumedReport = File(resumedReportPath).readAsStringSync();
            expect(resumedReport, contains('| 3 | 3 | 0 | 0 |'));
            for (var i = 0; i < 3; i++) {
              expect(
                '### [✅ PASS] retry_test #${i + 1}'.allMatches(resumedReport),
                hasLength(1),
              );
            }
            expect(
              resumedOutput.toString(),
              contains('All 3 case(s) complete.'),
            );
            expect(
              File(p.join(tempDir.path, '.overseer.lock')).existsSync(),
              isFalse,
            );
          },
        );
      }
    }

    test('generator failures consume the same retry budget as hot retries',
        () async {
      final inputs = ['y', 'r', 'r'];
      var readIndex = 0;
      var failedOnce = false;
      final generatedIndices = <int>[];
      final output = StringBuffer();
      final runner = OverseerRunner(
        matrixPath: matrixPath,
        outputDir: tempDir.path,
        autoOpen: false,
        maxRetries: 1,
        reader: () => inputs[readIndex++],
        printer: output.write,
        generator: (testCase) async {
          generatedIndices.add(testCase.index);
          if (testCase.index == 1 && !failedOnce) {
            failedOnce = true;
            throw StateError('Generation failed');
          }
          return ArtifactResult(path: '/fake/${testCase.index}.txt');
        },
      );

      final reportPath = await runner.run();

      expect(generatedIndices, [0, 1, 1]);
      expect(readIndex, inputs.length);
      expect(output.toString(), contains('Generator error'));
      expect(output.toString(), contains('Max retries reached'));
      expect(output.toString(), isNot(contains('case(s) complete')));
      expect(
          File(reportPath).readAsStringSync(), contains('| 1 | 1 | 0 | 0 |'));
      final lock = LockFile.tryResume(
        matrixPath: matrixPath,
        directory: tempDir.path,
      );
      expect(lock, isNotNull);
      expect(lock!.lastCompletedIndex, 0);
      expect(lock.results, hasLength(1));
    });
  });

  test('reviews can complete at the retry limit with a fresh budget per case',
      () async {
    final inputs = ['r', 'y', 'r', 'n'];
    var readIndex = 0;
    final generatedIndices = <int>[];
    final output = StringBuffer();
    final runner = OverseerRunner(
      matrixPath: matrixPath,
      outputDir: tempDir.path,
      autoOpen: false,
      maxRetries: 1,
      reader: () => inputs[readIndex++],
      printer: output.write,
      generator: (testCase) async {
        generatedIndices.add(testCase.index);
        return ArtifactResult(path: '/fake/${testCase.index}.txt');
      },
    );

    final reportPath = await runner.run();

    expect(generatedIndices, [0, 0, 1, 1]);
    expect(readIndex, inputs.length);
    final report = File(reportPath).readAsStringSync();
    expect(report, contains('| 2 | 1 | 1 | 0 |'));
    expect('**Retries:** 1'.allMatches(report), hasLength(2));
    expect(output.toString(), contains('All 2 case(s) complete.'));
    expect(output.toString(), isNot(contains('Max retries reached')));
    expect(File(p.join(tempDir.path, '.overseer.lock')).existsSync(), isFalse);
  });

  test('full flow - pass, hot-retry, quit, resume, and finalise', () async {
    // 1st run:
    // Case 1 (red): passes immediately -> 'y'
    // Case 2 (blue): user asks for hot retry -> 'r', then saves and quits -> 'q'

    // So the inputs sequence: 'y', 'r', 'q'
    final inputs1 = ['y', 'r', 'q'];
    int readIndex1 = 0;

    int generateCalls1 = 0;

    final runner1 = OverseerRunner(
      matrixPath: matrixPath,
      outputDir: tempDir.path,
      autoOpen: false,
      reader: () => inputs1[readIndex1++],
      printer: (_) {},
      generator: (tc) async {
        generateCalls1++;
        return ArtifactResult(path: '/fake/path/${tc.params['color']}');
      },
    );

    final reportPath1 = await runner1.run();
    expect(File(reportPath1).existsSync(), isTrue);

    // Lockfile should have `lastCompletedIndex = 0`.
    expect(File(p.join(tempDir.path, '.overseer.lock')).existsSync(), isTrue);

    // Generator should be called 3 times:
    // 1: Case 1 (red)
    // 2: Case 2 (blue)
    // 3: Case 2 retry (blue) after user inputs 'r'
    expect(generateCalls1, 3);

    // 2nd run: resume and finish
    // Since lastCompletedIndex is 0, it skips index 0 and starts at index 1.
    final inputs2 = ['n']; // fail the item
    int readIndex2 = 0;
    int generateCalls2 = 0;

    final runner2 = OverseerRunner(
      matrixPath: matrixPath,
      outputDir: tempDir.path,
      autoOpen: false,
      reader: () => inputs2[readIndex2++],
      printer: (_) {},
      generator: (tc) async {
        generateCalls2++;
        return ArtifactResult(path: '/fake/path/${tc.params['color']}');
      },
    );

    final reportPath2 = await runner2.run();
    expect(File(reportPath2).existsSync(), isTrue);

    // Generator should be called only 1 time: Case 2 (blue)
    expect(generateCalls2, 1);

    // Lock file should be cleared since we reached the end
    expect(File(p.join(tempDir.path, '.overseer.lock')).existsSync(), isFalse);

    // Read the final report
    final report = File(reportPath2).readAsStringSync();
    expect(report, contains('✅ Passed | ❌ Failed | ⏭ Skipped'));
    expect(
        report,
        contains(
            '| 2 | 1 | 1 | 0 |')); // Total 2 cases, 1 pass (red), 1 fail (blue)
  });
}
