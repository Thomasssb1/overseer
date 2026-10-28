import '../exceptions.dart';
import '../matrix_engine/matrix_engine.dart';
import '../models.dart';
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
        if (!_matchesNameAndParameters(testCase, original)) {
          errors.add('Case $index name or parameters do not match the matrix.');
        }
        if (!_matchesChecklist(checklist, original.checklist)) {
          errors.add('Case $index checklist does not match the matrix.');
        }
      }

      final verdicts = checklist.map((item) => item['verdict']).toList();
      final status = _caseStatus(testCase, verdicts);
      counts[status] = counts[status]! + 1;
      if (testCase['completed'] == true) completed++;
      errors.addAll(_verifyCaseOutcome(
        testCase,
        verdicts,
        status: status,
        allowFailures: allowFailures,
        allowSkips: allowSkips,
        allowErrors: allowErrors,
      ));
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

bool _matchesNameAndParameters(
    Map<dynamic, dynamic> testCase, TestCase expected) {
  if (testCase['name'] != expected.name) return false;

  final params = _object(testCase['params']);
  if (params.length != expected.params.length) return false;
  for (final entry in expected.params.entries) {
    if (!params.containsKey(entry.key) || params[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

bool _matchesChecklist(
    List<Map<dynamic, dynamic>> checklist, List<String> expected) {
  if (checklist.length != expected.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (checklist[i]['item'] != expected[i]) return false;
  }
  return true;
}

String _caseStatus(Map<dynamic, dynamic> testCase, List<dynamic> verdicts) {
  if (testCase['error'] != null) return 'error';
  if (testCase['artifact_path'] == null) return 'pending';
  if (verdicts.contains('fail')) return 'failed';
  if (testCase['completed'] != true ||
      verdicts.contains('skipped') ||
      verdicts.contains(null)) {
    return 'skipped';
  }
  return 'passed';
}

List<String> _verifyCaseOutcome(
  Map<dynamic, dynamic> testCase,
  List<dynamic> verdicts, {
  required String status,
  required bool allowFailures,
  required bool allowSkips,
  required bool allowErrors,
}) {
  final errors = <String>[];
  final index = testCase['index'];
  final hasReview = testCase['artifact_path'] != null;
  final hasError = testCase['error'] != null;
  final isCompleted = testCase['completed'] == true;
  final hasReviewData =
      isCompleted || verdicts.any((verdict) => verdict != null);
  final isUnfinished = status == 'pending' ||
      (!hasError && (!isCompleted || verdicts.contains(null)));

  if (testCase['status'] != status) {
    errors.add('Case $index status does not match its recorded outcome '
        '(expected $status).');
  }
  if ((hasError || !hasReview) && hasReviewData) {
    errors.add('Case $index has review data without a review outcome.');
  }
  if (hasError && hasReview) {
    errors.add('Case $index has both a generator error and a review artifact.');
  }
  if (isUnfinished) {
    errors.add('Case $index has an unfinished review.');
  }
  if (verdicts.contains('fail') && !allowFailures) {
    errors.add('Case $index contains failed checklist verdicts.');
  }
  if (verdicts.contains('skipped') && !allowSkips) {
    errors.add('Case $index contains skipped checklist verdicts.');
  }
  if (hasError && !allowErrors) {
    errors.add('Case $index has a terminal generator error.');
  }
  return errors;
}

Map<dynamic, dynamic> _object(Object? value) {
  if (value is Map) return value;
  throw const ReportException('Expected a report JSON object.');
}

List<dynamic> _list(Object? value) {
  if (value is List) return value;
  throw const ReportException('Expected a report JSON array.');
}
