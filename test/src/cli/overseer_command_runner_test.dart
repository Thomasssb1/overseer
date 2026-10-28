import 'package:overseer/src/cli/overseer_command_runner.dart';
import 'package:test/test.dart';

void main() {
  test('routes generated global help to the provided sink', () async {
    final output = StringBuffer();
    final runner = OverseerCommandRunner(output);

    expect(await runner.run(['--help']), isNull);
    expect(output.toString(), contains('Usage: overseer <command>'));
    expect(output.toString(), contains('verify'));
    expect(output.toString(), contains('Verify a JSON report'));
  });
}
