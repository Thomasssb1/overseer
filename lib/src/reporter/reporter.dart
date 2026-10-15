import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../exceptions.dart';
import '../models.dart';
import 'report_context.dart';
import 'report_format.dart';

/// Compiles reviews into Markdown (the default) or versioned JSON reports.
///
/// Call [record] for each completed case, then [writeReport] at the end of
/// the session to flush the report to disk.
///
/// The report is written to `reports/overseer_report_<timestamp>.md` or `.json` relative
/// to [outputDir] (defaults to the current working directory).
class Reporter {
  Reporter(
      {String? outputDir, this.format = ReportFormat.markdown, this.context})
      : _outputDir = outputDir ?? Directory.current.path {
    if (format == ReportFormat.json && context == null) {
      throw const ReportException('JSON reports require a ReportContext.');
    }
  }

  static const schemaVersion = 2;
  static const schemaUrl =
      'https://raw.githubusercontent.com/Thomasssb1/overseer/main/schema/report.v2.json';

  final ReportFormat format;
  final ReportContext? context;

  final String _outputDir;
  final List<ChecklistResult> _results = [];
  final Set<int> _incomplete = {};
  final Map<int, ({String message, int retryCount})> _errors = {};

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Adds [result] to the in-memory accumulator.
  void record(ChecklistResult result, {bool completed = true}) {
    _validateCase(result.testCase);
    if (result.retryCount < 0 ||
        result.verdicts.keys
            .any((item) => !result.testCase.checklist.contains(item))) {
      throw const ReportException(
          'Invalid retry count or unknown checklist verdict.');
    }
    _results.add(result);
    if (!completed) _incomplete.add(result.testCase.index);
  }

  /// Records a terminal generator error without advancing resumable progress.
  void recordError(TestCase testCase, Object error, {int retryCount = 0}) {
    _validateCase(testCase);
    if (retryCount < 0) {
      throw const ReportException('Retry count must not be negative.');
    }
    _errors[testCase.index] =
        (message: error.toString(), retryCount: retryCount);
  }

  /// Returns the total number of recorded results.
  int get count => _results.length;

