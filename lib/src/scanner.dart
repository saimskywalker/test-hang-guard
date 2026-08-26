import 'rules.dart';
import 'violation.dart';

/// Scans one file's [lines] and returns every hang pattern found in it.
///
/// [path] is only ever echoed back in the [Violation]s, so this works on source
/// held in memory — a fixture string, an editor buffer — as readily as on a
/// file read off disk.
///
/// This is a brace-depth scan rather than a per-line match, because both rules
/// are block-scoped facts: whether a given `await` sits inside a
/// `tester.runAsync(...)` closure, and whether it sits inside a widget test
/// body at all. No line regex can see either.
List<Violation> scanLines(String path, List<String> lines, HangRules rules) {
  final out = <Violation>[];

  // A triple-quoted string can hold an entire Dart program — this package's own
  // tests embed the exact hang patterns that way, as fixtures. Blank those
  // regions out FIRST, or the scanner reports its own fixtures as real
  // violations and no-one can add a regression test for a rule without
  // tripping the rule.
  final source = blankBlockStrings(lines);

  var depth = 0;
  int? runAsyncDepth; // brace depth at which the active runAsync block opened
  int? testBodyDepth;

  for (var i = 0; i < lines.length; i++) {
    // Analyse the blanked line; REPORT the original, or the message shows the
    // reader an empty line and asks them to fix it.
    final line = lines[i];
    final code = stripCommentsAndStrings(source[i]);

    if (testBodyDepth == null && rules.opensTestBody(code)) {
      testBodyDepth = depth;
    }
    if (runAsyncDepth == null && code.contains('runAsync(')) {
      runAsyncDepth = depth;
    }

    final inRunAsync = runAsyncDepth != null;
    final inTestBody = testBodyDepth != null;
    final ignored = line.contains(rules.ignoreMarker);

    if (!ignored && code.contains('await ')) {
      final teardown = rules.teardownCall;
      final realAsync = rules.realAsyncCall;

      if (inRunAsync && teardown != null && teardown.hasMatch(code)) {
        out.add(
          Violation(
            file: path,
            line: i + 1,
            rule: Violation.teardownInRunAsync,
            why:
                'A player built under the fake clock finishes its teardown only '
                'when that clock advances. runAsync runs on the real event loop '
                'and never advances it, so this await never returns. Drop the '
                'await — unawaited(...) — and let pump() drive the teardown.',
            source: line,
          ),
        );
      } else if (inTestBody &&
          !inRunAsync &&
          realAsync != null &&
          realAsync.hasMatch(code)) {
        out.add(
          Violation(
            file: path,
            line: i + 1,
            rule: Violation.realAsyncInTestBody,
            why: 'Real disk or plugin work runs on the real event loop, which '
                'pump() does not advance — this await never returns. Either stub '
                'the dependency so the test touches no disk, or wrap the call in '
                'tester.runAsync.',
            source: line,
          ),
        );
      }
    }

    depth += '{'.allMatches(code).length - '}'.allMatches(code).length;
    // A block closes when the depth comes back to where it opened.
    if (runAsyncDepth != null && depth <= runAsyncDepth) runAsyncDepth = null;
    if (testBodyDepth != null && depth <= testBodyDepth) testBodyDepth = null;
  }
  return out;
}

final _blockDelimiter = RegExp("'''|\"\"\"");

/// Blanks the interior of triple-quoted strings, keeping the line count intact
/// so reported line numbers stay true.
///
/// Dart source embedded in a `'''...'''` block is data, not code.
List<String> blankBlockStrings(List<String> lines) {
  final out = <String>[];
  var inBlock = false;

  for (final line in lines) {
    final delimiters = _blockDelimiter.allMatches(line).length;
    if (inBlock) {
      // Inside the string. An odd count closes it; whatever trails the closing
      // delimiter is code again, but it is never block structure in practice,
      // so blanking the whole line is both safe and simple.
      out.add('');
      if (delimiters.isOdd) inBlock = false;
    } else if (delimiters.isOdd) {
      // Opens a block that runs onto the next line. Keep the prefix — it holds
      // the real code (`final v = scan(`) whose braces have to be counted.
      inBlock = true;
      out.add(line.split(_blockDelimiter).first);
    } else {
      // Zero delimiters, or an open and close on one line — nothing spans lines.
      out.add(line);
    }
  }
  return out;
}

/// Blanks string literals and strips line comments, so their braces are not
/// counted as block structure.
///
/// STRINGS FIRST, then comments. Reverse the order and the `//` inside a URL
/// literal — `const cfg = {'url': 'https://example.test/x'};` — reads as the
/// start of a comment, truncating the line and eating the closing brace. The
/// depth counter then runs one too deep for the REST OF THE FILE, so runAsync
/// blocks never appear to close and every later teardown is falsely accused.
String stripCommentsAndStrings(String line) {
  final noStrings = line
      .replaceAll(RegExp(r'"[^"]*"'), '""')
      .replaceAll(RegExp(r"'[^']*'"), "''");
  return noStrings.replaceAll(RegExp(r'//.*$'), '');
}
