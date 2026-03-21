import 'overseer_exception.dart';

/// Thrown when a matrix YAML file is malformed or missing required fields.
class MatrixParseException extends OverseerException {
  const MatrixParseException(super.message);

  @override
  String toString() => 'MatrixParseException: $message';
}
