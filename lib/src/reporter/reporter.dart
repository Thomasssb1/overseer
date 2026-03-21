import 'dart:io';

import 'package:path/path.dart' as p;

import '../models.dart';

/// Compiles [ChecklistResult]s into a Markdown test report.
///
/// Call [record] for each completed case, then [writeReport] at the end of
/// the session to flush the report to disk.
///
/// The report is written to `reports/overseer_report_<timestamp>.md` relative
/// to [outputDir] (defaults to the current working directory).
class Reporter {
  Reporter({String? outputDir})
      : _outputDir = outputDir ?? Directory.current.path;

  final String _outputDir;
  final List<ChecklistResult> _results = [];

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Adds [result] to the in-memory accumulator.
  void record(ChecklistResult result) => _results.add(result);

  /// Returns the total number of recorded results.
  int get count => _results.length;

  /// Writes the final Markdown report and returns the path to the file.
  Future<String> writeReport() async {
    final timestamp = _timestamp();
    final dir = Directory(p.join(_outputDir, 'reports'));
    await dir.create(recursive: true);

    final file = File(p.join(dir.path, 'overseer_report_$timestamp.md'));
    await file.writeAsString(_buildMarkdown(timestamp));
    return file.path;
  }

  // ---------------------------------------------------------------------------
  // Private
  // ---------------------------------------------------------------------------

  String _buildMarkdown(String timestamp) {
    final passed = _results.where((r) => r.passed && !r.fullySkipped).length;
    final failed = _results.where((r) => !r.passed).length;
    final skipped = _results.where((r) => r.fullySkipped).length;
    final total = _results.length;

    final buf = StringBuffer();

    // Header
    buf.writeln('# Overseer Test Report');
    buf.writeln();
    buf.writeln('**Generated:** $timestamp');
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
      final badge = result.fullySkipped
          ? '⏭ SKIPPED'
          : result.passed
              ? '✅ PASS'
              : '❌ FAIL';

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
        '${_pad(now.second)}';
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');
}
