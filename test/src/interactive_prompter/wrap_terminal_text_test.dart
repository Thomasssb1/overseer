import 'package:overseer/src/interactive_prompter/wrap_terminal_text.dart';
import 'package:test/test.dart';

void main() {
  group('wrapTerminalText', () {
    test('keeps short and exactly fitting text on one line', () {
      expect(wrapTerminalText('short', 10), ['short']);
      expect(wrapTerminalText('exactlyten', 10), ['exactlyten']);
    });

    test('prefers word boundaries and retains spaces', () {
      expect(wrapTerminalText('one two three', 10), ['one two ', 'three']);
    });

    test('splits unbroken text without truncating it', () {
      expect(wrapTerminalText('abcdefghijkl', 5), ['abcde', 'fghij', 'kl']);
    });

    test('includes continuation indentation in the width', () {
      expect(wrapTerminalText('abcdefghijkl', 5, continuationIndent: '  '),
          ['abcde', '  fgh', '  ijk', '  l']);
    });

    test('does not wrap at leading indentation alone', () {
      expect(wrapTerminalText('  abcdefgh', 5), ['  abc', 'defgh']);
    });

    test('retains empty lines and normalizes CRLF line endings', () {
      expect(wrapTerminalText('', 5), ['']);
      expect(wrapTerminalText('ab\r\n\ncd\n', 5), ['ab', '', 'cd', '']);
    });

    test('expands tabs to prevent uncontrolled terminal tab stops', () {
      expect(wrapTerminalText('a\tb', 5), ['a    ', 'b']);
    });

    test('handles whitespace-only text and a one-column terminal', () {
      expect(wrapTerminalText('   ', 1), [' ', ' ', ' ']);
      expect(wrapTerminalText('abc', 1), ['a', 'b', 'c']);
    });

    test('counts East Asian characters as two columns', () {
      expect(wrapTerminalText('日本語abc', 4), ['日本', '語ab', 'c']);
    });

    test('keeps combining characters with their base character', () {
      expect(wrapTerminalText('e\u0301e\u0301x', 2), ['e\u0301e\u0301', 'x']);
    });

    test('keeps emoji code points and joined sequences intact', () {
      expect(wrapTerminalText('a😀bc', 3), ['a😀', 'bc']);
      expect(wrapTerminalText('x👩‍💻y', 4), ['x', '👩‍💻', 'y']);
    });

    test('drops indentation when needed to fit a grapheme', () {
      expect(
          wrapTerminalText('abc日', 3, continuationIndent: '  '), ['abc', '日']);
    });

    test('preserves a grapheme wider than the entire terminal', () {
      expect(wrapTerminalText('日a', 1), ['日', 'a']);
    });

    for (final width in [0, -1]) {
      test('rejects a nonpositive width of $width', () {
        expect(() => wrapTerminalText('text', width), throwsRangeError);
      });
    }

    for (final indent in ['   ', '    ', '日本']) {
      test('rejects indentation that leaves no room: "$indent"', () {
        expect(() => wrapTerminalText('text', 3, continuationIndent: indent),
            throwsArgumentError);
      });
    }
  });
}
