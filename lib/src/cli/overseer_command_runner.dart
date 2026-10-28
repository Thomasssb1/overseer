import 'package:args/command_runner.dart';

import '../verifier.dart';
import 'verify_command.dart';

/// Registers commands and routes the library's generated help to the CLI sink.
class OverseerCommandRunner extends CommandRunner<VerificationResult> {
  OverseerCommandRunner(StringSink output)
      : _output = output,
        super('overseer', 'Validate review reports for CI.') {
    addCommand(VerifyCommand(output));
  }

  final StringSink _output;

  @override
  void printUsage() => _output.writeln(usage);
}
