import 'dart:convert';
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

    test('resumes with correct lastCompletedIndex and deserializes results',
        () {
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
      expect(resumed.results, hasLength(1));

      final restoredResult = resumed.results.first;
      expect(restoredResult.testCase.index, 2);
      expect(restoredResult.artifactPath, '/tmp/art_2.mp4');
      expect(restoredResult.verdicts['Item'], ChecklistVerdict.pass);
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

    test('returns null when the lock file contains invalid JSON', () {
      final file = File(p.join(tempDir.path, '.overseer.lock'));
      file.writeAsStringSync('{ intentionally corrupted json');

      final resumed = LockFile.tryResume(
        matrixPath: _matrixPath,
        directory: tempDir.path,
      );
      expect(resumed, isNull);
    });

    test('returns null when the lock file json is structurally invalid', () {
      final file = File(p.join(tempDir.path, '.overseer.lock'));
      // Missing lastCompletedIndex but holding the right matrixPath
      file.writeAsStringSync('{"matrixPath": "$_matrixPath"}');

      final resumed = LockFile.tryResume(
        matrixPath: _matrixPath,
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

  group('LockFile provenance', () {
    final hash = 'a' * 64;
    final commit = 'b' * 40;

    test('preserves the original checklist, including repeated items', () {
      final original = LockFile.create(
          matrixPath: _matrixPath,
          directory: tempDir.path,
          matrixSha256: hash,
          commitSha: commit);
      original.advance(
          0,
          ChecklistResult(
              testCase: TestCase(
                  name: 'suite', index: 0, params: {}, checklist: ['A', 'A']),
              artifactPath: 'artifact',
              verdicts: {'A': ChecklistVerdict.pass}));
      final resumed = LockFile.tryResume(
          matrixPath: _matrixPath,
          directory: tempDir.path,
          matrixSha256: hash,
          commitSha: commit);
      expect(resumed!.results.single.testCase.checklist, ['A', 'A']);
    });

    test('legacy results restore checklist items from verdicts', () {
      final original =
          LockFile.create(matrixPath: _matrixPath, directory: tempDir.path);
      original.advance(0, _result(0));
      final file = File(p.join(tempDir.path, '.overseer.lock'));
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      data['results'][0].remove('checklist');
      file.writeAsStringSync(jsonEncode(data));
      final resumed =
          LockFile.tryResume(matrixPath: _matrixPath, directory: tempDir.path);
      expect(resumed!.results.single.testCase.checklist, ['Item']);
    });

    test('invalid persisted checklist shapes are ignored safely', () {
      final original =
          LockFile.create(matrixPath: _matrixPath, directory: tempDir.path);
      original.advance(0, _result(0));
      final file = File(p.join(tempDir.path, '.overseer.lock'));
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final invalid in <dynamic>[
        {'item': 'Item'},
        [42]
      ]) {
        data['results'][0]['checklist'] = invalid;
        file.writeAsStringSync(jsonEncode(data));
        expect(
            LockFile.tryResume(
                matrixPath: _matrixPath, directory: tempDir.path),
            isNull);
      }
    });

    test('persists and restores matching matrix and commit fingerprints', () {
      final original = LockFile.create(
          matrixPath: _matrixPath,
          directory: tempDir.path,
          matrixSha256: hash,
          commitSha: commit);
      original.advance(0, _result(0));
      final resumed = LockFile.tryResume(
          matrixPath: _matrixPath,
          directory: tempDir.path,
          matrixSha256: hash,
          commitSha: commit);
      expect(resumed, isNotNull);
      expect(resumed!.matrixSha256, hash);
      expect(resumed.commitSha, commit);
      expect(resumed.results.single.testCase.index, 0);
      expect(
          LockFile.tryResume(
              matrixPath: _matrixPath,
              directory: tempDir.path,
              commitSha: commit),
          isNotNull);
      expect(
          LockFile.tryResume(
              matrixPath: _matrixPath,
              directory: tempDir.path,
              commitSha: 'c' * 40),
          isNull);
    });

    test('a known revision cannot be resumed with unknown provenance', () {
      final original = LockFile.create(
          matrixPath: _matrixPath,
          directory: tempDir.path,
          matrixSha256: hash,
          commitSha: commit);
      original.advance(0, _result(0));
      expect(
          LockFile.tryResume(
              matrixPath: _matrixPath,
              directory: tempDir.path,
              matrixSha256: hash),
          isNull);
    });

    test('an unknown revision cannot be relabeled with a known revision', () {
      final original = LockFile.create(
          matrixPath: _matrixPath, directory: tempDir.path, matrixSha256: hash);
      original.advance(0, _result(0));
      expect(
          LockFile.tryResume(
              matrixPath: _matrixPath,
              directory: tempDir.path,
              matrixSha256: hash),
          isNotNull);
      expect(
          LockFile.tryResume(
              matrixPath: _matrixPath,
              directory: tempDir.path,
              matrixSha256: hash,
              commitSha: commit),
          isNull);
    });

    test('ignores structurally invalid provenance without raw type errors', () {
      final original = LockFile.create(
          matrixPath: _matrixPath,
          directory: tempDir.path,
          matrixSha256: hash,
          commitSha: commit);
      original.advance(0, _result(0));
      final file = File(p.join(tempDir.path, '.overseer.lock'));
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      for (final field in ['matrixSha256', 'commitSha']) {
        file.writeAsStringSync(jsonEncode({
          ...data,
          field: ['invalid']
        }));
        expect(
            LockFile.tryResume(
                matrixPath: _matrixPath, directory: tempDir.path),
            isNull);
      }
    });
  });
}
