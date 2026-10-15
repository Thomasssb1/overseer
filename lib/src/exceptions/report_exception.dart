import 'overseer_exception.dart';

class ReportException extends OverseerException {
  const ReportException(super.message);

  @override
  String toString() => 'ReportException: $message';
}
