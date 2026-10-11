import 'package:characters/characters.dart';
import 'package:termunicode/termunicode.dart';

/// Wraps plain text at spaces, splitting long words without splitting graphemes.
/// A single grapheme wider than [columns] is kept intact on its own line.
List<String> wrapTerminalText(
  String text,
  int columns, {
  String continuationIndent = '',
}) {
  if (columns <= 0) throw RangeError.range(columns, 1, null, 'columns');
  final indentWidth = widthString(continuationIndent);
  if (indentWidth >= columns) {
    throw ArgumentError.value(
        continuationIndent, 'continuationIndent', 'Must leave room for text');
  }

  final lines = <String>[];
  for (final paragraph
      in text.replaceAll('\r\n', '\n').replaceAll('\t', '    ').split('\n')) {
    final characters = paragraph.characters.toList();
    if (characters.isEmpty) {
      lines.add('');
      continue;
    }

    var start = 0;
    while (start < characters.length) {
      var indent = start == 0 ? '' : continuationIndent;
      var available = columns - (start == 0 ? 0 : indentWidth);
      if (widthString(characters[start]) > available) {
        indent = '';
        available = columns;
      }
      var end = start;
      var used = 0;
      var wordBreak = start;
      var hasText = false;
      while (end < characters.length) {
        final character = characters[end];
        final characterWidth = widthString(character);
        if (used + characterWidth > available && end > start) break;
        used += characterWidth;
        end++;
        if (character == ' ') {
          if (hasText) wordBreak = end;
        } else {
          hasText = true;
        }
        if (used > available) break;
      }
      if (end < characters.length && wordBreak > start) end = wordBreak;
      lines.add('$indent${characters.sublist(start, end).join()}');
      start = end;
    }
  }
  return lines;
}
