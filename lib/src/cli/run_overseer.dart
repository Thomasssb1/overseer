import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../verifier.dart';
import 'overseer_command_runner.dart';

/// Runs the non-interactive CLI, returning 0 for success or 1 for failure.
///
/// Verification JSON goes to [output]; the summary and diagnostics go to
/// [errorOutput]. Help goes to [output] without producing verification JSON.
Future<int> runOverseer(
  List<String> arguments, {
  required StringSink output,
  required StringSink errorOutput,
}) async {
  VerificationResult result;
  try {
    final verification = await OverseerCommandRunner(output).run(arguments);
    if (verification == null) return 0;
    result = verification;
  } on UsageException catch (error) {
    result = VerificationResult(errors: [error.message]);
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
