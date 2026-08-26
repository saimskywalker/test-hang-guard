## What this changes

<!-- One or two sentences. What is different after this merges? -->

## Why

<!-- The problem it solves. If it fixes a bug, what was the symptom? -->

## Checklist

- [ ] `dart analyze --fatal-infos` is clean and `dart format` leaves no diff
- [ ] `dart test` passes
- [ ] If this fixes a bug: there is a test that fails without the fix
- [ ] If this changes a rule: there is a fixture for the pattern it now catches
      **and** one for the safe code it must still leave alone

## For rule changes

A rule is a claim that some pattern deadlocks the isolate. Please say how it
was established — a hung run, a reproduction, a linked issue. A rule added on a
hunch flags code nobody has proven dangerous, and a gate that does that gets
switched off, which costs more than the rule was ever worth.
