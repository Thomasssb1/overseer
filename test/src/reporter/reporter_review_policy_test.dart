import 'package:overseer/overseer.dart';
import 'package:test/test.dart';

void main() {
  late List<TestCase> cases;
  late Reporter reporter;

  setUp(() {
    cases = [
      for (var i = 0; i < 2; i++)
        TestCase(
            name: 'suite', index: i, params: {'row': i}, checklist: ['A', 'B']),
    ];
    reporter = Reporter(
        context: ReportContext(
            matrixPath: 'matrix.yaml', matrixSha256: 'a' * 64, cases: cases));
  });

  void record(int index,
      {Map<String, ChecklistVerdict> verdicts = const {
        'A': ChecklistVerdict.pass,
        'B': ChecklistVerdict.pass,
      },
      bool completed = true}) {
    reporter.record(
        ChecklistResult(
            testCase: cases[index],
            artifactPath: 'artifact',
            verdicts: verdicts),
        completed: completed);
  }

  test('requires context to distinguish complete coverage from missing cases',
      () {
    expect(
        () => Reporter().meetsReviewPolicy(),
        throwsA(isA<ReportException>().having(
            (error) => error.message, 'message', contains('ReportContext'))));
  });

  test('an empty expected matrix never passes', () {
    reporter = Reporter(
        context: ReportContext(
            matrixPath: 'matrix.yaml', matrixSha256: 'a' * 64, cases: []));
    expect(reporter.meetsReviewPolicy(), isFalse);
    expect(reporter.meetsReviewPolicy(allowSkips: true), isFalse);
  });

  test('requires a completed passing review for every expected case', () {
    expect(reporter.meetsReviewPolicy(), isFalse);
    record(0);
    expect(reporter.meetsReviewPolicy(), isFalse);
    expect(reporter.meetsReviewPolicy(allowSkips: true), isFalse);
    record(1);
    expect(reporter.meetsReviewPolicy(), isTrue);
    expect(reporter.meetsReviewPolicy(allowSkips: true), isTrue);
  });

  test('a failed item fails policy even when skips are allowed', () {
    record(0);
    record(1, verdicts: {
      'A': ChecklistVerdict.fail,
      'B': ChecklistVerdict.skipped,
    });
    expect(reporter.meetsReviewPolicy(), isFalse);
    expect(reporter.meetsReviewPolicy(allowSkips: true), isFalse);
  });

  test('skipped items pass only when explicitly allowed', () {
    record(0);
    record(1, verdicts: {
      'A': ChecklistVerdict.pass,
      'B': ChecklistVerdict.skipped,
    });
    expect(reporter.meetsReviewPolicy(), isFalse);
    expect(reporter.meetsReviewPolicy(allowSkips: true), isTrue);
  });

  test('a terminal generator error fails policy even when skips are allowed',
      () {
    record(0);
    reporter.recordError(cases[1], StateError('generation failed'));
    expect(reporter.meetsReviewPolicy(), isFalse);
    expect(reporter.meetsReviewPolicy(allowSkips: true), isFalse);
  });

  test('a missing checklist answer fails even when skips are allowed', () {
    record(0);
    record(1, verdicts: {'A': ChecklistVerdict.pass});
    expect(reporter.meetsReviewPolicy(), isFalse);
    expect(reporter.meetsReviewPolicy(allowSkips: true), isFalse);
  });

  test('an interrupted review with passing answers still fails', () {
    record(0);
    record(1, completed: false);
    expect(reporter.meetsReviewPolicy(), isFalse);
    expect(reporter.meetsReviewPolicy(allowSkips: true), isFalse);
  });
}
