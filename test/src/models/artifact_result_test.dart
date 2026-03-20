import 'package:overseer/src/models/artifact_result.dart';
import 'package:test/test.dart';

void main() {
  group('ArtifactResult', () {
    test('has empty metadata by default', () {
      const result = ArtifactResult(path: 'out.mp4');
      expect(result.path, 'out.mp4');
      expect(result.metadata, isEmpty);
    });

    test('retains populated metadata', () {
      const result = ArtifactResult(
        path: 'out.mp4',
        metadata: {'duration': 5.0},
      );
      expect(result.metadata['duration'], 5.0);
    });
  });
}
