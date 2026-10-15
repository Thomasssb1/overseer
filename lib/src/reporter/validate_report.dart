import '../exceptions.dart';
import 'report_schema.dart';

/// Validates decoded report JSON, throwing [ReportException] for schema errors.
///
/// Commit identity, matrix identity, and review policy must be checked separately.
void validateReport(Object? report) {
  final validator = report is Map && report['schema_version'] == 1
      ? reportSchemaV1Validator
      : reportSchemaValidator;
  final result = validator.validate(report, validateFormats: true);
  if (!result.isValid) {
    throw ReportException('Invalid report: ${result.errors.join('; ')}');
  }
}
