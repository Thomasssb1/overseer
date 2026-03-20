import 'checklist_verdict.dart';
import 'test_case.dart';

/// The collected answers from the interactive prompter for one [TestCase].
class ChecklistResult {
  const ChecklistResult({
    required this.testCase,
    required this.artifactPath,
    required this.verdicts,
    this.retryCount = 0,
  });

  final TestCase testCase;
  final String artifactPath;

  /// Verdicts keyed by checklist item text.
  final Map<String, ChecklistVerdict> verdicts;

  /// How many times this case was hot-retried.
  final int retryCount;

  /// Overall pass/fail: fails if any item scored [ChecklistVerdict.fail].
  bool get passed => verdicts.values.every((v) => v != ChecklistVerdict.fail);

  /// True if the user skipped every item (no y/n given).
  bool get fullySkipped =>
      verdicts.values.every((v) => v == ChecklistVerdict.skipped);
}
