import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:overseer/overseer.dart';

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
    expect(report, contains('| 2 | 1 | 1 | 0 |')); // Total 2 cases, 1 pass (red), 1 fail (blue)
  });
}
