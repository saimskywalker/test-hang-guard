---
name: False positive
about: A line was flagged that cannot actually hang
labels: false-positive
---

A false positive is the failure mode that matters most here. People silence a
gate they do not trust, and a silenced gate catches nothing — so these are
worth reporting even though the ignore marker works around them.

**The flagged line**

```dart

```

**Which rule fired**

- [ ] `awaited-teardown-in-run-async`
- [ ] `awaited-real-async-in-test-body`

**Why it cannot hang**

<!-- e.g. the receiver is named `player` but is a plain value object; the call
     is a fake with no real I/O behind it. -->

**Does the test suite actually pass with this line in place?**

<!-- The decisive evidence. If the suite runs to completion, the pattern is
     safe in this context and the matcher is too broad. -->

**Would a narrower list fix it for you?**

<!-- `--teardown-receiver` / `--async-call` replace the default lists, so a
     project-specific naming clash can often be settled without a code change.
     Worth saying if you tried and it did not work. -->
