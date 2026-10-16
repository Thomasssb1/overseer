import 'dart:io';
import 'dart:isolate';

import 'package:overseer/overseer.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('compiled Overseer version matches the package release version', () {
    final libraryUri = Isolate.resolvePackageUriSync(
      Uri.parse('package:overseer/overseer.dart'),
    )!;
    final pubspec = loadYaml(
      File.fromUri(libraryUri.resolve('../pubspec.yaml')).readAsStringSync(),
    );
    expect(
      overseerVersion,
      pubspec['version'],
      reason: 'Update lib/src/version.dart when changing pubspec.yaml.',
    );
  });
}
