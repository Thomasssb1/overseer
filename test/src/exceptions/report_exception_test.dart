import 'package:overseer/overseer.dart';
import 'package:test/test.dart';

void main() {
  test('ReportException includes its message and is an OverseerException', () {
    const error = ReportException('Invalid report');
    expect(error, isA<OverseerException>());
    expect(error.message, 'Invalid report');
    expect(error.toString(), 'ReportException: Invalid report');
  });
}