  /// Writes the selected report format and returns the path to the file.
  Future<String> writeReport() async {
    final timestamp = _timestamp();
    final String content;
    if (format == ReportFormat.json) {
      content = '${const JsonEncoder.withIndent('  ').convert(_buildJson())}\n';
    } else {
      content = _buildMarkdown(timestamp);
    }
    final dir = Directory(p.join(_outputDir, 'reports'));
    await dir.create(recursive: true);

    final extension = format == ReportFormat.json ? 'json' : 'md';
    final file =
        File(p.join(dir.path, 'overseer_report_$timestamp.$extension'));
    await file.writeAsString(content);
    return file.path;
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  void _validateCase(TestCase testCase) {
    final expected = context?.cases;
    if (expected == null) return;
    final index = testCase.index;
    if (index < 0 || index >= expected.length) {
      throw ReportException(
          'Case index $index is outside the expected matrix.');
    }
    final original = expected[index];
    if (original.name != testCase.name ||
        original.matrixVersion != testCase.matrixVersion ||
        original.params.length != testCase.params.length ||
        original.params.entries.any((e) =>
            !testCase.params.containsKey(e.key) ||
            testCase.params[e.key] != e.value) ||
        original.checklist.length != testCase.checklist.length ||
        original.checklist
            .asMap()
            .entries
            .any((e) => testCase.checklist[e.key] != e.value)) {
      throw ReportException('Case $index does not match the expected matrix.');
    }
    if (_results.any((r) => r.testCase.index == index) ||
        _errors.containsKey(index)) {
      throw ReportException('Case $index already has a recorded outcome.');
    }
  }

  Map<String, dynamic> _buildJson() {
    final reportContext = context!;
    final results = {
      for (final result in _results) result.testCase.index: result
    };
    final cases = [
      for (final testCase in reportContext.cases)
        _jsonCase(testCase, results[testCase.index]),
    ];
    final summary = {
      for (final status in ['passed', 'failed', 'skipped', 'error', 'pending'])
        status: cases.where((c) => c['status'] == status).length,
    };
    final completed = cases.where((c) => c['completed'] == true).length;
    return {
      r'$schema': schemaUrl,
      'schema_version': schemaVersion,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'commit_sha': reportContext.commitSha,
      'matrix': {
        'path': reportContext.matrixPath,
        'sha256': reportContext.matrixSha256,
        if (reportContext.matrixVersion != null)
          'version': reportContext.matrixVersion,
      },
      'expected_case_count': cases.length,
      'completed_case_count': completed,
      'complete': completed == cases.length,
      'successful': cases.isNotEmpty &&
          completed == cases.length &&
          summary['passed'] == cases.length,
      'summary': summary,
      'cases': cases,
    };
  }

  Map<String, dynamic> _jsonCase(TestCase testCase, ChecklistResult? result) {
    final error = _errors[testCase.index];
    final completed = result != null &&
        !_incomplete.contains(testCase.index) &&
        testCase.checklist.every(result.verdicts.containsKey);
    final String status;
    if (error != null) {
      status = 'error';
    } else if (result == null) {
      status = 'pending';
    } else {
      status = _reviewStatus(result);
    }
    return {
      'index': testCase.index,
      'name': testCase.name,
      'params': testCase.params,
      'artifact_path': result?.artifactPath,
      'retry_count': result?.retryCount ?? error?.retryCount ?? 0,
      'completed': completed,
      'status': status,
      'error': error?.message,
      'checklist': [
        for (final item in testCase.checklist)
          {'item': item, 'verdict': result?.verdicts[item]?.name},
      ],
    };
  }

  String _reviewStatus(ChecklistResult result) {
    if (!result.passed) return 'failed';
    if (_incomplete.contains(result.testCase.index) ||
        result.testCase.checklist.isEmpty ||
        result.testCase.checklist
            .any((item) => result.verdicts[item] != ChecklistVerdict.pass)) {
      return 'skipped';
    }
    return 'passed';
  }

  String _buildMarkdown(String timestamp) {
    final statuses = _results.map(_reviewStatus).toList();
    final passed = statuses.where((status) => status == 'passed').length;
    final failed = statuses.where((status) => status == 'failed').length;
    final skipped = statuses.where((status) => status == 'skipped').length;
    final total = _results.length;

    final buf = StringBuffer();

    // Header
    buf.writeln('# Overseer Test Report');
    buf.writeln();
    buf.writeln('**Generated:** $timestamp');
    if (context?.matrixVersion != null) {
      buf.writeln('**Matrix version:** ${context!.matrixVersion}');
    }
    buf.writeln();

    // Summary table
    buf.writeln('## Summary');
    buf.writeln();
    buf.writeln('| Total | ✅ Passed | ❌ Failed | ⏭ Skipped |');
    buf.writeln('|-------|----------|----------|----------|');
    buf.writeln('| $total | $passed | $failed | $skipped |');
    buf.writeln();

    // Per-case sections
    buf.writeln('## Cases');
    buf.writeln();

    for (final result in _results) {
      final badge = switch (_reviewStatus(result)) {
        'passed' => '✅ PASS',
        'failed' => '❌ FAIL',
        _ => '⏭ SKIPPED',
      };

      buf.writeln('### [$badge] ${result.testCase.label}');
      buf.writeln();
      buf.writeln('**Artifact:** `${result.artifactPath}`');
      if (result.retryCount > 0) {
        buf.writeln('**Retries:** ${result.retryCount}');
      }
      buf.writeln();

      // Params table
      if (result.testCase.params.isNotEmpty) {
        buf.writeln('**Parameters:**');
        buf.writeln();
        buf.writeln('| Parameter | Value |');
        buf.writeln('|-----------|-------|');
        for (final e in result.testCase.params.entries) {
          buf.writeln('| ${e.key} | ${e.value} |');
        }
        buf.writeln();
      }

      // Checklist table
      buf.writeln('**Checklist:**');
      buf.writeln();
      buf.writeln('| Item | Result |');
      buf.writeln('|------|--------|');
      for (final e in result.verdicts.entries) {
        final icon = switch (e.value) {
          ChecklistVerdict.pass => '✅',
          ChecklistVerdict.fail => '❌',
          ChecklistVerdict.skipped => '⏭',
        };
        buf.writeln('| ${e.key} | $icon |');
      }
      buf.writeln();
      buf.writeln('---');
      buf.writeln();
    }

    return buf.toString();
  }

  static String _timestamp() {
    final now = DateTime.now();
    return '${now.year}'
        '${_pad(now.month)}'
        '${_pad(now.day)}'
        '_'
        '${_pad(now.hour)}'
        '${_pad(now.minute)}'
        '${_pad(now.second)}'
        '_'
        '${now.microsecondsSinceEpoch}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
