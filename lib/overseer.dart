/// overseer — Human-in-the-loop testing framework for backend artifacts.
///
/// ## Quick start
/// ```dart
/// import 'package:overseer/overseer.dart';
///
/// void main() async {
///   final runner = OverseerRunner(
///     matrixPath: 'tests/my_test.matrix.yaml',
///     generator: (tc) async {
///       // Your custom generation logic here
///       final path = await myGenerateArtifact(tc.params);
///       return ArtifactResult(path: path);
///     },
///   );
///
///   await runner.run();
/// }
/// ```
export 'src/exceptions.dart';
export 'src/execution_wrapper/execution_wrapper.dart'
    show ExecutionWrapper, ArtifactGenerator;
export 'src/matrix_engine/matrix_engine.dart' show MatrixEngine;
export 'src/matrix_engine/matrix_mode.dart' show MatrixMode;
export 'src/models.dart';
export 'src/overseer_runner.dart' show OverseerRunner;
