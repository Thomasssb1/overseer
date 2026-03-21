import '../exceptions.dart';
import '../models.dart';

/// Wraps the user-supplied generator function and handles errors cleanly.
///
/// Usage:
/// ```dart
/// final wrapper = ExecutionWrapper();
/// final result = await wrapper.run(testCase, (tc) async {
///   final path = await myGenerator(tc.params);
///   return ArtifactResult(path: path);
/// });
/// ```
class ExecutionWrapper {
  const ExecutionWrapper();

  /// Runs [generator] with [testCase] and returns the [ArtifactResult].
  ///
  /// If the generator throws, the exception is wrapped in a
  /// [GeneratorException] and rethrown so the caller can decide whether to
  /// hot-retry or abort.
  Future<ArtifactResult> run(
    TestCase testCase,
    ArtifactGenerator generator,
  ) async {
    try {
      return await generator(testCase);
    } on GeneratorException {
      rethrow;
    } catch (e, st) {
      Error.throwWithStackTrace(
        GeneratorException(
          'Generator failed for case "${testCase.label}".',
          cause: e,
        ),
        st,
      );
    }
  }
}

/// Signature for the user-supplied artifact generator.
typedef ArtifactGenerator = Future<ArtifactResult> Function(TestCase testCase);
