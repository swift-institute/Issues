# `swift-issue-silgencleanup-nested-closure-borrowing-noncopyable`

**Classification:** compiler crash (SIL ownership-verifier abort in the
mandatory SILGenCleanup pass).

**Upstream:** NOT FILED (upstream contact is principal-gated,
swift-institute/Issues#58).

**Tracks:** swift-institute/Issues#80.

`swift-frontend` aborts (signal 6) while compiling a closure LITERAL
(assigned to, or returned as, a value of closure type) whose body defines a
**nested local closure** that also captures the outer closure's
**`borrowing ~Copyable` parameter**:

```
Begin Error in Function: '...'
Have operand with incompatible ownership?!
Value:   %2 = mark_unresolved_non_copyable_value [no_consume_or_assign] %1 : $Parsed
User:   copy_addr %2 to [init] %6 : $*Parsed
Operand Number: 0
Conv: owned
Constraint:
<Constraint Kind:none LifetimeConstraint:NonLifetimeEnding>
End Error in Function: '...'
Found ownership error?!
4.  While running pass #0 SILModuleTransform "SILGenCleanup".
error: fatal error encountered during compilation
```

## Observed / expected

- **Observed** (`swiftc Crash.swift.txt`, Apple Swift 6.4
  `swiftlang-6.4.0.27.1`): abort as above. Fires at `-Onone` too —
  SILGenCleanup is a **mandatory** SIL pass, not an optimization, so
  `-Onone`-only testing does not clear this bug.
- **Expected**: clean compilation.

## The actual defect: a missing diagnostic, not just a crash

The identical body as a plain top-level `func` (not a closure literal) is
instead **correctly rejected** at typecheck:

```
error: 'source' cannot be captured by an escaping closure since it is a
       borrowed parameter
```

That diagnostic is exactly right — a nested closure that outlives a single,
provably-linear use of a `borrowing` parameter is an escape. The bug is
that this check **does not fire when the outer function's own parameter
list is a closure LITERAL's parameter list** rather than a `func`
declaration's. The malformed capture then reaches SILGen instead of being
rejected at the typecheck stage where the equivalent `func` shape is
caught, and the SIL ownership verifier aborts.

## Minimal reproduction

Single file, no dependencies (`Sources/Reproducer/Crash.swift.txt`), key
shape:

```swift
struct Parsed: ~Copyable, Sendable {
    let path: String
    let tree: [Int]
}

struct Rule {
    let findings: @Sendable (borrowing Parsed, Int) -> [Int]
}

let rule = Rule(
    findings: { source, severity in
        let emit: (String) -> [Int] = { basename in
            source.tree.filter { $0 == severity }
        }
        guard source.path.isEmpty == false else {
            return emit(source.path)
        }
        return emit("x")
    }
)
```

Probe:

```sh
swiftc Crash.swift.txt -o /dev/null    # aborts, SILGenCleanup, Apple Swift 6.4
```

### Empirical correction — reduced past the field report's own description

The field report characterized the trigger as "a nested local closure
capturing a borrowing `~Copyable` parameter **across early-return
branches**." Reduction (A/B, one variable removed per step, each retested)
found the early-return branching is **not load-bearing**: the crash
persists with the `guard`/second-call removed entirely, down to a single
unconditional call:

```swift
let findings: (borrowing Parsed) -> [Int] = { source in
    let emit: () -> [Int] = { source.tree }
    return emit()
}
```

Also not load-bearing (each independently removed, crash persists):
`@Sendable`, `Sendable` conformance on the borrowing type, the `Rule`
wrapper struct, and the second (`severity`) parameter.

**Genuinely load-bearing** (each A/B-confirmed — removing it clears the
crash or changes it to the correct rejection):

- The outer context must be a **closure literal** assigned to or returned
  from a closure-typed binding. The same body as a plain top-level `func`
  is correctly *rejected* at typecheck (see above) — not a crash.
- The **nested** closure must actually capture the borrowing parameter (or
  a value derived from it). A nested closure capturing nothing from the
  outer scope does not crash.
- **Two levels** of closure nesting are required. A single level (using
  the borrowing parameter's field directly in the outer closure's body,
  with no intermediate closure) does not crash.

`Crash.swift.txt` retains the `guard` branch and the `Rule`/`@Sendable`
scaffolding because they document the field-reported shape faithfully; the
reduction above is recorded here rather than reflected in a second,
narrower crash file, since the repository convention ships one crash
trigger per issue.

## Toolchains

| Toolchain | Result |
|---|---|
| Apple Swift 6.4 (`swiftlang-6.4.0.27.1`, macOS arm64) | **ABORT** — `Found ownership error?!`, pass `SILGenCleanup` |

Only the toolchain in active use has been checked so far (2026-07-30); no
other version has been probed, so this is **not yet confirmed as a
regression** (absence of a known-good toolchain is not established either
way — it is simply unchecked).

## Harness

Repository two-target convention: the trigger ships as `Crash.swift.txt`
and is compiled OUT OF PROCESS because the abort would otherwise kill the
Issues package build. `Tests/Reproducer.swift` wraps the probe in
`withKnownIssue`, unconditional (`when: { true }`) since no known-good
toolchain has been established; the red flip on any leg is the signal that
a fix (or workaround-independent resolution) reached that toolchain.
`Sources/Reproducer/main.swift` is the standalone probe (exit 1 = bug
fired, 0 = clean or inconclusive).

## Provenance (Institute discovery context)

Surfaced during implementation of API-IMPL-006
(`Lint.Rule.Structure.FileNameNestedPath`) in
swift-foundations/swift-institute-linter-rules, where the rule's
`findings: @Sendable (borrowing Lint.Source.Parsed, Diagnostic.Severity) ->
[Diagnostic.Record]` closure originally defined a nested local helper
closure directly against the borrowing `Parsed` bundle across the rule's
early-return branches (the `guard let slashIndex = ... else { return ... }`
in the shipped code marks where the nested closure was). The shipped
workaround (commit
[74f0bc9](https://github.com/swift-foundations/swift-institute-linter-rules/commit/74f0bc9))
hoists the body to a private top-level **function**
(`structureFileNameNestedPathFindings`) taking already-extracted `Copyable`
fields (`source.file`, `source.converter`, `source.tree`) instead of the
borrowing `Parsed` bundle itself — removing the nested-closure capture
entirely rather than suppressing the crash. Not yet independently
reproduced against the real `Lint.Source.Parsed`/`SourceFileSyntax` types
(task-attributed peer report only); this entry's reduced trigger
(`Sources/Reproducer/Crash.swift.txt`) is a fresh, independently-verified
minimal isolate of the mechanism described, built and confirmed on this
toolchain during this filing pass — not a byte-for-byte extraction of the
original production code (which was never committed in its crashing form).

## Workaround

Extract every field the nested closure needs into `Copyable` locals (or
route through a top-level function taking those `Copyable` fields, never
the `borrowing ~Copyable` bundle) before defining any nested closure inside
a closure literal whose own parameter is `borrowing ~Copyable`. Equivalent
to, but stronger than, replacing the nested closure with a nested `func` —
a nested `func` also avoids the crash (and is correctly typechecked either
way), but does not by itself avoid capturing the whole bundle if the
`func` still takes `borrowing Parsed` as a parameter and is invoked from
multiple sites; the field extraction is what the shipped fix actually
relies on.

## License

Reproducer only; repository license (Apache 2.0) applies.
