import 'dart:io';

import 'package:overseer/src/exceptions.dart';
import 'package:overseer/src/matrix_engine/matrix_engine.dart';
import 'package:test/test.dart';

void main() {
  group('MatrixEngine.load', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('overseer_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    String createYamlFile(String content) {
      final file = File('${tempDir.path}/test.matrix.yaml');
      file.writeAsStringSync(content);
      return file.path;
    }

    test('throws MatrixParseException if file does not exist', () {
      expect(
        () => MatrixEngine.load('non_existent.yaml'),
        throwsA(isA<MatrixParseException>()),
      );
    });

    test('throws MatrixParseException if file is not a map', () {
      final path = createYamlFile('- just a list\n- not a map');
      expect(
        () => MatrixEngine.load(path),
        throwsA(isA<MatrixParseException>()),
      );
    });

    test('throws MatrixParseException if missing required fields', () {
      final path = createYamlFile('''
parameters:
  resolution: [1080]
''');
      expect(
        () => MatrixEngine.load(path),
        throwsA(isA<MatrixParseException>()),
      );
    });

    test('expands permutations mode correctly', () {
      final path = createYamlFile('''
name: permutations_test
mode: permutations
checklist:
  - "Looks good"
parameters:
  res: [720, 1080]
  codec: [h264, h265]
''');

      final cases = MatrixEngine.load(path);
      expect(cases, hasLength(4));

      expect(cases[0].params, {'res': 720, 'codec': 'h264'});
      expect(cases[1].params, {'res': 720, 'codec': 'h265'});
      expect(cases[2].params, {'res': 1080, 'codec': 'h264'});
      expect(cases[3].params, {'res': 1080, 'codec': 'h265'});

      for (var i = 0; i < cases.length; i++) {
        expect(cases[i].name, 'permutations_test');
        expect(cases[i].index, i);
        expect(cases[i].checklist, ['Looks good']);
      }
    });

    test('expands list mode correctly', () {
      final path = createYamlFile('''
name: list_test
mode: list
checklist:
  - "Audio is synced"
parameters:
  res: [720, 1080]
  bitrate: [low, high]
''');

      final cases = MatrixEngine.load(path);
      expect(cases, hasLength(2));

      expect(cases[0].params, {'res': 720, 'bitrate': 'low'});
      expect(cases[1].params, {'res': 1080, 'bitrate': 'high'});
    });

    test('list mode defaults when mode is not provided', () {
      final path = createYamlFile('''
name: list_default_test
checklist:
  - "Audio is synced"
parameters:
  res: [720, 1080]
  bitrate: [low, high]
''');

      final cases = MatrixEngine.load(path);
      expect(cases, hasLength(2));
      expect(cases[0].params, {'res': 720, 'bitrate': 'low'});
    });

    test(
        'list mode throws MatrixParseException if lists have different lengths',
        () {
      final path = createYamlFile('''
name: invalid_list_test
mode: list
checklist:
  - "Ok"
parameters:
  res: [720, 1080]
  bitrate: [low] # Mismatched length!
''');

      expect(
        () => MatrixEngine.load(path),
        throwsA(isA<MatrixParseException>()),
      );
    });

    test('throws MatrixParseException if parameter value is a map', () {
      final path = createYamlFile('''
name: invalid_param_test
checklist: ["Ok"]
parameters:
  res: {width: 1080, height: 720}
''');
      expect(
        () => MatrixEngine.load(path),
        throwsA(isA<MatrixParseException>()),
      );
    });

    test(
        'throws MatrixParseException if parameter list contains complex objects',
        () {
      final path = createYamlFile('''
name: invalid_param_test
checklist: ["Ok"]
parameters:
  res: [1080, {foo: bar}]
''');
      expect(
        () => MatrixEngine.load(path),
        throwsA(isA<MatrixParseException>()),
      );
    });

    test(
        'throws YamlException wrapped in MatrixParseException for invalid syntax',
        () {
      final path = createYamlFile('invalid: yaml: : syntax');
      expect(
        () => MatrixEngine.load(path),
        throwsA(isA<MatrixParseException>().having(
          (e) => e.message,
          'message',
          contains('Failed to parse matrix YAML'),
        )),
      );
    });

    test('throws MatrixParseException if mode is not a string', () {
      final path = createYamlFile('''
name: invalid_mode_test
checklist: ["Ok"]
mode: 123
parameters:
  res: [1080]
''');
      expect(
        () => MatrixEngine.load(path),
        throwsA(isA<MatrixParseException>().having(
          (e) => e.message,
          'message',
          contains("Field 'mode' must be a string"),
        )),
      );
    });
  });
}
