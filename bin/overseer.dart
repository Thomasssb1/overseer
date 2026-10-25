import 'dart:io';

import 'package:overseer/src/cli/run_overseer.dart';

void main(List<String> arguments) {
  exitCode = runOverseer(arguments, output: stdout, errorOutput: stderr);
}
