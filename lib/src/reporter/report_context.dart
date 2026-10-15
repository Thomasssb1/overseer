import 'dart:io';

import 'package:crypto/crypto.dart';

import '../exceptions.dart';
import '../models.dart';
import 'report_schema.dart';

final _matrixHashSchema =
    reportSchemaValidator.properties['matrix']!.properties['sha256']!;
final _commitShaSchema = reportSchemaValidator.properties['commit_sha']!;

/// The matrix and source revision captured before generation starts.
class ReportContext {
  ReportContext({
    required this.matrixPath,
    required this.matrixSha256,
    required List<TestCase> cases,
    this.commitSha,
  }) : cases = List.unmodifiable([
          for (final testCase in cases)
            TestCase(
              name: testCase.name,
              index: testCase.index,
              params: Map.unmodifiable(testCase.params),
              checklist: List.unmodifiable(testCase.checklist),
            ),
        ]) {
    if (!_matrixHashSchema.validate(matrixSha256).isValid) {
      throw const ReportException(
          'Matrix SHA-256 must be 64 lowercase hex digits.');
    }
    if (!_commitShaSchema.validate(commitSha).isValid) {
      throw const ReportException('Commit SHA must be a full Git object ID.');
    }
    for (var i = 0; i < cases.length; i++) {
      if (cases[i].index != i) {
        throw const ReportException(
            'Expected cases must have consecutive zero-based indices.');
      }
      if (cases[i].checklist.isEmpty) {
        throw const ReportException(
            'Expected cases must have a non-empty checklist.');
      }
      for (final value in cases[i].params.values) {
        final isScalar =
            value == null || value is String || value is bool || value is num;
        if (!isScalar || (value is num && !value.isFinite)) {
          throw const ReportException(
              'Report parameters must be finite JSON scalar values.');
        }
      }
    }
  }

  /// Captures the raw file's SHA-256 and resolves the source revision.
  ///
  /// An explicit [commitSha] takes precedence over `GITHUB_SHA`, then Git HEAD
  /// in the matrix's directory. Unavailable revision information remains null.
  /// [environment] overrides the process environment for embedding and testing.
  factory ReportContext.capture({
    required String matrixPath,
    required List<TestCase> cases,
    String? commitSha,
    Map<String, String>? environment,
  }) {
    final file = File(matrixPath);
    final String hash;
    try {
      hash = sha256.convert(file.readAsBytesSync()).toString();
    } on FileSystemException catch (e) {
      throw ReportException('Cannot fingerprint matrix: ${e.message}');
    }
    var revision = commitSha;
    if (revision == null) {
      final githubSha = (environment ?? Platform.environment)['GITHUB_SHA'];
      if (githubSha != null && githubSha.trim().isNotEmpty) {
        revision = githubSha.trim();
      } else {
        try {
          final result = Process.runSync('git', [
            '-C',
            file.absolute.parent.path,
            'rev-parse',
            'HEAD',
          ]);
          if (result.exitCode == 0) revision = '${result.stdout}'.trim();
        } on ProcessException {
          // Git is optional; CI can require a non-null commit_sha.
        }
      }
    }
    return ReportContext(
      matrixPath: matrixPath,
      matrixSha256: hash,
      cases: cases,
      commitSha: revision,
    );
  }

  final String matrixPath;
  final String matrixSha256;
  final String? commitSha;
  final List<TestCase> cases;
}
