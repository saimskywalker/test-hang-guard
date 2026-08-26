import 'dart:io';

import 'package:test/test.dart';
import 'package:test_hang_guard/test_hang_guard.dart';

const _hangingTest = '''
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('hangs', (tester) async {
    await tester.runAsync(() async {
      await audioPlayer.dispose();
    });
  });
}
''';

const _cleanTest = '''
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('is fine', (tester) async {
    await tester.pumpWidget(const SizedBox());
    unawaited(player.dispose());
    await tester.pump();
  });
}
''';

void main() {
  late Directory root;
  late StringBuffer out;
  late StringBuffer err;

  setUp(() {
    root = Directory.systemTemp.createTempSync('test_hang_guard_');
    out = StringBuffer();
    err = StringBuffer();
  });

  tearDown(() => root.deleteSync(recursive: true));

  File write(String relative, String contents) {
    final file = File('${root.path}/$relative');
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(contents);
    return file;
  }

  test('a clean tree exits 0 and says how much it scanned', () {
    write('test/a_test.dart', _cleanTest);
    write('test/nested/b_test.dart', _cleanTest);

    final code = run(
      paths: ['${root.path}/test'],
      rules: HangRules(),
      out: out,
      err: err,
    );

    expect(code, exitClean);
    expect(out.toString(), contains('2 file(s) scanned'));
    expect(out.toString(), contains('no hang patterns found'));
    expect(err.toString(), isEmpty);
  });

  test('a violation exits 1 and names the file and line on stderr', () {
    write('test/a_test.dart', _hangingTest);

    final code = run(
      paths: ['${root.path}/test'],
      rules: HangRules(),
      out: out,
      err: err,
    );

    expect(code, exitViolations);
    expect(err.toString(), contains('a_test.dart:6'));
    expect(err.toString(), contains(Violation.teardownInRunAsync));
    expect(err.toString(), contains('audioPlayer.dispose()'));
    expect(err.toString(), contains('no-hang-check'));
    expect(out.toString(), isEmpty);
  });

  test('a missing path exits 2 without scanning anything', () {
    final code = run(
      paths: ['${root.path}/nowhere'],
      rules: HangRules(),
      out: out,
      err: err,
    );

    expect(code, exitUsage);
    expect(err.toString(), contains('no such file or directory'));
    expect(out.toString(), isEmpty);
  });

  test('a file path is scanned directly', () {
    final file = write('test/a_test.dart', _hangingTest);

    final code = run(
      paths: [file.path],
      rules: HangRules(),
      out: out,
      err: err,
    );

    expect(code, exitViolations);
  });

  test('several paths are scanned in one run', () {
    write('test/a_test.dart', _cleanTest);
    write('integration_test/b_test.dart', _hangingTest);

    final code = run(
      paths: ['${root.path}/test', '${root.path}/integration_test'],
      rules: HangRules(),
      out: out,
      err: err,
    );

    expect(code, exitViolations);
    expect(err.toString(), contains('b_test.dart'));
  });

  test('non-Dart files in a scanned directory are skipped', () {
    write('test/a_test.dart', _cleanTest);
    write('test/fixture.txt', _hangingTest);

    final code = run(
      paths: ['${root.path}/test'],
      rules: HangRules(),
      out: out,
      err: err,
    );

    expect(code, exitClean);
    expect(out.toString(), contains('1 file(s) scanned'));
  });

  test('files are reported in a stable sorted order', () {
    write('test/z_test.dart', _hangingTest);
    write('test/a_test.dart', _hangingTest);

    run(paths: ['${root.path}/test'], rules: HangRules(), out: out, err: err);

    final report = err.toString();
    expect(
        report.indexOf('a_test.dart'), lessThan(report.indexOf('z_test.dart')));
  });

  group('report', () {
    test('an empty list is clean', () {
      final code = report(violations: [], fileCount: 7, out: out, err: err);
      expect(code, exitClean);
      expect(out.toString(), contains('7 file(s) scanned'));
    });

    test('the suppression hint uses the configured marker', () {
      final code = report(
        violations: [
          const Violation(
            file: 'test/a_test.dart',
            line: 12,
            rule: Violation.realAsyncInTestBody,
            why: 'because',
            source: '  await readAsString(p);',
          ),
        ],
        fileCount: 1,
        ignoreMarker: 'HANG-OK',
        out: out,
        err: err,
      );

      expect(code, exitViolations);
      expect(err.toString(), contains('// HANG-OK: <reason>'));
      expect(err.toString(), contains('1 pattern(s)'));
      expect(err.toString(), contains('await readAsString(p);'));
    });
  });

  test('Violation stringifies as file, line and rule', () {
    const violation = Violation(
      file: 'test/a_test.dart',
      line: 3,
      rule: Violation.teardownInRunAsync,
      why: 'because',
      source: 'x',
    );
    expect(violation.toString(),
        'test/a_test.dart:3  [awaited-teardown-in-run-async]');
  });
}
