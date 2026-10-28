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
    test('passes the original case and returns the artifact with all metadata',
        () async {
      const wrapper = ExecutionWrapper();
      final artifact = ArtifactResult(
          path: '/tmp/output.mp4', metadata: {'fps': 30, 'codec': 'h264'});
      TestCase? received;
      final result = await wrapper.run(sampleCase, (tc) async {
        received = tc;
        return artifact;
      });
      expect(received, same(sampleCase));
      expect(result, same(artifact));
      expect(result.path, '/tmp/output.mp4');
      expect(result.metadata, {'fps': 30, 'codec': 'h264'});
    });
  });

  group('ExecutionWrapper – error handling', () {
    test('wraps unexpected errors with the original cause and case label',
        () async {
      const wrapper = ExecutionWrapper();
      final cause = StateError('unexpected');
      await expectLater(
        () => wrapper.run(sampleCase, (tc) async {
          throw cause;
        }),
        throwsA(isA<GeneratorException>()
            .having((error) => error.cause, 'cause', same(cause))
            .having((error) => error.message, 'message',
                contains(sampleCase.label))),
      );
    });

    test('re-throws GeneratorException as-is', () async {
      const wrapper = ExecutionWrapper();
      const original = GeneratorException('deliberate error');
      await expectLater(
        () => wrapper.run(sampleCase, (tc) async => throw original),
        throwsA(same(original)),
      );
    });
  });
}
