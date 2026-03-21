/// overseer — Human-in-the-loop testing framework for backend artifacts.
///
/// ## Quick start
/// ```dart
/// import 'package:overseer/overseer.dart';
///
/// void main() async {
///   // Create a matrix engine from your matrix file.
///   final engine = MatrixEngine.fromFile('tests/my_test.matrix.yaml');
///
///   // Wrap the engine with an execution wrapper that knows how
///   // to turn each test case into an artifact.
///   final wrapper = ExecutionWrapper(
///     engine: engine,
///     generator: (tc) async {
///       final path = await myGenerateArtifact(tc.params);
///       return ArtifactResult(path: path);
///     },
///   );
///
///   await wrapper.run();
/// }
/// ```
library overseer;

export 'src/exceptions.dart';
export 'src/execution_wrapper/execution_wrapper.dart'
    show ExecutionWrapper, ArtifactGenerator;
export 'src/matrix_engine/matrix_engine.dart' show MatrixEngine;
export 'src/matrix_engine/matrix_mode.dart' show MatrixMode;
export 'src/models.dart';
