import 'dart:convert';
import 'dart:io';

import 'package:overseer/overseer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late String matrixPath;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('overseer_strict_exit_');
    matrixPath = p.join(tempDir.path, 'matrix.yaml');
    File(matrixPath).writeAsStringSync('''
name: strict_exit
parameters: {color: [red, blue]}
checklist: [A, B]
''');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  // A subprocess verifies the actual exit status without affecting the tests.
  Future<({int code, String report})> runScript(
    List<String> inputs, {
    bool? strictExit = true,
    bool allowSkips = false,
    bool generatorError = false,
    ReportFormat format = ReportFormat.markdown,
    int initialExitCode = 0,
  }) async {
    final script = File(p.join(tempDir.path, 'review.dart'));
    script.writeAsStringSync('''
import 'dart:convert';
import 'dart:io';
import 'package:overseer/overseer.dart';

Future<void> main(List<String> arguments) async {
  final inputs = jsonDecode('${jsonEncode(inputs)}') as List<dynamic>;
  var readIndex = 0;
  exitCode = $initialExitCode;
  final runner = OverseerRunner(
    matrixPath: arguments[0],
    outputDir: arguments[1],
    autoOpen: false,
    ${strictExit == null ? '' : 'strictExit: $strictExit,'}
    allowSkips: $allowSkips,
    reportFormat: ReportFormat.${format.name},
    commitSha: 'a' * 40,
    maxRetries: 0,
    reader: () => inputs[readIndex++] as String,
    printer: (_) {},
    generator: (_) async {
      if ($generatorError) throw StateError('generation failed');
      return ArtifactResult(path: 'artifact');
    },
  );
  stdout.writeln(await runner.run());
}
''');
    final process = await Process.start(Platform.resolvedExecutable, [
      '--packages=${p.absolute('.dart_tool', 'package_config.json')}',
      script.path,
      matrixPath,
      tempDir.path,
    ]);
    final stdoutText = process.stdout.transform(utf8.decoder).join();
    final stderrText = process.stderr.transform(utf8.decoder).join();
    final int code;
    try {
      await process.stdin.close();
      code = await process.exitCode.timeout(const Duration(seconds: 20));
      expect(await stderrText, isEmpty);
    } finally {
      process.kill();
    }
    final report = File((await stdoutText).trim()).readAsStringSync();
    return (code: code, report: report);
  }

  for (final format in ReportFormat.values) {
    for (final (verdict, code) in [('y', 0), ('n', 1)]) {
      test('${format.name} review with $verdict exits $code and saves a report',
          () async {
        final result =
            await runScript([verdict, 'y', 'y', 'y'], format: format);
        expect(result.code, code);
        expect(
            result.report,
            startsWith(
                format == ReportFormat.json ? '{' : '# Overseer Test Report'));
      });
    }
  }

  test('strict exit is off by default', () async {
    final result = await runScript(['n', 's', 'y', 'y'], strictExit: null);
    expect(result.code, 0);
  });

  for (final allowSkips in [false, true]) {
    test(
        'skipped reviews exit ${allowSkips ? 0 : 1} with allowSkips $allowSkips',
        () async {
      final result = await runScript(['y', 's', 's', 's'],
          allowSkips: allowSkips, format: ReportFormat.json);
      expect(result.code, allowSkips ? 0 : 1);
      final report = jsonDecode(result.report);
      expect(report['complete'], isTrue);
      expect(report['successful'], isFalse);
    });
  }

  for (final (ending, inputs, generatorError) in [
    ('partial quit', ['y', 'q'], false),
    ('retry exhaustion', ['r'], false),
    ('generator error', ['s'], true),
  ]) {
    test('$ending exits 1 even when skips are allowed', () async {
      final result = await runScript(inputs,
          allowSkips: true, generatorError: generatorError);
      expect(result.code, 1);
    });
  }

  for (final (verdict, code) in [('y', 0), ('n', 1)]) {
    test('resumed $verdict verdict contributes to exit code $code', () async {
      final partial = await runScript([verdict, 'y', 'q']);
      expect(partial.code, 1);
      final resumed = await runScript(['y', 'y'], format: ReportFormat.json);
      expect(resumed.code, code);
      final report = jsonDecode(resumed.report);
      expect(report['complete'], isTrue);
      expect(report['cases'][0]['checklist'][0]['verdict'],
          verdict == 'y' ? 'pass' : 'fail');
    });

    test('preserves an existing exit code after a $verdict review', () async {
      final result =
          await runScript([verdict, 'y', 'y', 'y'], initialExitCode: 7);
      expect(result.code, 7);
    });
  }
}
