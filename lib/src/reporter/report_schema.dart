import 'dart:io';
import 'dart:isolate';

import 'package:json_schema/json_schema.dart';

import '../exceptions.dart';

final reportSchema = loadReportSchema();
final reportSchemaValidator = JsonSchema.create(reportSchema);
final reportSchemaV1Validator = JsonSchema.create(loadReportSchema(version: 1));
final reportSchemaV2Validator = JsonSchema.create(loadReportSchema(version: 2));

/// Reads the schema JSON from the installed package.
String loadReportSchema({
  int version = 3,
  Uri? Function(Uri) resolvePackageUri = Isolate.resolvePackageUriSync,
}) {
  if (version != 1 && version != 2 && version != 3) {
    throw ReportException('Unsupported report schema version: $version.');
  }
  final libraryUri = resolvePackageUri(
    Uri.parse('package:overseer/overseer.dart'),
  );
  if (libraryUri == null) {
    throw const ReportException(
        'Cannot resolve the installed Overseer package.');
  }
  final schemaUri = libraryUri.resolve('../schema/report.v$version.json');
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
