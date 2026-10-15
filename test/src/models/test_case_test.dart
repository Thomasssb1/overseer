import 'package:overseer/src/models/test_case.dart';
import 'package:test/test.dart';

void main() {
  group('TestCase', () {
    test('matrix version is optional for existing callers', () {
      const testCase =
          TestCase(name: 'suite', index: 0, params: {}, checklist: []);
      expect(testCase.matrixVersion, isNull);
    });

    test('version appears in labels and string output', () {
      const testCase = TestCase(
        name: 'suite',
        matrixVersion: 'review-2',
        index: 0,
        params: {'color': 'red'},
        checklist: [],
      );
      expect(testCase.matrixVersion, 'review-2');
      expect(testCase.label, 'suite (version review-2) #1 [color=red]');
      expect(testCase.toString(),
          'TestCase(suite (version review-2) #1 [color=red])');
    });

    test('version appears in labels without parameters', () {
      const testCase = TestCase(
        name: 'suite',
        matrixVersion: '1.0.0',
        index: 1,
        params: {},
        checklist: [],
      );
      expect(testCase.label, 'suite (version 1.0.0) #2');
    });

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

    test('produces correct label with no parameters', () {
      const t = TestCase(
        name: 'Login Flow',
        index: 2,
        params: {},
        checklist: [],
      );
      expect(t.label, 'Login Flow #3');
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
