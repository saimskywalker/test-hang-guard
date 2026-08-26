import 'package:test/test.dart';
import 'package:test_hang_guard/test_hang_guard.dart';

List<Violation> scan(String source, {HangRules? rules}) =>
    scanLines('fixture.dart', source.split('\n'), rules ?? HangRules());

void main() {
  group('awaited teardown inside runAsync', () {
    test('is flagged', () {
      // The fixture lives in a block string on purpose: the scanner has to
      // blank these out, and a rule with no regression test is a rule that
      // gets broken.
      final violations = scan('''
testWidgets('plays', (tester) async {
  await tester.pumpWidget(const App());
  await tester.runAsync(() async {
    await audioPlayer.dispose();
  });
});
''');

      expect(violations, hasLength(1));
      expect(violations.single.rule, Violation.teardownInRunAsync);
      expect(violations.single.line, 4);
      expect(violations.single.source, contains('audioPlayer.dispose()'));
      expect(violations.single.why, contains('never returns'));
    });

    test('matches every default receiver and method', () {
      for (final receiver in defaultTeardownReceivers) {
        for (final method in defaultTeardownMethods) {
          final violations = scan('''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    await $receiver.$method();
  });
});
''');
          expect(
            violations.map((v) => v.rule),
            [Violation.teardownInRunAsync],
            reason: '$receiver.$method() should be flagged',
          );
        }
      }
    });

    test('matches a receiver whose name merely contains the fragment', () {
      final violations = scan('''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    await backgroundAudioPlayerFake.stop();
  });
});
''');
      expect(violations, hasLength(1));
    });

    test('tolerates whitespace around the selector', () {
      final violations = scan('''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    await player . stop ();
  });
});
''');
      expect(violations, hasLength(1));
    });

    test('is not flagged once the runAsync block has closed', () {
      final violations = scan('''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(Duration.zero);
  });
  unawaited(player.dispose());
  await tester.pump();
});
''');
      expect(violations, isEmpty);
    });

    test('a teardown outside runAsync is left alone', () {
      // Outside runAsync the teardown is driven by pump(), which is the fix the
      // rule asks for — flagging it here would flag the remedy.
      final violations = scan('''
testWidgets('t', (tester) async {
  await player.dispose();
});
''');
      expect(violations, isEmpty);
    });

    test('pause() is not teardown and is not flagged', () {
      final violations = scan('''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    await audioPlayer.pause();
  });
});
''');
      expect(violations, isEmpty);
    });
  });

  group('awaited real async inside a test body', () {
    test('is flagged', () {
      final violations = scan('''
testWidgets('reads a draft', (tester) async {
  final dir = await getApplicationDocumentsDirectory();
  await tester.pumpWidget(const App());
});
''');
      expect(violations, hasLength(1));
      expect(violations.single.rule, Violation.realAsyncInTestBody);
      expect(violations.single.line, 2);
    });

    test('matches every default call name', () {
      for (final call in defaultAsyncCalls) {
        final violations = scan('''
testWidgets('t', (tester) async {
  await $call('x');
});
''');
        expect(
          violations.map((v) => v.rule),
          [Violation.realAsyncInTestBody],
          reason: '$call() should be flagged',
        );
      }
    });

    test('a bare word without a call is not flagged', () {
      // `readAsString` on its own could be a variable, a tear-off name, or a
      // word in a string; only `readAsString(` is I/O.
      final violations = scan('''
testWidgets('t', (tester) async {
  final readAsString = 1;
  await tester.pump();
});
''');
      expect(violations, isEmpty);
    });

    test('constructing a File does no I/O and is not flagged', () {
      // This is the false positive that would have got the whole gate
      // switched off: it is safe, and it is something anyone might write.
      final violations = scan('''
testWidgets('t', (tester) async {
  await tester.pumpWidget(Image.file(File('avatar.png')));
});
''');
      expect(violations, isEmpty);
    });

    test('the same call wrapped in runAsync is not flagged', () {
      final violations = scan('''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    await File('x').readAsString();
  });
});
''');
      expect(violations, isEmpty);
    });

    test('the same call outside any test body is not flagged', () {
      final violations = scan('''
Future<void> main() async {
  await File('x').readAsString();
}
''');
      expect(violations, isEmpty);
    });

    test('an unawaited call is not flagged', () {
      final violations = scan('''
testWidgets('t', (tester) async {
  unawaited(File('x').readAsString());
  await tester.pump();
});
''');
      expect(violations, isEmpty);
    });
  });

  group('suppression', () {
    test('the ignore marker silences a line', () {
      final violations = scan('''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    await player.stop(); // no-hang-check: a fake with a synchronous stop
  });
});
''');
      expect(violations, isEmpty);
    });

    test('it silences only the line it sits on', () {
      final violations = scan('''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    await player.stop(); // no-hang-check: fake
    await audioHandler.dispose();
  });
});
''');
      expect(violations, hasLength(1));
      expect(violations.single.line, 4);
    });

    test('a custom marker replaces the default', () {
      final rules = HangRules(ignoreMarker: 'HANG-OK');
      const fixture = '''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    await player.stop(); // HANG-OK: fake
    await handler.stop(); // no-hang-check: not the configured marker
  });
});
''';
      final violations = scan(fixture, rules: rules);
      expect(violations, hasLength(1));
      expect(violations.single.line, 4);
    });
  });

  group('brace tracking', () {
    test('a URL literal does not desynchronise the depth counter', () {
      // Strings are blanked before comments are stripped. The other order reads
      // the `//` in the URL as a comment, eats the closing brace, and leaves the
      // depth one too deep for the rest of the file.
      final violations = scan('''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    const cfg = {'url': 'https://example.test/x'};
  });
  unawaited(player.dispose());
});
''');
      expect(violations, isEmpty);
    });

    test('braces inside a comment are not block structure', () {
      final violations = scan('''
testWidgets('t', (tester) async {
  await tester.runAsync(() async {
    // closes like this: }
    await player.stop();
  });
});
''');
      expect(violations, hasLength(1));
      expect(violations.single.line, 4);
    });

    test('two sibling tests are each scoped correctly', () {
      final violations = scan('''
testWidgets('one', (tester) async {
  await getTemporaryDirectory();
});

void helper() async {
  await getTemporaryDirectory();
}

testWidgets('two', (tester) async {
  await getTemporaryDirectory();
});
''');
      expect(violations.map((v) => v.line), [2, 10]);
    });
  });

  group('blankBlockStrings', () {
    test('blanks a block string interior but keeps the line count', () {
      final blanked = blankBlockStrings([
        "final fixture = '''",
        'await player.stop();',
        "''';",
        'await handler.stop();',
      ]);
      expect(blanked, hasLength(4));
      expect(blanked[0], 'final fixture = ');
      expect(blanked[1], '');
      expect(blanked[2], '');
      expect(blanked[3], 'await handler.stop();');
    });

    test('a single-line block string spans nothing', () {
      final blanked = blankBlockStrings(["const a = '''x''';"]);
      expect(blanked.single, "const a = '''x''';");
    });

    test('double-quoted blocks are handled too', () {
      final blanked = blankBlockStrings([
        'final fixture = """',
        'await player.stop();',
        '""";',
      ]);
      expect(blanked[1], '');
    });
  });

  group('stripCommentsAndStrings', () {
    test('blanks strings and drops the trailing comment', () {
      expect(
        stripCommentsAndStrings("var a = 'x'; // note {"),
        "var a = ''; ",
      );
    });

    test('leaves a brace outside a string alone', () {
      expect(stripCommentsAndStrings('if (a) {'), 'if (a) {');
    });
  });
}
