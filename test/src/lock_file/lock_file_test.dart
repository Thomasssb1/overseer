import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package:overseer/overseer.dart';
import 'package:overseer/src/lock_file/lock_file.dart';

const _matrixPath = 'tests/my_test.matrix.yaml';

ChecklistResult _result(int index) => ChecklistResult(
      testCase: TestCase(
        name: 'suite',
        index: index,
        params: {'k': 'v$index'},
        checklist: const ['Item'],
      ),
      artifactPath: '/tmp/art_$index.mp4',
      verdicts: const {'Item': ChecklistVerdict.pass},
    );

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('overseer_lock_test_');
  });

  tearDown(() => tempDir.deleteSync(recursive: true));

  group('LockFile – create', () {
    test('starts with lastCompletedIndex = -1', () {
      final lock = LockFile.create(
        matrixPath: _matrixPath,
        directory: tempDir.path,
      );
      expect(lock.lastCompletedIndex, -1);
      expect(lock.results, isEmpty);
    });

    test('stores matrixPath correctly', () {
      final lock = LockFile.create(
        matrixPath: _matrixPath,
        directory: tempDir.path,
      );
      expect(lock.matrixPath, _matrixPath);
    });
  });

  group('LockFile – advance and persist', () {
    test('advance increments lastCompletedIndex', () {
      final lock = LockFile.create(
        matrixPath: _matrixPath,
        directory: tempDir.path,
      );
      lock.advance(0, _result(0));
      expect(lock.lastCompletedIndex, 0);
    });

    test('advance appends to results', () {
      final lock = LockFile.create(
        matrixPath: _matrixPath,
        directory: tempDir.path,
      );
      lock.advance(0, _result(0));
      lock.advance(1, _result(1));
      expect(lock.results, hasLength(2));
    });

    test('lock file is written to disk after advance', () {
      final lock = LockFile.create(
        matrixPath: _matrixPath,
        directory: tempDir.path,
      );
      lock.advance(0, _result(0));
      final file = File(p.join(tempDir.path, '.overseer.lock'));
      expect(file.existsSync(), isTrue);
    });
  });

  group('LockFile – tryResume', () {
    test('returns null when no lock file exists', () {
      final lock = LockFile.tryResume(
        matrixPath: _matrixPath,
        directory: tempDir.path,
      );
      expect(lock, isNull);
    });

    test('resumes with correct lastCompletedIndex', () {
      final original = LockFile.create(
        matrixPath: _matrixPath,
        directory: tempDir.path,
      );
      original.advance(2, _result(2));

      final resumed = LockFile.tryResume(
        matrixPath: _matrixPath,
        directory: tempDir.path,
      );
      expect(resumed, isNotNull);
      expect(resumed!.lastCompletedIndex, 2);
    });

    test('returns null when matrixPath does not match', () {
      final original = LockFile.create(
        matrixPath: _matrixPath,
        directory: tempDir.path,
      );
      original.advance(0, _result(0));

      final resumed = LockFile.tryResume(
        matrixPath: 'tests/other.matrix.yaml',
        directory: tempDir.path,
      );
      expect(resumed, isNull);
    });
  });

  group('LockFile – clear', () {
    test('clear() deletes the lock file', () {
      final lock = LockFile.create(
        matrixPath: _matrixPath,
        directory: tempDir.path,
      );
      lock.advance(0, _result(0));
      lock.clear();
      final file = File(p.join(tempDir.path, '.overseer.lock'));
      expect(file.existsSync(), isFalse);
    });

    test('clear() is a no-op if file does not exist', () {
      final lock = LockFile.create(
        matrixPath: _matrixPath,
        directory: tempDir.path,
      );
      // No advance() called, so no file written.
      expect(() => lock.clear(), returnsNormally);
    });
  });
}
