import 'dart:convert';
import 'dart:io';

import 'package:overseer/overseer.dart';
import 'package:overseer/src/reporter/report_schema.dart' show loadReportSchema;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;
  late File schemaFile;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('overseer_schema_test_');
    schemaFile = File(p.join(tempDir.path, 'schema', 'report.v1.json'));
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
