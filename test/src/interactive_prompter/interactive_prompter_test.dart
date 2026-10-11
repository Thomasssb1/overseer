import 'dart:io';

import 'package:ansi_styles/ansi_styles.dart';
import 'package:termunicode/termunicode.dart';
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

    test('prints correctly formatted header without escaped templates',
        () async {
      int readCount = 0;
      final inputs = ['y', 'y'];
      final buffer = StringBuffer();

      final prompter = InteractivePrompter(
        autoOpen: false,
        reader: () => inputs[readCount++],
        printer: (msg) => buffer.write(msg),
        terminalWidth: 80,
      );

      await prompter.prompt(artifact, testCase, retryCount: 2);
      final output = AnsiStyles.strip(buffer.toString());

      // Ensure the variables are interpolated
      expect(output, contains('Case 1: prompter_test #1 [resolution=1080]'));
      expect(output, contains('Artifact: /tmp/output.mp4'));
      expect(output, contains('Retry #2'));
      // ASCII box drawing character check
      expect(output, contains('─' * 60));
      // Ensure there are no literal dollar signs left (which would mean failed interpolation)
      expect(output.contains(r'$'), isFalse);
    });

    for (final width in [1, 2, 3, 4, 12, 32, 80, 120]) {
      test('wraps long header values within $width columns', () async {
        final longCase = TestCase(
          name: 'a lengthy case name',
          index: 42,
          params: {'prompt': 'a detailed prompt ${'long' * 60}'},
          checklist: [],
        );
        final path = '/tmp/folder with spaces/${'artifact' * 30}.png';
        final output = StringBuffer();
        final prompter = InteractivePrompter(
          autoOpen: false,
          printer: output.write,
          terminalWidth: width,
        );

        final outcome = await prompter
            .prompt(ArtifactResult(path: path), longCase, retryCount: 123);

        expect(outcome, isA<PromptCompleted>());
        final plain = AnsiStyles.strip(output.toString());
        final lines = plain.split('\n');
        expect(lines.map(widthString), everyElement(lessThanOrEqualTo(width)));
        expect(lines.where((line) => line == '─' * width), hasLength(2));
        final compact = plain.replaceAll(RegExp(r'[\s─]'), '');
        final expected = 'Case 43: ${longCase.label}Artifact: $path'
            'Retry #123Keys: [y] pass [n] fail [s] skip [r] retry [q] save & quit';
        expect(compact, expected.replaceAll(RegExp(r'\s'), ''));
      });
    }

    test('wraps Unicode values without splitting graphemes', () async {
      final output = StringBuffer();
      final unicodeCase = TestCase(
        name: '日本語 😀',
        index: 0,
        params: {'prompt': 'e\u0301👩‍💻' * 20},
        checklist: [],
      );
      final prompter = InteractivePrompter(
        autoOpen: false,
        printer: output.write,
        terminalWidth: 20,
      );

      await prompter.prompt(ArtifactResult(path: '/tmp/画像😀.png'), unicodeCase);

      final plain = AnsiStyles.strip(output.toString());
      expect(plain.split('\n').map(widthString),
          everyElement(lessThanOrEqualTo(20)));
      expect('e\u0301'.allMatches(plain), hasLength(20));
      expect('👩‍💻'.allMatches(plain), hasLength(20));
      expect(plain, contains('/tmp/画像😀.png'));
      expect(plain, isNot(contains('Retry #')));
    });

    for (final width in [0, -10]) {
      test('falls back to 80 columns for invalid width $width', () async {
        final output = StringBuffer();
        final prompter = InteractivePrompter(
          autoOpen: false,
          printer: output.write,
          terminalWidth: width,
        );

        await prompter.prompt(
          ArtifactResult(path: 'x' * 200),
          const TestCase(name: 'fallback', index: 0, params: {}, checklist: []),
        );

        final plain = AnsiStyles.strip(output.toString());
        expect(plain, contains('─' * 80));
        expect(plain.split('\n').map(widthString),
            everyElement(lessThanOrEqualTo(80)));
      });
    }

    test('uses an 80-column fallback when stdout is redirected', () async {
      if (stdout.hasTerminal) return;
      final output = StringBuffer();
      final prompter = InteractivePrompter(
        autoOpen: false,
        printer: output.write,
      );

      await prompter.prompt(
        ArtifactResult(path: 'x' * 200),
        const TestCase(name: 'redirected', index: 0, params: {}, checklist: []),
      );

      final plain = AnsiStyles.strip(output.toString());
      expect(plain, contains('─' * 80));
      expect(plain.split('\n').map(widthString),
          everyElement(lessThanOrEqualTo(80)));
    });

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
      expect(quit.partial!.artifactPath, '/tmp/output.mp4');
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

    test('quits immediately on EOF without requesting more input', () async {
      final inputs = <String?>[null];
      var readCount = 0;
      final output = StringBuffer();
      final prompter = InteractivePrompter(
        autoOpen: false,
        reader: () => inputs[readCount++],
        printer: output.write,
      );

      final outcome = await prompter.prompt(artifact, testCase);

      expect(outcome, isA<PromptQuit>());
      expect((outcome as PromptQuit).partial, isNull);
      expect(readCount, 1);
      expect(output.toString(), contains('Saving progress and quitting'));
      expect(output.toString(), isNot(contains('Please enter')));
    });

    for (final (answer, verdict) in [
      ('y', ChecklistVerdict.pass),
      ('n', ChecklistVerdict.fail),
      ('s', ChecklistVerdict.skipped),
    ]) {
      test('EOF preserves a partial $answer review and retry count', () async {
        final inputs = <String?>[answer, null];
        var readCount = 0;
        final output = StringBuffer();
        final prompter = InteractivePrompter(
          autoOpen: false,
          reader: () => inputs[readCount++],
          printer: output.write,
        );

        final outcome =
            await prompter.prompt(artifact, testCase, retryCount: 2);

        expect(outcome, isA<PromptQuit>());
        final partial = (outcome as PromptQuit).partial;
        expect(partial, isNotNull);
        expect(partial!.testCase, same(testCase));
        expect(partial.artifactPath, artifact.path);
        expect(partial.retryCount, 2);
        expect(partial.verdicts, {'Question 1': verdict});
        expect(readCount, 2);
        expect(output.toString(), contains('Saving progress and quitting'));
        expect(output.toString(), isNot(contains('Please enter')));
      });
    }

    test('repeats prompt cleanly if input is blank or unrecognized', () async {
      int readCount = 0;
      final inputs = ['', '   ', 'invalid', 'garbage', 'y', 's'];

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
      expect(readCount, inputs.length);
    });
  });
}
