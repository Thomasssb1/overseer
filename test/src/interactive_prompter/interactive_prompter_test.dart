import 'package:test/test.dart';

import 'package:overseer/overseer.dart';
import 'package:overseer/src/interactive_prompter/interactive_prompter.dart';
import 'package:overseer/src/interactive_prompter/prompt_outcome.dart';

void main() {
  group('InteractivePrompter', () {
    const testCase = TestCase(
      name: 'prompter_test',
      index: 0,
      params: {'resolution': '1080'},
      checklist: ['Question 1', 'Question 2'],
    );

    final artifact = ArtifactResult(path: '/tmp/output.mp4');

    test('completes with all passes', () async {
      int readCount = 0;
      final inputs = ['y', 'y']; // answer 'pass' to both

      final prompter = InteractivePrompter(
        autoOpen: false, // Turn off auto-open for tests
        printer: (_) {}, // Silence prints
        reader: () => inputs[readCount++],
      );

      final outcome = await prompter.prompt(artifact, testCase);

      expect(outcome, isA<PromptCompleted>());
      final result = (outcome as PromptCompleted).result;

      expect(result.passed, isTrue);
      expect(result.fullySkipped, isFalse);
      expect(result.verdicts['Question 1'], ChecklistVerdict.pass);
      expect(result.verdicts['Question 2'], ChecklistVerdict.pass);
    });

    test('completes when answering y or n to all questions', () async {
      int readCount = 0;
      final inputs = ['y', 'n']; // answer 'pass' then 'fail'

      final prompter = InteractivePrompter(
        autoOpen: false, // Turn off auto-open for tests
        printer: (_) {}, // Silence prints
        reader: () => inputs[readCount++],
      );

      final outcome = await prompter.prompt(artifact, testCase);

      expect(outcome, isA<PromptCompleted>());
      final result = (outcome as PromptCompleted).result;

      expect(result.passed, isFalse); // Because of the 'n' answer
      expect(result.fullySkipped, isFalse);
      expect(result.verdicts['Question 1'], ChecklistVerdict.pass);
      expect(result.verdicts['Question 2'], ChecklistVerdict.fail);
    });

    test('exits early with PromptRetry when r is pressed', () async {
      int readCount = 0;
      final inputs = ['y', 'r']; // answer 'y' to first, then 'r' to retry

      final prompter = InteractivePrompter(
        autoOpen: false,
        printer: (_) {},
        reader: () => inputs[readCount++],
      );

      final outcome = await prompter.prompt(artifact, testCase);

      expect(outcome, isA<PromptRetry>());
    });

    test('exits early with PromptQuit and partial data when q is pressed',
        () async {
      int readCount = 0;
      final inputs = ['y', 'q']; // answer 'y', then 'q'

      final prompter = InteractivePrompter(
        autoOpen: false,
        printer: (_) {},
        reader: () => inputs[readCount++],
      );

      final outcome = await prompter.prompt(artifact, testCase);

      expect(outcome, isA<PromptQuit>());
      final quit = outcome as PromptQuit;

      expect(quit.partial, isNotNull);
      expect(quit.partial!.verdicts['Question 1'], ChecklistVerdict.pass);
      expect(quit.partial!.verdicts.containsKey('Question 2'), isFalse);
    });

    test('returns null partial if q is pressed immediately', () async {
      int readCount = 0;
      final inputs = ['q']; // immediately 'q'

      final prompter = InteractivePrompter(
        autoOpen: false,
        printer: (_) {},
        reader: () => inputs[readCount++],
      );

      final outcome = await prompter.prompt(artifact, testCase);

      expect(outcome, isA<PromptQuit>());
      final quit = outcome as PromptQuit;

      expect(quit.partial, isNull);
    });

    test('repeats prompt cleanly if input is unrecognized', () async {
      int readCount = 0;
      final inputs = [
        'invalid',
        'garbage',
        'y',
        's'
      ]; // garbage x2, then valid inputs

      final prompter = InteractivePrompter(
        autoOpen: false,
        printer: (_) {},
        reader: () => inputs[readCount++],
      );

      final outcome = await prompter.prompt(artifact, testCase);

      expect(outcome, isA<PromptCompleted>());
      final result = (outcome as PromptCompleted).result;

      expect(result.verdicts['Question 1'], ChecklistVerdict.pass);
      expect(result.verdicts['Question 2'], ChecklistVerdict.skipped);
    });
  });
}
