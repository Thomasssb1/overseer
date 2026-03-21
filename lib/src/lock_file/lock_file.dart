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
  })  : _file = File(p.join(directory, _lockFileName)),
        _lastCompletedIndex = lastCompletedIndex,
        _results = results;

  final File _file;
  final String matrixPath;
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
  }) {
    final dir = directory ?? Directory.current.path;
    return LockFile._(
      matrixPath: matrixPath,
      directory: dir,
      lastCompletedIndex: -1,
      results: [],
    );
  }

  /// Tries to load an existing lock file for [matrixPath] from [directory].
  ///
  /// Returns `null` if no lock file exists or the stored matrix path does not
  /// match [matrixPath] (which would mean a different run).
  static LockFile? tryResume({
    required String matrixPath,
    String? directory,
  }) {
    final dir = directory ?? Directory.current.path;
    final file = File(p.join(dir, _lockFileName));
    if (!file.existsSync()) return null;

    try {
      final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      if (json['matrixPath'] != matrixPath) return null;

      final rawResults = json['results'] as List<dynamic>? ?? [];
      final restoredResults = rawResults
          .map((e) => _resultFromJson(e as Map<String, dynamic>))
          .toList();

      return LockFile._(
        matrixPath: matrixPath,
        directory: dir,
        lastCompletedIndex: (json['lastCompletedIndex'] as num).toInt(),
        results: restoredResults,
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
    _lastCompletedIndex = index;
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
      'lastCompletedIndex': _lastCompletedIndex,
      'results': _results.map(_resultToJson).toList(),
    };
    _file.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(data),
    );
  }

  static Map<String, dynamic> _resultToJson(ChecklistResult r) => {
        'caseIndex': r.testCase.index,
        'caseName': r.testCase.name,
        'params': r.testCase.params,
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

    return ChecklistResult(
      testCase: TestCase(
        name: json['caseName'] as String,
        index: (json['caseIndex'] as num).toInt(),
        params: json['params'] as Map<String, dynamic>,
        checklist: verdicts.keys.toList(),
      ),
      artifactPath: json['artifactPath'] as String,
      verdicts: verdicts,
      retryCount: (json['retryCount'] as num).toInt(),
    );
  }
}
