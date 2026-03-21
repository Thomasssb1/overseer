import 'package:test/test.dart';

import 'package:overseer/overseer.dart';

void main() {
  const sampleChecklist = ['Item A', 'Item B'];
  const sampleCase = TestCase(
    name: 'my_suite',
    index: 0,
    params: {'resolution': '1080'},
    checklist: sampleChecklist,
  );

  group('ExecutionWrapper – success', () {
    test('returns ArtifactResult from generator', () async {
      const wrapper = ExecutionWrapper();
      final result = await wrapper.run(sampleCase, (tc) async {
        return ArtifactResult(path: '/tmp/output.mp4');
      });
      expect(result.path, '/tmp/output.mp4');
    });

    test('passes TestCase to generator correctly', () async {
      const wrapper = ExecutionWrapper();
      TestCase? received;
      await wrapper.run(sampleCase, (tc) async {
        received = tc;
        return ArtifactResult(path: '/tmp/out.mp4');
      });
      expect(received?.params['resolution'], '1080');
    });

    test('metadata is preserved in result', () async {
      const wrapper = ExecutionWrapper();
      final result = await wrapper.run(sampleCase, (tc) async {
        return ArtifactResult(
          path: '/tmp/a.mp4',
          metadata: {'fps': 30, 'codec': 'h264'},
        );
      });
      expect(result.metadata['fps'], 30);
    });
  });

  group('ExecutionWrapper – error handling', () {
    test('wraps unexpected exception in GeneratorException', () async {
      const wrapper = ExecutionWrapper();
      expect(
        () => wrapper.run(sampleCase, (tc) async {
          throw StateError('unexpected');
        }),
        throwsA(isA<GeneratorException>()),
      );
    });

    test('re-throws GeneratorException as-is', () async {
      const wrapper = ExecutionWrapper();
      const original = GeneratorException('deliberate error');
      expect(
        () => wrapper.run(sampleCase, (tc) async => throw original),
        throwsA(isA<GeneratorException>()),
      );
    });

    test('GeneratorException message is descriptive', () async {
      const wrapper = ExecutionWrapper();
      GeneratorException? caught;
      try {
        await wrapper.run(sampleCase, (tc) async {
          throw Exception('boom');
        });
      } on GeneratorException catch (e) {
        caught = e;
      }
      expect(caught?.message, contains('my_suite'));
    });
  });
}
