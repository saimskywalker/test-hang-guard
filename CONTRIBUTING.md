# Contributing

Contributions are welcome. A few things worth knowing before you spend time.

## How changes land

Every change reaches `main` through a pull request that the maintainer reviews
and merges. That includes changes from forks, which is the normal path — you
cannot push to this repository directly, and nothing merges without a review.
If a PR sits without a response, a nudge is fine.

## Before opening a PR

```bash
dart pub get
dart format .
dart analyze --fatal-infos
dart test
```

CI runs the same, and then runs the CLI against a tree that hangs and one that
does not, checking the exit codes. Those are the actual contract — `dart test`
never starts the process, so it cannot see them.

## Adding or widening a rule

A rule is a claim that some pattern wedges the test isolate. The bar is
evidence, not plausibility: a run that hung, a reproduction, an issue that
shows it. `pause()` is absent from the teardown list for exactly this reason —
an early version matched it, and nothing had ever been observed to deadlock on
it.

That asymmetry is the whole design. A missed hang costs one CI run and is
recoverable. A false positive costs trust, people switch the gate off, and then
every hang gets through. `File(...)` is not matched for the same reason: the
constructor performs no I/O, and matching it flagged
`await tester.pumpWidget(Image.file(File(p)))` — safe code anyone might write,
and on its own enough to get the gate disabled.

So a rule change needs two fixtures: one for the pattern it now catches, and
one for the nearby safe code it must still leave alone.

## What a good bug fix looks like

A test that fails without the fix. Several of the tests here exist because
something shipped broken once — the comments say which — and that is the shape
worth adding to.

## Things to be careful with

**Brace-depth tracking.** Both rules are block-scoped, so the depth counter is
load-bearing. Desynchronise it once and it stays wrong for the rest of the
file, and the symptom is a burst of false positives far from the real cause.
`stripCommentsAndStrings` blanks strings *before* it strips comments for this
reason: the other order reads the `//` in a URL literal as a comment start,
eats the closing brace on that line, and leaves the counter one too deep.

**Block strings.** Fixtures in this package are Dart source inside `'''`
blocks, which means the scanner would read its own test data as violations if
`blankBlockStrings` stopped working. It blanks lines rather than removing them
so reported line numbers stay true — check the line numbers in a fixture test,
not just the count.

**Matching is name-based, deliberately.** Resolving the static type of a
receiver means running the analyzer over the package, which costs more time
than the hang the tool prevents. If you find yourself needing type resolution
to express a rule, the rule probably belongs in a custom lint instead.

## Scope

This catches a small, specific family of deadlocks by reading source text. It
is not a linter, it does not type-check, and it does not try to find every way
a test can be slow — only the ones where the isolate stops and the suite tells
you nothing.
