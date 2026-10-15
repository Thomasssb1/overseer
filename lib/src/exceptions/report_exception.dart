import 'overseer_exception.dart';

/// Thrown when a report cannot be built from the supplied review data.
class ReportException extends OverseerException {
  const ReportException(super.message);

  @override
  String toString() => 'ReportException: $message';
}
