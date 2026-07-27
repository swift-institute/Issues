# Swift compiler crash: `borrowing` actor parameter captured by a closure

**Canonical record:** [swift-institute/Issues#3](https://github.com/swift-institute/Issues/issues/3)

**Classification:** compiler crash in the `MoveOnlyTypeEliminator` SIL pass.

Swift 6.2.3 crashes when an actor method captures a `borrowing` class parameter
in a synchronous, non-escaping closure such as the predicate passed to
`removeAll`.

## Reproducer

The triggering source is
[`Sources/Reproducer/Crash.swift.txt`](Sources/Reproducer/Crash.swift.txt).
It is compiled out of process because compiling it as a normal SwiftPM target
would abort the package build.

```sh
cp Sources/Reproducer/Crash.swift.txt /tmp/borrowing-actor-closure.swift
swiftc -parse-as-library -swift-version 6 -c \
  /tmp/borrowing-actor-closure.swift \
  -o /tmp/borrowing-actor-closure.o
```

Expected: compilation succeeds.

Observed on Swift 6.2.3 (`swiftlang-6.2.3.3.21`, arm64 macOS 26):
`swift-frontend` exits on signal 5 while `MoveOnlyTypeEliminator` handles an
`init_existential_ref` instruction.

## Trigger and controls

The crash requires all three ingredients:

1. an actor method;
2. a `borrowing` parameter;
3. capture of that parameter in a closure.

Removing `borrowing`, using the parameter outside a closure, or moving the
method to a non-actor type compiles.

## Impact and workaround

The defect blocks ownership annotations in actor-based subscription, observer,
and callback management code. Removing the `borrowing` annotation is a verified
workaround.

## Upstream status

No exact upstream issue has been identified. The related reports
swiftlang/swift#85275, #69252, #84568, and #76804 have different triggers or
failure modes.

## Provenance

This dossier is a clean-content consolidation from the temporary migration
source
[`swift-institute/swift-issue-borrowing-actor-closure`](https://github.com/swift-institute/swift-issue-borrowing-actor-closure).
Its ancestry was not merged. Exact repository and ref facts are recorded in
[`evidence/source-provenance.json`](evidence/source-provenance.json).
