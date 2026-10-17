import 'dart:io';
import 'dart:isolate';

import 'package:yaml/yaml.dart';

import 'exceptions.dart';

/// The version from the installed Overseer package's pubspec, cached on first use.
final overseerVersion = loadOverseerVersion();

/// Reads Overseer's own pubspec independently of the current working directory.
///
/// Requires the installed package files, as does the report schema loader.
/// Throws [ReportException] if the pubspec is unavailable or invalid.
String loadOverseerVersion({
  Uri? Function(Uri) resolvePackageUri = Isolate.resolvePackageUriSync,
}) {
  final libraryUri = resolvePackageUri(
    Uri.parse('package:overseer/overseer.dart'),
  );
  if (libraryUri == null) {
    throw const ReportException(
        'Cannot resolve the installed Overseer package.');
  }
  final pubspecUri = libraryUri.resolve('../pubspec.yaml');
  if (!pubspecUri.isScheme('file')) {
    throw ReportException('Overseer pubspec must be a local file: $pubspecUri');
  }

  final Object? pubspec;
  try {
    pubspec = loadYaml(File.fromUri(pubspecUri).readAsStringSync());
  } on FileSystemException catch (e) {
    throw ReportException(
        'Cannot read Overseer pubspec at $pubspecUri: ${e.message}');
  } on YamlException catch (e) {
    throw ReportException(
        'Cannot parse Overseer pubspec at $pubspecUri: ${e.message}');
  }
  if (pubspec is! YamlMap) {
    throw const ReportException(
        'Overseer pubspec must contain a YAML mapping.');
  }
  final version = pubspec['version'];
  if (version is! String || version.trim().isEmpty) {
    throw const ReportException(
        'Overseer pubspec version must be a non-empty string.');
  }
  return version;
}
