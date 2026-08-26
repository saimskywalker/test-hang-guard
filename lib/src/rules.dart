/// Receiver name fragments that identify a media player or audio handler.
///
/// Matched on the NAME of the receiver, not its static type — resolving the
/// type would mean running the analyzer over the whole package, which is
/// several orders of magnitude slower than the hang it prevents. A false
/// positive costs one ignore marker; a missed hang costs a whole CI run.
const defaultTeardownReceivers = <String>[
  'audioHandler',
  'audioPlayer',
  'player',
  'handler',
];

/// The calls that count as a teardown.
///
/// Exactly teardown, and no more. `pause()` is deliberately absent: it is not
/// teardown and has not been observed to deadlock. A gate that flags things
/// nobody has proven dangerous teaches people to distrust it, and a distrusted
/// gate gets switched off.
const defaultTeardownMethods = <String>['stop', 'dispose'];

/// Calls whose work runs on the real event loop: real disk reads and writes,
/// and the `path_provider` directory lookups.
///
/// These are the I/O METHODS, deliberately — not `File(...)` or
/// `Directory(...)`, which perform no I/O at all and merely build a handle.
/// Matching the constructor flags `await tester.pumpWidget(Image.file(File(p)))`,
/// which is safe and something anyone might write.
const defaultAsyncCalls = <String>[
  'getApplicationDocumentsDirectory',
  'getTemporaryDirectory',
  'getExternalStorageDirectory',
  'readAsString',
  'readAsBytes',
  'readAsLines',
  'writeAsString',
  'writeAsBytes',
];

/// Test-declaring functions whose body runs under the fake clock.
const defaultTestFunctions = <String>['testWidgets'];

/// Default text that suppresses a finding on the line carrying it.
const defaultIgnoreMarker = 'no-hang-check';

/// Exit code: nothing found.
const exitClean = 0;

/// Exit code: at least one violation.
const exitViolations = 1;

/// Exit code: bad arguments, or a path that does not exist.
const exitUsage = 2;

/// The configured pattern set a scan runs with.
///
/// Every list defaults to the values above; passing one replaces that list
/// rather than adding to it, so a project can narrow a rule as easily as it
/// can widen one. Passing an empty list disables the rule that uses it.
class HangRules {
  HangRules({
    List<String>? teardownReceivers,
    List<String>? teardownMethods,
    List<String>? asyncCalls,
    List<String>? asyncSymbols,
    List<String>? testFunctions,
    this.ignoreMarker = defaultIgnoreMarker,
  })  : teardownReceivers = teardownReceivers ?? defaultTeardownReceivers,
        teardownMethods = teardownMethods ?? defaultTeardownMethods,
        asyncCalls = asyncCalls ?? defaultAsyncCalls,
        asyncSymbols = asyncSymbols ?? const <String>[],
        testFunctions = testFunctions ?? defaultTestFunctions;

  /// Name fragments of receivers whose teardown may not be awaited.
  final List<String> teardownReceivers;

  /// Method names that count as a teardown.
  final List<String> teardownMethods;

  /// Names that must be followed by `(` to count as real-event-loop work.
  final List<String> asyncCalls;

  /// Bare identifiers that count wherever they appear, no call syntax needed.
  ///
  /// For an on-disk store reached through a singleton — `Store.instance.load()`
  /// — the method name varies but the type name does not, so match the type.
  final List<String> asyncSymbols;

  /// Names of the functions that declare a widget test.
  final List<String> testFunctions;

  /// A line containing this text is skipped.
  final String ignoreMarker;

  /// Matches an awaited player teardown, or null when the rule is disabled.
  late final RegExp? teardownCall = _buildTeardown();

  /// Matches work the fake clock never drives, or null when disabled.
  late final RegExp? realAsyncCall = _buildRealAsync();

  RegExp? _buildTeardown() {
    if (teardownReceivers.isEmpty || teardownMethods.isEmpty) return null;
    final receivers = teardownReceivers.map(RegExp.escape).join('|');
    final methods = teardownMethods.map(RegExp.escape).join('|');
    return RegExp(
      r'\b\w*(' + receivers + r')\w*\s*\.\s*(' + methods + r')\s*\(',
      caseSensitive: false,
    );
  }

  RegExp? _buildRealAsync() {
    final parts = <String>[
      if (asyncSymbols.isNotEmpty)
        r'\b(' + asyncSymbols.map(RegExp.escape).join('|') + r')\b',
      if (asyncCalls.isNotEmpty)
        r'\b(' + asyncCalls.map(RegExp.escape).join('|') + r')\s*\(',
    ];
    if (parts.isEmpty) return null;
    return RegExp(parts.join('|'));
  }

  /// Whether [code] opens the body of a widget test.
  bool opensTestBody(String code) =>
      testFunctions.any((name) => code.contains('$name('));
}
