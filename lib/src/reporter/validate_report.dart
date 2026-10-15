import 'package:json_schema/json_schema.dart';

import '../exceptions.dart';
import 'report_schema.dart';

final _schema = JsonSchema.create(reportSchema);

/// Validates decoded report JSON, throwing [ReportException] for schema errors.
///
/// Commit identity, matrix identity, and review policy must be checked separately.
void validateReport(Object? report) {
  final result = _schema.validate(report, validateFormats: true);
  if (!result.isValid) {
    throw ReportException('Invalid report: ${result.errors.join('; ')}');
  }
}
