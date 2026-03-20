import 'package:overseer/src/models/test_case.dart';
import 'package:test/test.dart';

void main() {
  group('TestCase', () {
    test('produces correct label with single parameter', () {
      const t = TestCase(
        name: 'Login Flow',
        index: 0,
        params: {'browser': 'chrome'},
        checklist: [],
      );
      expect(t.label, 'Login Flow #1 [browser=chrome]');
    });

    test('produces correct label with multiple parameters', () {
      const t = TestCase(
        name: 'Login Flow',
        index: 1,
        params: {'browser': 'firefox', 'os': 'windows'},
        checklist: [],
      );
      expect(t.label, 'Login Flow #2 [browser=firefox, os=windows]');
    });

    test('toString returns proper format', () {
      const t = TestCase(
        name: 'Foo',
        index: 2,
        params: {'x': 1},
        checklist: [],
      );
      expect(t.toString(), 'TestCase(Foo #3 [x=1])');
    });
  });
}
