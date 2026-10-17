import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:overseer/overseer.dart';
import 'package:overseer/src/version.dart' show loadOverseerVersion;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  late Directory tempDir;
  late File pubspecFile;
  late Uri libraryUri;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('overseer_version_test_');
    final packageDir = p.join(tempDir.path, 'overseer package');
    pubspecFile = File(p.join(packageDir, 'pubspec.yaml'));
    pubspecFile.parent.createSync(recursive: true);
    pubspecFile.writeAsStringSync('name: overseer\nversion: 2.3.4\n');
    libraryUri = File(p.join(packageDir, 'lib', 'overseer.dart')).uri;
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  test('reads the version relative to the installed package', () {
    final version = loadOverseerVersion(resolvePackageUri: (uri) {
      expect(uri, Uri.parse('package:overseer/overseer.dart'));
      return libraryUri;
    });
    expect(version, '2.3.4');
  });

  test('reads updated versions including prerelease and build metadata', () {
    for (final version in ['3.0.0', '3.1.0-dev.2+build.7']) {
      pubspecFile.writeAsStringSync("name: overseer\nversion: '$version'\n");
      expect(
          loadOverseerVersion(resolvePackageUri: (_) => libraryUri), version);
    }
  });

  test('public version comes from the installed package pubspec', () {
    final installedLibraryUri = Isolate.resolvePackageUriSync(
        Uri.parse('package:overseer/overseer.dart'))!;
    final pubspec = loadYaml(
        File.fromUri(installedLibraryUri.resolve('../pubspec.yaml'))
            .readAsStringSync());
    expect(overseerVersion, pubspec['version']);
  });

  test('reports an unresolved package descriptively', () {
    expect(
        () => loadOverseerVersion(resolvePackageUri: (_) => null),
        throwsA(isA<ReportException>().having((e) => e.message, 'message',
            contains('Cannot resolve the installed Overseer package'))));
  });

  test('rejects a non-file package location descriptively', () {
    expect(
        () => loadOverseerVersion(
            resolvePackageUri: (_) =>
                Uri.parse('https://example.com/lib/overseer.dart')),
        throwsA(isA<ReportException>().having(
            (e) => e.message, 'message', contains('must be a local file'))));
  });

  test('reports an unreadable pubspec descriptively', () {
    pubspecFile.deleteSync();
    expect(
        () => loadOverseerVersion(resolvePackageUri: (_) => libraryUri),
        throwsA(isA<ReportException>().having((e) => e.message, 'message',
            contains('Cannot read Overseer pubspec'))));
  });

  for (final yaml in ['version: [', 'version: 1.0.0\nversion: 2.0.0']) {
    test('reports malformed pubspec YAML descriptively: $yaml', () {
      pubspecFile.writeAsStringSync(yaml);
      expect(
          () => loadOverseerVersion(resolvePackageUri: (_) => libraryUri),
          throwsA(isA<ReportException>().having((e) => e.message, 'message',
              contains('Cannot parse Overseer pubspec'))));
    });
  }

  for (final yaml in [
    '',
    'null',
    '[]',
    '[version, 1.0.0]',
    '1.0.0',
    '42',
    'true'
  ]) {
    test('rejects a non-mapping pubspec root: $yaml', () {
      pubspecFile.writeAsStringSync(yaml);
      expect(
          () => loadOverseerVersion(resolvePackageUri: (_) => libraryUri),
          throwsA(isA<ReportException>().having((e) => e.message, 'message',
              contains('must contain a YAML mapping'))));
    });
  }

  for (final version in ['', 'null', "''", "'   '", '42', 'true', '[]', '{}']) {
    test('rejects a missing, empty, or non-string version: $version', () {
      pubspecFile.writeAsStringSync('name: overseer\nversion: $version\n');
      expect(
          () => loadOverseerVersion(resolvePackageUri: (_) => libraryUri),
          throwsA(isA<ReportException>().having((e) => e.message, 'message',
              contains('version must be a non-empty string'))));
    });
  }

  test('rejects an omitted version', () {
    pubspecFile.writeAsStringSync('name: overseer\n');
    expect(
        () => loadOverseerVersion(resolvePackageUri: (_) => libraryUri),
        throwsA(isA<ReportException>().having((e) => e.message, 'message',
            contains('version must be a non-empty string'))));
  });

  test('reports use the dependency version instead of the caller pubspec', () {
    File(p.join(tempDir.path, 'pubspec.yaml'))
        .writeAsStringSync('name: consumer\nversion: 999.0.0\n');
    final script = File(p.join(tempDir.path, 'check.dart'));
    script.writeAsStringSync('''
import 'dart:convert';
import 'dart:io';
import 'package:overseer/overseer.dart';

Future<void> main() async {
  final context = ReportContext(
    matrixPath: 'matrix.yaml', matrixSha256: 'a' * 64, cases: []);
  final reports = <String, Object?>{'version': overseerVersion};
  for (final format in ReportFormat.values) {
    final reporter = Reporter(format: format, context: context);
    final path = await reporter.writeReport();
    reports[format.name] = File(path).readAsStringSync();
  }
  stdout.write(jsonEncode(reports));
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
    final reports = jsonDecode('${result.stdout}') as Map<String, dynamic>;
    expect(reports['version'], overseerVersion);
    expect(reports['version'], isNot('999.0.0'));
    expect(reports['markdown'],
        contains('**Overseer version:** $overseerVersion'));
    final jsonReport = jsonDecode(reports['json'] as String) as Map;
    expect(jsonReport['overseer_version'], overseerVersion);
    validateReport(jsonReport);
  });
}
