import 'dart:io';

import 'package:test/test.dart';

/// The CLI, not the library.
///
/// `args` turns `--ignore-marker=` into an empty string, and only a real
/// process does that — a unit test constructing `HangRules` directly cannot
/// reach the path where the value arrives blank from a command line. This is
/// the same reason the pattern-list options needed a process-level check.
ProcessResult runCli(List<String> args) => Process.runSync(
      Platform.resolvedExecutable,
      ['run', 'bin/test_hang_guard.dart', ...args],
    );

void main() {
  late Directory hanging;

  setUpAll(() {
    hanging = Directory.systemTemp.createTempSync('thg_cli_');
    File('${hanging.path}/a_test.dart').writeAsStringSync('''
void main() {
  testWidgets('hangs', (tester) async {
    await tester.runAsync(() async {
      await audioPlayer.dispose();
    });
  });
}
''');
  });

  tearDownAll(() => hanging.deleteSync(recursive: true));

  test('a hanging tree exits 1', () {
    expect(runCli([hanging.path]).exitCode, 1);
  });

  test('a blank --ignore-marker is bad usage, not a clean tree', () {
    // Before this was refused, the blank marker matched every line: the scan
    // suppressed every finding, printed "no hang patterns found" and exited 0
    // against the very tree the test above proves is dirty.
    final result = runCli(['--ignore-marker=', hanging.path]);
    expect(result.exitCode, 2);
    expect(result.stderr, contains('must not be blank'));
    expect(result.stdout, isNot(contains('no hang patterns found')));
  });

  test('a blank --ignore-marker of only whitespace is refused too', () {
    expect(runCli(['--ignore-marker=   ', hanging.path]).exitCode, 2);
  });

  test('a padded --ignore-marker still suppresses', () {
    final dir = Directory.systemTemp.createTempSync('thg_cli_ok_');
    addTearDown(() => dir.deleteSync(recursive: true));
    File('${dir.path}/b_test.dart').writeAsStringSync('''
void main() {
  testWidgets('fine', (tester) async {
    await tester.runAsync(() async {
      await audioPlayer.dispose(); // no-hang-check: fake player
    });
  });
}
''');
    expect(runCli(['--ignore-marker=  no-hang-check  ', dir.path]).exitCode, 0);
  });
}
