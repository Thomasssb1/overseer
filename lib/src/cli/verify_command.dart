import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../verifier.dart';

/// Verifies a report using the command library's option and help handling.
class VerifyCommand extends Command<VerificationResult> {
  VerifyCommand(StringSink output) : _output = output {
    argParser
      ..addOption('report', mandatory: true, help: 'Path to the JSON report.')
      ..addOption('matrix',
          mandatory: true, help: 'Path to the matrix YAML file.')
      ..addOption('expected-sha',
          mandatory: true, help: 'Full expected Git commit SHA.')
      ..addFlag('allow-failures',
          negatable: false, help: 'Allow failed checklist verdicts.')
      ..addFlag('allow-skips',
          negatable: false,
          help: 'Allow skipped verdicts in fully reviewed cases.')
      ..addFlag('allow-errors',
          negatable: false,
          help: 'Allow terminal generator errors; pending reviews still fail.');
  }

  final StringSink _output;

  @override
  String get name => 'verify';

  @override
  String get description => 'Verify a JSON report against a matrix and commit.';

  @override
  bool get takesArguments => false;

  @override
  String get usageFooter =>
      'Writes verification JSON to stdout and a readable summary to stderr.\n'
      'Exits 0 on success, 1 on invalid input or failed verification.';

  @override
  void printUsage() => _output.writeln(usage);

  @override
  VerificationResult run() {
    final options = argResults!;
    for (final name in ['report', 'matrix', 'expected-sha']) {
      if (options.option(name)!.trim().isEmpty) {
        throw FormatException('Option --$name must not be blank.');
      }
    }
    final report =
        jsonDecode(File(options.option('report')!).readAsStringSync());
    return verifyReport(
      report,
      matrixPath: options.option('matrix')!,
      expectedSha: options.option('expected-sha')!,
      allowFailures: options.flag('allow-failures'),
      allowSkips: options.flag('allow-skips'),
      allowErrors: options.flag('allow-errors'),
    );
  }
}
