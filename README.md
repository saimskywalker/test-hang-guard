# test_hang_guard

**Your Flutter test suite hangs. `flutter test` prints nothing, names no file,
and sits there until the CI job timeout kills it.** No stack trace, no failing
test name, no output at all — just a job that ran for 60 minutes and then went
red for "The operation was canceled."

This finds the cause by reading the source, before the suite runs. It takes
about two seconds and it names the file and the line.

```
test_hang_guard: 1 pattern(s) that can WEDGE THE TEST ISOLATE and hang the whole suite with no error.

test/player_test.dart:7  [awaited-teardown-in-run-async]
  await audioPlayer.dispose();
  A player built under the fake clock finishes its teardown only when that clock
  advances. runAsync runs on the real event loop and never advances it, so this
  await never returns. Drop the await — unawaited(...) — and let pump() drive
  the teardown.

If one of these is genuinely safe, append  // no-hang-check: <reason>  to the line.
```

## Why a hanging test suite reports nothing

A widget test runs on a **fake clock**. `tester.pump()` advances it. Real
asynchronous work — a disk read, a plugin call, a player shutting itself down —
runs on the **real** event loop, which `pump()` never advances. `await` one of
those from inside a widget test and the future never completes.

The isolate is now wedged, and that has three consequences that together
explain why you get no information:

- **The per-test timeout cannot fire.** It is a timer, the timer lives on the
  wedged isolate, and a wedged isolate runs no timers. The usual safety net is
  gone precisely when you need it.
- **Nothing has failed.** A hang is not an error, so no reporter prints
  anything. The last line you see is whichever test *did* finish.
- **A hang looks exactly like a slow run.** For the first several minutes there
  is no way to tell them apart, so the run is usually allowed to continue.

The ceiling is your job timeout. Locally you notice in a minute or two;
in CI it burns the whole allowance and tells you nothing about which test did
it.

## Install

Not on pub.dev yet, so it installs from git.

```bash
dart pub global activate --source git https://github.com/saimskywalker/test-hang-guard.git
```

That puts the executable in `$HOME/.pub-cache/bin`. If that is not on your
`PATH`, either add it or call the tool through pub — `dart pub global run
test_hang_guard` — which needs no `PATH` change.

Then, from your Flutter package root:

```bash
test_hang_guard
```

Or without installing it globally — add it as a dev dependency and run it from
the package:

```yaml
dev_dependencies:
  test_hang_guard:
    git: https://github.com/saimskywalker/test-hang-guard.git
```

```bash
dart pub get
dart run test_hang_guard
```

Once it is published, `dart pub global activate test_hang_guard` and
`dart pub add --dev test_hang_guard` will be the shorter forms of the same two
routes.

## Usage

```bash
test_hang_guard                            # scans test/
test_hang_guard test integration_test      # scans both
test_hang_guard test/features/player       # one directory
test_hang_guard test/player_test.dart      # one file
```

## In CI

This is what the tool is for, so it is worth wiring properly. Put it **before**
`flutter test`, never after: the point is to fail in two seconds instead of
hanging for an hour, and that only works if it runs first. After the suite has
wedged, there is nothing left to save.

A whole GitHub Actions job, using the dev dependency from above:

```yaml
name: test
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - run: flutter pub get

      # Before the suite, not after. Seconds, and it names the file and line.
      - run: dart run test_hang_guard test

      - run: flutter test
```

Without the dev dependency, install it inside the job instead — this needs no
change to the package's `pubspec.yaml`:

```yaml
      - run: dart pub global activate --source git https://github.com/saimskywalker/test-hang-guard.git
      - run: dart pub global run test_hang_guard test
```

Two things to know before the step goes red on you:

- **Exit code 2 is not a finding.** It means the scan could not run, and by far
  the most common cause is naming a path the package does not have —
  `test_hang_guard test integration_test` in a package with no
  `integration_test/` exits 2 without scanning anything. Name only the
  directories that exist.
- **Nothing here needs a Flutter SDK.** The scan reads source text, so on a
  `dart`-only runner the `dart pub global activate` form above works on its own.

GitLab CI, or any runner that speaks shell:

```yaml
test:
  script:
    - flutter pub get
    - dart run test_hang_guard test
    - flutter test
```

## The rules

Two patterns, each scoped to a block rather than to a line: the first to a
`tester.runAsync(...)` closure, the second to a `testWidgets` body outside one.
Scoping is done by tracking brace depth through the file, not by matching
lines, because "is this `await` inside a `runAsync` closure" is a question no
line-by-line regex can answer.

### `awaited-teardown-in-run-async`

