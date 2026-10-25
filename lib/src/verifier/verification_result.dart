/// The result of checking a report against a matrix, revision, and policy.
class VerificationResult {
  VerificationResult({
    required List<String> errors,
    this.expectedCaseCount,
    this.reportedCaseCount,
  }) : errors = List.unmodifiable(errors);

  final List<String> errors;

  /// Counts are unavailable when input validation could not be completed.
  final int? expectedCaseCount;
  final int? reportedCaseCount;

  bool get valid => errors.isEmpty;

  String get summary => valid
      ? 'Verification passed: all $expectedCaseCount expected cases satisfy policy.'
      : 'Verification failed: ${errors.length} problem(s).';

  Map<String, Object?> toJson() => {
        'valid': valid,
        'summary': summary,
        'expected_case_count': expectedCaseCount,
        'reported_case_count': reportedCaseCount,
        'errors': errors,
      };
}
