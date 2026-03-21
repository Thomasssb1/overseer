import 'overseer_exception.dart';

/// Thrown when the user's generator function throws an unhandled error.
class GeneratorException extends OverseerException {
  const GeneratorException(super.message, {this.cause});

  final Object? cause;

  @override
  String toString() =>
      'GeneratorException: $message${cause != null ? ' (cause: $cause)' : ''}';
}
