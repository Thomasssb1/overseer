import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:overseer/overseer.dart';
import 'package:overseer/src/reporter/report_schema.dart' show loadReportSchema;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File schemaFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('overseer_schema_test_');
    schemaFile = File(p.join(tempDir.path, 'schema', 'report.v2.json'));
    schemaFile.parent.createSync();
    schemaFile.writeAsStringSync('{"type": "object"}');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('reads the JSON file relative to the installed package', () {
    final libraryUri = File(p.join(tempDir.path, 'lib', 'overseer.dart')).uri;
    final schema = loadReportSchema(resolvePackageUri: (uri) {
      expect(uri, Uri.parse('package:overseer/overseer.dart'));
      return libraryUri;
    });
    expect(jsonDecode(schema), {'type': 'object'});
  });

  test('can still load v1 separately from the current schema', () {
    final legacyFile = File(p.join(tempDir.path, 'schema', 'report.v1.json'));
    legacyFile.writeAsStringSync('{"title": "legacy"}');
    final libraryUri = File(p.join(tempDir.path, 'lib', 'overseer.dart')).uri;
    expect(
        jsonDecode(
            loadReportSchema(version: 1, resolvePackageUri: (_) => libraryUri)),
        {'title': 'legacy'});
    expect(jsonDecode(loadReportSchema(resolvePackageUri: (_) => libraryUri)),
        {'type': 'object'});
  });

  for (final version in [-1, 0, 3]) {
    test('rejects unsupported schema version $version', () {
      expect(
          () => loadReportSchema(version: version),
          throwsA(isA<ReportException>().having((error) => error.message,
              'message', contains('Unsupported report schema version'))));
    });
  }

  test('preserves the strict v1 matrix shape and adds version tags only in v2',
      () {
    final legacy = jsonDecode(loadReportSchema(version: 1)) as Map;
    final current = jsonDecode(reportSchema) as Map;
    expect(legacy[r'$id'], endsWith('/report.v1.json'));
    expect(legacy['properties']['schema_version']['const'], 1);
    expect(legacy['properties']['matrix']['additionalProperties'], isFalse);
    expect(legacy['properties']['matrix']['properties'],
        isNot(contains('version')));
    expect(current[r'$id'], endsWith('/report.v2.json'));
    expect(current['properties']['schema_version']['const'], 2);
    expect(current['properties']['matrix']['properties'], contains('version'));
    final matrix = {'path': 'matrix.yaml', 'sha256': 'a' * 64};
    final legacyMatrix = JsonSchema.create(legacy['properties']['matrix']);
    final currentMatrix = JsonSchema.create(current['properties']['matrix']);
    expect(legacyMatrix.validate(matrix).isValid, isTrue);
    expect(legacyMatrix.validate({...matrix, 'version': '1.0.0'}).isValid,
        isFalse);
    expect(currentMatrix.validate({...matrix, 'version': '1.0.0'}).isValid,
        isTrue);
  });

  test('reports an unresolved package descriptively', () {
    expect(
        () => loadReportSchema(resolvePackageUri: (_) => null),
        throwsA(isA<ReportException>().having((e) => e.message, 'message',
            contains('Cannot resolve the installed Overseer package'))));
  });

  test('reports missing schema files descriptively', () {
    schemaFile.deleteSync();
    expect(
        () => loadReportSchema(
            resolvePackageUri: (_) =>
                File(p.join(tempDir.path, 'lib', 'overseer.dart')).uri),
        throwsA(isA<ReportException>().having((e) => e.message, 'message',
            contains('Cannot read report schema'))));
  });

  test('rejects a non-file package location descriptively', () {
    expect(
        () => loadReportSchema(
            resolvePackageUri: (_) =>
                Uri.parse('https://example.com/lib/overseer.dart')),
        throwsA(isA<ReportException>().having(
            (e) => e.message, 'message', contains('must be a local file'))));
  });

  test('loads the package schema when run outside the package directory', () {
    final script = File(p.join(tempDir.path, 'check.dart'));
    script.writeAsStringSync('''
import 'dart:convert';
import 'package:overseer/overseer.dart';

void main() {
  final schema = jsonDecode(reportSchema);
  if (schema['properties']['schema_version']['const'] != Reporter.schemaVersion) {
    throw StateError('Wrong schema');
  }
}
''');
    final result = Process.runSync(
        Platform.resolvedExecutable,
        [
          '--packages=${p.join(Directory.current.path, '.dart_tool', 'package_config.json')}',
          script.path,
        ],
        workingDirectory: tempDir.path);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
  });
}
