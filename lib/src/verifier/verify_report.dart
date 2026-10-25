import '../exceptions.dart';
import '../matrix_engine/matrix_engine.dart';
import '../reporter.dart';
import 'verification_result.dart';

/// Verifies decoded JSON against the exact matrix bytes and a full Git SHA.
///
/// Structural errors, invalid matrix inputs, provenance mismatches, inconsistent
/// outcomes, and incomplete coverage fail verification. Report paths are
/// informational and need not match local paths.
///
/// By default every checklist verdict must pass. Policy overrides allow failed
/// or skipped verdicts, or terminal generator errors. Pending and interrupted
/// reviews are always rejected, even when all overrides are enabled.
VerificationResult verifyReport(
  Object? report, {
  required String matrixPath,
  required String expectedSha,
  bool allowFailures = false,
  bool allowSkips = false,
  bool allowErrors = false,
}) {
  try {
    validateReport(report);
    final data = _object(report);
    final expected = MatrixEngine.load(matrixPath);
    final context = ReportContext.capture(
      matrixPath: matrixPath,
      cases: expected,
      commitSha: expectedSha,
    );
    final matrix = _object(data['matrix']);
    final cases = _list(data['cases']);
    final errors = <String>[];

    if (data['commit_sha'] != expectedSha) {
      errors.add('Commit SHA mismatch: expected $expectedSha, '
          'found ${data['commit_sha'] ?? 'unavailable'}.');
    }
    if (matrix['sha256'] != context.matrixSha256) {
      errors.add('Matrix SHA-256 does not match the supplied matrix file.');
    }
    // Legacy reports omit matrix version metadata; the byte hash still applies.
    if (data['schema_version'] != 1 &&
        matrix['version'] != context.matrixVersion) {
      errors.add('Matrix version does not match the supplied matrix file.');
    }
    if (data['expected_case_count'] != expected.length) {
      errors.add('Expected case count does not match the matrix '
          '(${expected.length}).');
    }

    final seen = <num>{};
    final counts = {
      for (final status in ['passed', 'failed', 'skipped', 'error', 'pending'])
        status: 0,
    };
    var completed = 0;
    for (final rawCase in cases) {
      final testCase = _object(rawCase);
      final index = testCase['index'];
      final checklist = _list(testCase['checklist']).map(_object).toList();
      if (index is! num || index < 0 || index >= expected.length) {
        errors.add('Unexpected case index: $index.');
      } else {
        if (!seen.add(index)) errors.add('Duplicate case index: $index.');
        final original = expected[index.toInt()];
        final params = _object(testCase['params']);
        if (testCase['name'] != original.name ||
            params.length != original.params.length ||
            original.params.entries.any((entry) =>
                !params.containsKey(entry.key) ||
                params[entry.key] != entry.value)) {
          errors.add('Case $index name or parameters do not match the matrix.');
        }
        if (checklist.length != original.checklist.length ||
            original.checklist
                .asMap()
                .entries
                .any((entry) => checklist[entry.key]['item'] != entry.value)) {
          errors.add('Case $index checklist does not match the matrix.');
        }
      }

      final verdicts = checklist.map((item) => item['verdict']).toList();
      final hasFailure = verdicts.contains('fail');
      final hasSkip = verdicts.contains('skipped');
      final hasMissing = verdicts.contains(null);
      final hasReview = testCase['artifact_path'] != null;
      final hasError = testCase['error'] != null;
      final isCompleted = testCase['completed'] == true;
      final String status;
      if (hasError) {
        status = 'error';
      } else if (!hasReview) {
        status = 'pending';
      } else if (hasFailure) {
        status = 'failed';
      } else if (!isCompleted || hasSkip || hasMissing) {
        status = 'skipped';
      } else {
        status = 'passed';
      }
      counts[status] = counts[status]! + 1;
      if (isCompleted) completed++;
      if (testCase['status'] != status) {
        errors.add('Case $index status does not match its recorded outcome '
            '(expected $status).');
      }
      if ((hasError || !hasReview) &&
          (isCompleted || verdicts.any((verdict) => verdict != null))) {
        errors.add('Case $index has review data without a review outcome.');
      }
      if (hasError && hasReview) {
        errors.add(
            'Case $index has both a generator error and a review artifact.');
      }
      if (status == 'pending' || (!hasError && (!isCompleted || hasMissing))) {
        errors.add('Case $index has an unfinished review.');
      }
      if (hasFailure && !allowFailures) {
        errors.add('Case $index contains failed checklist verdicts.');
      }
      if (hasSkip && !allowSkips) {
        errors.add('Case $index contains skipped checklist verdicts.');
      }
      if (hasError && !allowErrors) {
        errors.add('Case $index has a terminal generator error.');
      }
    }
    for (final testCase in expected) {
      if (!seen.contains(testCase.index)) {
        errors.add('Missing expected case ${testCase.index}.');
      }
    }

    final summary = _object(data['summary']);
    for (final entry in counts.entries) {
      if (summary[entry.key] != entry.value) {
        errors.add('Summary ${entry.key} count does not match case outcomes '
            '(${entry.value}).');
      }
    }
    if (data['completed_case_count'] != completed) {
      errors.add(
          'Completed case count does not match case outcomes ($completed).');
    }
    final complete = cases.length == expected.length &&
        seen.length == expected.length &&
        completed == expected.length;
    if (data['complete'] != complete) {
      errors
          .add('Report complete flag does not match case coverage/completion.');
    }
    final successful =
        expected.isNotEmpty && complete && counts['passed'] == expected.length;
    if (data['successful'] != successful) {
      errors.add('Report successful flag does not match case outcomes.');
    }
    return VerificationResult(
      errors: errors,
      expectedCaseCount: expected.length,
      reportedCaseCount: cases.length,
    );
  } on OverseerException catch (error) {
    return VerificationResult(errors: [error.message]);
  }
}

Map<dynamic, dynamic> _object(Object? value) {
  if (value is Map) return value;
  throw const ReportException('Expected a report JSON object.');
}

List<dynamic> _list(Object? value) {
  if (value is List) return value;
  throw const ReportException('Expected a report JSON array.');
}
