# Changelog

## 0.1.0

First release.

- Two rules, both scoped to a widget test body by a brace-depth scan rather
  than a line match: an awaited player teardown inside `tester.runAsync`, and
  awaited real-event-loop work (disk I/O, `path_provider`) inside the test
  body itself.
- Every pattern list is replaceable from the command line, and passing an
  empty list disables the rule that uses it.
- `// no-hang-check: <reason>` suppresses one line; `--ignore-marker` changes
  the text.
- Exit codes: `0` clean, `1` violations, `2` bad usage.
