import 'dart:io';

import 'package:overseer/src/cli/run_overseer.dart';

Future<void> main(List<String> arguments) async {
  exitCode = await runOverseer(arguments, output: stdout, errorOutput: stderr);
}
