import 'package:overseer/overseer.dart';
import 'package:overseer/src/interactive_prompter/prompt_outcome.dart';
import 'package:test/test.dart';

void main() {
  test('existing import exposes every outcome for exhaustive matching', () {
    const result = ChecklistResult(
      testCase: TestCase(
        name: 'outcome_test',
        index: 0,
        params: {},
        checklist: ['Item 1'],
      ),
      artifactPath: '/fake/artifact.txt',
      verdicts: {'Item 1': ChecklistVerdict.pass},
    );
    final outcomes = <PromptOutcome>[
      PromptCompleted(result),
      PromptRetry(),
      PromptQuit(result),
      PromptQuit(null),
    ];

    expect(
      outcomes.map((outcome) => switch (outcome) {
            PromptCompleted(:final result) => ('completed', result),
            PromptRetry() => ('retry', null),
            PromptQuit(:final partial) => ('quit', partial),
          }),
      [
        ('completed', result),
        ('retry', null),
        ('quit', result),
        ('quit', null),
      ],
    );
  });
}
