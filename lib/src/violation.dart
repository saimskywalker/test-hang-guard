/// One flagged line: a pattern that can wedge the test isolate.
class Violation {
  const Violation({
    required this.file,
    required this.line,
    required this.rule,
    required this.why,
    required this.source,
  });

  /// Rule id for an `await`ed teardown inside a `tester.runAsync` closure.
  static const teardownInRunAsync = 'awaited-teardown-in-run-async';

  /// Rule id for `await`ed real-event-loop work inside a widget test body.
  static const realAsyncInTestBody = 'awaited-real-async-in-test-body';

  /// Path of the scanned file, exactly as it was passed in.
  final String file;

  /// 1-based line number.
  final int line;

  /// Which rule matched — one of [teardownInRunAsync], [realAsyncInTestBody].
  final String rule;

  /// Why this deadlocks, written for whoever has to fix it.
  final String why;

  /// The original source line, uncensored, so the report shows real code.
  final String source;

  @override
  String toString() => '$file:$line  [$rule]';
}
