import 'dart:io';
import 'dart:isolate';

import 'package:json_schema/json_schema.dart';

import '../exceptions.dart';

final reportSchema = loadReportSchema();
final reportSchemaValidator = JsonSchema.create(reportSchema);

/// Reads the installed package's schema, or a sidecar for standalone executables.
String loadReportSchema({
  Uri? Function(Uri) resolvePackageUri = Isolate.resolvePackageUriSync,
  Uri? executableUri,
}) {
  final libraryUri = resolvePackageUri(
    Uri.parse('package:overseer/overseer.dart'),
  );
  final schemaUri = libraryUri?.resolve('../schema/report-v1.schema.json') ??
      (executableUri ?? Platform.script)
          .resolve('schema/report-v1.schema.json');
  if (!schemaUri.isScheme('file')) {
    throw ReportException('Report schema must be a local file: $schemaUri');
  }
  try {
    return File.fromUri(schemaUri).readAsStringSync();
  } on FileSystemException catch (e) {
    throw ReportException(
        'Cannot read report schema at $schemaUri: ${e.message}');
  }
}
