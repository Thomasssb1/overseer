import 'dart:convert';

import 'package:overseer/overseer.dart';
import 'package:test/test.dart';

void main() {
  test('serializes a successful verification and its case counts', () {
    final result = VerificationResult(
        errors: [], expectedCaseCount: 2, reportedCaseCount: 2);
    expect(result.valid, isTrue);
    expect(jsonDecode(jsonEncode(result.toJson())), {
      'valid': true,
      'summary': 'Verification passed: all 2 expected cases satisfy policy.',
      'expected_case_count': 2,
      'reported_case_count': 2,
      'errors': [],
    });
  });

  test('snapshots diagnostics and preserves unavailable counts on failure', () {
    final errors = ['Invalid JSON'];
    final result = VerificationResult(errors: errors);
    errors.clear();
    expect(result.valid, isFalse);
    expect(result.summary, 'Verification failed: 1 problem(s).');
    expect(result.toJson(), {
      'valid': false,
      'summary': result.summary,
      'expected_case_count': null,
      'reported_case_count': null,
      'errors': ['Invalid JSON'],
    });
    expect(() => result.errors.clear(), throwsUnsupportedError);
  });
}
