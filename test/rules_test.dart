import 'package:test/test.dart';
import 'package:test_hang_guard/test_hang_guard.dart';

List<Violation> scan(String source, HangRules rules) =>
    scanLines('fixture.dart', source.split('\n'), rules);

void main() {
  test('defaults are what the constructor falls back to', () {
    final rules = HangRules();
    expect(rules.teardownReceivers, defaultTeardownReceivers);
    expect(rules.teardownMethods, defaultTeardownMethods);
    expect(rules.asyncCalls, defaultAsyncCalls);
    expect(rules.asyncSymbols, isEmpty);
    expect(rules.testFunctions, defaultTestFunctions);
    expect(rules.ignoreMarker, defaultIgnoreMarker);
    expect(rules.teardownCall, isNotNull);
    expect(rules.realAsyncCall, isNotNull);
  });

  test('a supplied list replaces the default rather than extending it', () {
    final rules = HangRules(teardownReceivers: ['engine']);
    const fixture = '''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    await engine.stop();
    await audioPlayer.stop();
  });
});
''';
    final violations = scan(fixture, rules);
    expect(violations.map((v) => v.line), [3]);
  });

  test('an async symbol matches without call syntax', () {
    final rules = HangRules(asyncSymbols: ['DraftStore']);
    const fixture = '''
testWidgets('t', (tester) async {
  await DraftStore.instance.loadAll();
});
''';
    expect(scan(fixture, rules), hasLength(1));
  });

  test('an extra async call name is honoured alongside a narrowed list', () {
    final rules = HangRules(asyncCalls: ['loadFromDisk']);
    const fixture = '''
testWidgets('t', (tester) async {
  await loadFromDisk();
  await readAsString('x');
});
''';
    final violations = scan(fixture, rules);
    expect(violations.map((v) => v.line), [2]);
  });

  test('an empty list disables its rule', () {
    final rules = HangRules(teardownMethods: []);
    expect(rules.teardownCall, isNull);
    const fixture = '''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    await player.stop();
  });
});
''';
    expect(scan(fixture, rules), isEmpty);
  });

  test('emptying both async lists disables the real-async rule', () {
    final rules = HangRules(asyncCalls: [], asyncSymbols: []);
    expect(rules.realAsyncCall, isNull);
    const fixture = '''
testWidgets('t', (tester) async {
  await getTemporaryDirectory();
});
''';
    expect(scan(fixture, rules), isEmpty);
  });

  test('emptying the receivers disables the teardown rule', () {
    expect(HangRules(teardownReceivers: []).teardownCall, isNull);
  });

  test('a custom test function opens a test body', () {
    final rules = HangRules(testFunctions: ['testWidgetsWithHarness']);
    expect(rules.opensTestBody('testWidgetsWithHarness('), isTrue);
    expect(rules.opensTestBody('testWidgets('), isFalse);
    const fixture = '''
testWidgetsWithHarness('t', (tester) async {
  await getTemporaryDirectory();
});
''';
    expect(scan(fixture, rules), hasLength(1));
  });

  test('names with regex metacharacters are escaped, not interpreted', () {
    final rules = HangRules(asyncCalls: [r'load.all']);
    const fixture = '''
testWidgets('t', (tester) async {
  await loadXall();
});
''';
    expect(scan(fixture, rules), isEmpty);
  });
}
