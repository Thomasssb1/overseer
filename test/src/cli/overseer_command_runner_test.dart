import 'package:args/command_runner.dart';
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

  test('routes help verify to the registered verification command', () async {
    final output = StringBuffer();
    final runner = OverseerCommandRunner(output);

    expect(await runner.run(['help', 'verify']), isNull);
    expect(output.toString(), contains('Usage: overseer verify'));
    expect(output.toString(), contains('--report (mandatory)'));
    expect(output.toString(), contains('--allow-errors'));
    expect(output.toString(), contains('JSON to stdout'));
  });

  test('dispatches verify and enforces its required options', () async {
    final runner = OverseerCommandRunner(StringBuffer());

    await expectLater(
        runner.run(['verify']),
        throwsA(isA<ArgumentError>().having((error) => error.message, 'message',
            'Option report is mandatory.')));
  });

  test('rejects unknown commands through the command library', () async {
    final runner = OverseerCommandRunner(StringBuffer());

    await expectLater(
        runner.run(['unknown']),
        throwsA(isA<UsageException>().having((error) => error.message,
            'message', contains('Could not find a command'))));
  });
}