An awaited `stop()` or `dispose()` on something whose name looks like a player,
inside a `tester.runAsync(...)` closure.

```dart
await tester.runAsync(() async {
  await audioPlayer.dispose();   // never returns
});
```

**Why it deadlocks.** The player was created under the fake clock, so its
teardown completes only when that clock advances. `runAsync` runs its body on
the real event loop and does not advance the fake one. The teardown waits for a
clock that is waiting for the teardown.

**The fix.** Do not await it — let `pump()` drive it:

```dart
unawaited(audioPlayer.dispose());
await tester.pump();
```

Receivers matched by default: any identifier containing `audioHandler`,
`audioPlayer`, `player` or `handler`, case-insensitively. Methods: `stop` and
`dispose`. `pause()` is deliberately *not* matched — it is not teardown, and
has never been observed to deadlock.

### `awaited-real-async-in-test-body`

An awaited call that does real I/O, inside a `testWidgets` body and *not*
inside `runAsync`.

```dart
testWidgets('loads the draft', (tester) async {
  final dir = await getApplicationDocumentsDirectory();   // never returns
});
```

**Why it deadlocks.** Same root cause. Disk I/O and `path_provider` complete on
the real event loop, and inside a widget test nothing is advancing it.

**The fix.** Either stub the dependency so the test touches no disk — usually
the right answer, since a widget test that reads real files is testing the
filesystem — or wrap the call so it runs on the real loop:

```dart
await tester.runAsync(() => File(path).readAsString());
```

Matched by default: `getApplicationDocumentsDirectory`,
`getTemporaryDirectory`, `getExternalStorageDirectory`, `readAsString`,
`readAsBytes`, `readAsLines`, `writeAsString`, `writeAsBytes`.

These are the **I/O methods**, not `File(...)` or `Directory(...)`. Those
constructors perform no I/O — they build a handle. Matching them flags
`await tester.pumpWidget(Image.file(File(path)))`, which is safe and something
anyone might write.

## Suppressing a false positive

Put the marker on the offending line, with a reason:

```dart
await player.stop();   // no-hang-check: a fake, stops synchronously
```

It suppresses that line only. `--ignore-marker=<text>` changes the word if
`no-hang-check` collides with something in your codebase.

Prefer this over widening a rule. A gate that flags things nobody has proven
dangerous is a gate people switch off, and a switched-off gate catches nothing.

## Configuring the rules

Every list can be replaced from the command line. **Passing an option replaces
that default list rather than adding to it**, so a rule can be narrowed as
easily as widened, and passing it empty — `--async-call=''` — turns the rule
off.

| Option | What it sets |
|---|---|
| `--teardown-receiver=<name>` | Receiver name fragments treated as a player |
| `--teardown-method=<name>` | Calls that count as a teardown |
| `--async-call=<name>` | Names that do real-event-loop work when called |
| `--async-symbol=<Name>` | Bare identifiers that count wherever they appear |
| `--test-function=<name>` | Functions that declare a widget test body |
| `--ignore-marker=<text>` | The suppression marker (default `no-hang-check`) |

`--async-symbol` is for a store reached through a singleton —
`DraftStore.instance.loadAll()`, where the method name varies but the type name
does not, so the type is what you match. It is the one option with no default,
so it only ever adds.

`--test-function` matters if your project wraps `testWidgets` in a harness of
its own; a body declared by `testWidgetsWithHarness(...)` is invisible to the
default.

```bash
test_hang_guard \
  --async-symbol=DraftStore \
  --test-function=testWidgets --test-function=testWidgetsWithHarness \
  test
```

## Exit codes

| Code | Meaning |
|---|---|
| `0` | Nothing found. A one-line summary goes to stdout. |
| `1` | At least one violation. The report goes to stderr. |
| `2` | Bad usage, or a path that does not exist. |

## Using it as a library

The scanner works on source held in memory, so it can back an editor
integration or a custom check:

```dart
import 'package:test_hang_guard/test_hang_guard.dart';

final violations = scanLines('player_test.dart', source.split('\n'), HangRules());
for (final v in violations) {
  print('${v.file}:${v.line} ${v.rule} — ${v.why}');
}
```

## Limitations

Matching is on **names**, not resolved types. A variable called `player` that
is not a player gets flagged; a player called `engine` does not. Resolving
static types means running the analyzer over the package, which costs more time
than the hang this prevents — and the trade is deliberate. A false positive
costs one ignore marker. A missed hang costs a CI run.

It reads source text, so it does not follow a call into a helper function. A
teardown awaited inside a helper that the test calls is not caught.

## License

MIT
