/// Finds the Flutter test patterns that deadlock the test isolate.
///
/// Every other mistake in a test file fails loudly. This family does not — it
/// DEADLOCKS. The suite stops producing output and sits there, and a hang is
/// indistinguishable from a slow run, so nobody learns which test did it or
/// even that a test did it. The per-test timeout cannot help either: the
/// isolate is wedged, so its timer never fires. The ceiling is the CI job
/// timeout.
///
/// Point [run] at a directory of tests, or call [scanLines] on source you
/// already hold.
library;

export 'src/rules.dart';
export 'src/runner.dart';
export 'src/scanner.dart';
export 'src/violation.dart';
