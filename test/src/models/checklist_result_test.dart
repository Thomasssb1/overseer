import 'package:overseer/src/models/checklist_result.dart';
import 'package:overseer/src/models/checklist_verdict.dart';
import 'package:overseer/src/models/test_case.dart';
import 'package:test/test.dart';

void main() {
  group('ChecklistResult', () {
    const defaultTest = TestCase(
      name: 'foo',
      index: 0,
      params: {},
      checklist: ['Item 1', 'Item 2'],
    );

    test('passed is true when all verdicts are pass or skipped', () {
      const result = ChecklistResult(
        testCase: defaultTest,
        artifactPath: 'x.mp4',
        verdicts: {
          'Item 1': ChecklistVerdict.pass,
          'Item 2': ChecklistVerdict.skipped,
        },
      );
      expect(result.passed, isTrue);
    });

    test('passed is false when any verdict is fail', () {
      const result = ChecklistResult(
        testCase: defaultTest,
        artifactPath: 'x.mp4',
        verdicts: {
          'Item 1': ChecklistVerdict.pass,
          'Item 2': ChecklistVerdict.fail,
        },
      );
      expect(result.passed, isFalse);
    });

    test('fullySkipped is true only if all items are skipped', () {
      const allSkipped = ChecklistResult(
        testCase: defaultTest,
        artifactPath: 'x.mp4',
        verdicts: {
          'Item 1': ChecklistVerdict.skipped,
          'Item 2': ChecklistVerdict.skipped,
        },
      );
      expect(allSkipped.fullySkipped, isTrue);

      const mixed = ChecklistResult(
        testCase: defaultTest,
        artifactPath: 'x.mp4',
        verdicts: {
          'Item 1': ChecklistVerdict.skipped,
          'Item 2': ChecklistVerdict.pass,
        },
      );
      expect(mixed.fullySkipped, isFalse);
    });
  });
}
