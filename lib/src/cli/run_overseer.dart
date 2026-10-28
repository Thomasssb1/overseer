import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

import '../verifier.dart';

/// Runs the non-interactive CLI, returning 0 for success or 1 for failure.
///
/// Verification JSON goes to [output]; the summary and diagnostics go to
/// [errorOutput]. Help goes to [output] without producing verification JSON.
int runOverseer(
  List<String> arguments, {
  required StringSink output,
  required StringSink errorOutput,
}) {
  final verify = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show command help.')
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
  final parser = ArgParser()
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show help.')
    ..addCommand('verify', verify);
  final usage = 'Usage: overseer verify --report <report.json> '
      '--matrix <matrix.yaml> --expected-sha <sha> [policy flags]\n\n'
      '${verify.usage}\n\n'
      'Writes verification JSON to stdout and a readable summary to stderr.\n'
      'Exits 0 on success, 1 on invalid input or failed verification.';

  VerificationResult result;
  try {
    final options = parser.parse(arguments);
    final command = options.command;
    if (options.flag('help') || (command?.flag('help') ?? false)) {
      output.writeln(usage);
      return 0;
    }
    if (command == null || options.rest.isNotEmpty || command.rest.isNotEmpty) {
      throw const FormatException(
          'Expected the verify subcommand with options.');
    }
    for (final name in ['report', 'matrix', 'expected-sha']) {
      if (command.option(name)!.trim().isEmpty) {
        throw FormatException('Option --$name must not be blank.');
      }
    }
    final report =
        jsonDecode(File(command.option('report')!).readAsStringSync());
    result = verifyReport(
      report,
      matrixPath: command.option('matrix')!,
      expectedSha: command.option('expected-sha')!,
      allowFailures: command.flag('allow-failures'),
      allowSkips: command.flag('allow-skips'),
      allowErrors: command.flag('allow-errors'),
    );
  } on FormatException catch (error) {
    result = VerificationResult(errors: [error.message]);
  } on ArgumentError catch (error) {
    result = VerificationResult(errors: ['${error.message}']);
  } on FileSystemException catch (error) {
    result = VerificationResult(
        errors: ['Cannot read report ${error.path}: ${error.message}']);
  }
  output.writeln(jsonEncode(result.toJson()));
  errorOutput.writeln(result.summary);
  for (final error in result.errors) {
    errorOutput.writeln('  - $error');
  }
  return result.valid ? 0 : 1;
}
