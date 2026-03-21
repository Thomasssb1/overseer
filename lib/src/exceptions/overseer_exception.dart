/// Thrown when overseer encounters an unrecoverable error.
class OverseerException implements Exception {
  const OverseerException(this.message);

  final String message;

  @override
  String toString() => 'OverseerException: $message';
}
