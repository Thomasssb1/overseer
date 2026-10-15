import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';

const _lockFileName = '.overseer.lock';

/// Persists session state to a `.overseer.lock` file so a run can be resumed.
///
/// The lock file is written to [directory] (defaults to the current working
/// directory) and is automatically deleted when [clear] is called at the end
/// of a successful run.
///
/// ### JSON schema
/// ```json
/// {
///   "matrixPath": "tests/my_test.matrix.yaml",
///   "lastCompletedIndex": 3,
///   "results": [ ...serialised ChecklistResult objects... ]
/// }
/// ```
class LockFile {
  LockFile._({
    required this.matrixPath,
    required String directory,
    required int lastCompletedIndex,
    required List<ChecklistResult> results,
    this.matrixSha256,
    this.commitSha,
  })  : _file = File(p.join(directory, _lockFileName)),
        _lastCompletedIndex = lastCompletedIndex,
        _results = results;

  final File _file;
  final String matrixPath;
  final String? matrixSha256;
  final String? commitSha;
  int _lastCompletedIndex;
  final List<ChecklistResult> _results;

  /// The index of the last fully completed case (-1 = none yet).
  int get lastCompletedIndex => _lastCompletedIndex;

  /// All results collected so far.
  List<ChecklistResult> get results => List.unmodifiable(_results);

  // ---------------------------------------------------------------------------
  // Factory constructors
  // ---------------------------------------------------------------------------

  /// Creates a brand-new lock file for [matrixPath] in [directory].
  factory LockFile.create({
    required String matrixPath,
    String? directory,
    String? matrixSha256,
    String? commitSha,
  }) {
    final dir = directory ?? Directory.current.path;
    return LockFile._(
      matrixPath: matrixPath,
      directory: dir,
      lastCompletedIndex: -1,
      results: [],
      matrixSha256: matrixSha256,
      commitSha: commitSha,
    );
  }

  /// Tries to load an existing lock file for [matrixPath] from [directory].
  ///
  /// Returns `null` if no lock file exists or the stored matrix path does not
  /// match [matrixPath] (which would mean a different run).
  /// When [matrixSha256] is supplied, both its contents and [commitSha] must
  /// match the stored provenance. Legacy locks without a fingerprint are ignored.
  static LockFile? tryResume({
    required String matrixPath,
    String? directory,
    String? matrixSha256,
    String? commitSha,
  }) {
    final dir = directory ?? Directory.current.path;
    final file = File(p.join(dir, _lockFileName));
    if (!file.existsSync()) return null;

    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (json['matrixPath'] != matrixPath) return null;
      // A fingerprinted run must never relabel legacy or stale reviews.
      if ((matrixSha256 != null && json['matrixSha256'] != matrixSha256) ||
          ((matrixSha256 != null || commitSha != null) &&
              json['commitSha'] != commitSha)) {
        return null;
      }
      final storedHash = json['matrixSha256'];
      final storedCommit = json['commitSha'];
      if ((storedHash != null && storedHash is! String) ||
          (storedCommit != null && storedCommit is! String)) {
        return null;
      }

      final rawResults = json['results'] as List<dynamic>? ?? [];
      final restoredResults = rawResults
          .map((e) => _resultFromJson(e as Map<String, dynamic>))
          .toList();

      return LockFile._(
        matrixPath: matrixPath,
        directory: dir,
        lastCompletedIndex: (json['lastCompletedIndex'] as num).toInt(),
        results: restoredResults,
        matrixSha256: storedHash,
        commitSha: storedCommit,
      );
    } catch (_) {
      // Corrupt lock file — ignore and start fresh.
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Mutation
  // ---------------------------------------------------------------------------

  /// Records that [index] has been completed and persists to disk.
  void advance(int index, ChecklistResult result) {
    final resultIndex = result.testCase.index;
    if (resultIndex != index) {
      throw ArgumentError(
        'Inconsistent test index: parameter index=$index, '
        'but result.testCase.index=$resultIndex',
      );
    }
    _lastCompletedIndex = resultIndex;
    _results.add(result);
    _persist();
  }

  /// Deletes the lock file — called at the end of a completed run.
  void clear() {
    if (_file.existsSync()) _file.deleteSync();
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _persist() {
    final data = {
      'matrixPath': matrixPath,
      'matrixSha256': matrixSha256,
      'commitSha': commitSha,
      'lastCompletedIndex': _lastCompletedIndex,
      'results': _results.map(_resultToJson).toList(),
    };

    // Ensure the parent directory exists before writing.
    final directory = _file.parent;
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    // Write to a temporary file and then atomically replace the lock file.
    final json = const JsonEncoder.withIndent('  ').convert(data);
    final tempFile = File('${_file.path}.tmp');
    tempFile.writeAsStringSync(json, flush: true);
    tempFile.renameSync(_file.path);
  }

  static Map<String, dynamic> _resultToJson(ChecklistResult r) => {
        'caseIndex': r.testCase.index,
        'caseName': r.testCase.name,
        'params': r.testCase.params,
        'checklist': r.testCase.checklist,
        'artifactPath': r.artifactPath,
        'retryCount': r.retryCount,
        'verdicts': r.verdicts.map(
          (k, v) => MapEntry(k, v.name),
        ),
      };

  static ChecklistResult _resultFromJson(Map<String, dynamic> json) {
    final rawVerdicts = json['verdicts'] as Map<String, dynamic>;
    final verdicts = rawVerdicts.map((k, v) => MapEntry(
          k,
          ChecklistVerdict.values.firstWhere((e) => e.name == v),
        ));

    final rawChecklist = json['checklist'];
    final List<String> checklist;
    if (rawChecklist == null) {
      // Older standalone LockFile clients did not persist the original list.
      checklist = verdicts.keys.toList();
    } else if (rawChecklist is List &&
        rawChecklist.every((item) => item is String)) {
      checklist = rawChecklist.cast<String>();
    } else {
      throw const FormatException('Lock checklist must be a list of strings.');
    }

    return ChecklistResult(
      testCase: TestCase(
        name: json['caseName'] as String,
        index: (json['caseIndex'] as num).toInt(),
        params: json['params'] as Map<String, dynamic>,
        checklist: checklist,
      ),
      artifactPath: json['artifactPath'] as String,
      verdicts: verdicts,
      retryCount: (json['retryCount'] as num).toInt(),
    );
  }
}
