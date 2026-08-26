import 'dart:io';

import 'package:args/args.dart';
import 'package:test_hang_guard/test_hang_guard.dart';

const _version = '0.1.0';

ArgParser buildParser() => ArgParser()
  ..addMultiOption(
    'teardown-receiver',
    help: 'Receiver name fragments whose teardown may not be awaited inside '
        'tester.runAsync. Replaces the default list.',
    valueHelp: 'name',
  )
  ..addMultiOption(
    'teardown-method',
    help: 'Method names that count as a teardown. Replaces the default list.',
    valueHelp: 'name',
  )
  ..addMultiOption(
    'async-call',
    help: 'Names that, when called, do real-event-loop work. Replaces the '
        'default list.',
    valueHelp: 'name',
  )
  ..addMultiOption(
    'async-symbol',
    help: 'Bare identifiers that count wherever they appear — for a store '
        'reached through a singleton, match the type name.',
    valueHelp: 'Name',
  )
  ..addMultiOption(
    'test-function',
    help: 'Functions that declare a widget test body. Replaces the default '
        'list.',
    valueHelp: 'name',
  )
  ..addOption(
    'ignore-marker',
    help: 'Text that suppresses a finding on the line carrying it.',
    defaultsTo: defaultIgnoreMarker,
    valueHelp: 'text',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'Print this usage.')
  ..addFlag('version', negatable: false, help: 'Print the version.');

String usage(ArgParser parser) =>
    'Usage: test_hang_guard [options] [paths...]\n'
    '\n'
    'Fails on the patterns that deadlock a Flutter test isolate. Scans\n'
    '${defaultPaths.map((d) => '$d/').join(', ')} when no path is given.\n'
    '\n'
    '${parser.usage}\n'
    '\n'
    'Exit codes: $exitClean clean, $exitViolations violations found, '
    '$exitUsage bad usage.';

void main(List<String> args) {
  final parser = buildParser();

  final ArgResults argv;
  try {
    argv = parser.parse(args);
  } on FormatException catch (e) {
    stderr.writeln('test_hang_guard: ${e.message}\n');
    stderr.writeln(usage(parser));
    exit(exitUsage);
  }

  if (argv.flag('help')) {
    stdout.writeln(usage(parser));
    exit(exitClean);
  }
  if (argv.flag('version')) {
    stdout.writeln('test_hang_guard $_version');
    exit(exitClean);
  }

  // wasParsed, not isNotEmpty: passing an empty list is how a rule is turned
  // off, and that has to be distinguishable from not passing the option.
  List<String>? given(String name) =>
      argv.wasParsed(name) ? argv.multiOption(name) : null;

  final rules = HangRules(
    teardownReceivers: given('teardown-receiver'),
    teardownMethods: given('teardown-method'),
    asyncCalls: given('async-call'),
    asyncSymbols: given('async-symbol'),
    testFunctions: given('test-function'),
    ignoreMarker: argv.option('ignore-marker') ?? defaultIgnoreMarker,
  );

  exit(
    run(
      paths: argv.rest.isEmpty ? defaultPaths : argv.rest,
      rules: rules,
      out: stdout,
      err: stderr,
    ),
  );
}
