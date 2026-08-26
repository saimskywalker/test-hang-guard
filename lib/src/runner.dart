import 'dart:io';

import 'rules.dart';
import 'scanner.dart';
import 'violation.dart';

/// Scanned when no paths are given on the command line.
const defaultPaths = <String>['test'];

/// Scans every `.dart` file under [paths] and writes a report.
///
/// Returns the process exit code: [exitClean], [exitViolations], or
/// [exitUsage] when a path does not exist. A directory is walked recursively;
/// a file is scanned whatever its extension, on the grounds that naming it
/// explicitly is intent.
int run({
  List<String> paths = defaultPaths,
  required HangRules rules,
  required StringSink out,
  required StringSink err,
}) {
  final files = <File>[];

  for (final path in paths) {
    final directory = Directory(path);
    final file = File(path);
    if (directory.existsSync()) {
      files.addAll(
        directory
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart')),
      );
    } else if (file.existsSync()) {
      files.add(file);
    } else {
      err.writeln('test_hang_guard: no such file or directory: $path');
      return exitUsage;
    }
  }

  files.sort((a, b) => a.path.compareTo(b.path));

  final violations = <Violation>[];
  for (final file in files) {
    violations.addAll(scanLines(file.path, file.readAsLinesSync(), rules));
  }

  return report(
    violations: violations,
    fileCount: files.length,
    ignoreMarker: rules.ignoreMarker,
    out: out,
    err: err,
  );
}

/// Writes [violations] and returns the exit code they imply.
///
/// Split out from [run] so the wording of a failure can be tested without a
/// filesystem.
int report({
  required List<Violation> violations,
  required int fileCount,
  String ignoreMarker = defaultIgnoreMarker,
  required StringSink out,
  required StringSink err,
}) {
  if (violations.isEmpty) {
    out.writeln(
      'test_hang_guard: $fileCount file(s) scanned, no hang patterns found.',
    );
    return exitClean;
  }

  err.writeln(
    '\ntest_hang_guard: ${violations.length} pattern(s) that can WEDGE THE '
    'TEST ISOLATE and hang the whole suite with no error.\n',
  );
  for (final violation in violations) {
    err.writeln('${violation.file}:${violation.line}  [${violation.rule}]');
    err.writeln('  ${violation.source.trim()}');
    err.writeln('  ${violation.why}\n');
  }
  err.writeln(
    'If one of these is genuinely safe, append  // $ignoreMarker: <reason>  '
    'to the line.\n',
  );
  return exitViolations;
}
