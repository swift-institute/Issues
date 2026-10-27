# Experiment: Nested-type generic escape

<!--
---
version: 1.0.0
last_updated: 2026-04-24
status: REFUTED
tier: 2
---
-->

## Context

Follow-on to `unified-vs-two-type-box-design`. The user asked: can we
"wiggle the type system" — perhaps via hoisting of types — to allow
**`Ownership.Box<V>` as a bare CoW generic type** AND simultaneously
**`Ownership.Box.Unique<U>` as a nested ~Copyable variant** that users
can reference without supplying the outer `V`?

The structural problem: if `Ownership.Box<V>` is a generic struct, any
nested type inside it inherits `V` from the outer. To write
`Ownership.Box.Unique<U>` without specifying `V`, Swift would have to
infer or omit the outer generic at the nested access site.

This experiment tests several ways to achieve that.

## Hypotheses

| ID | Hypothesis | Approach |
|----|-----------|----------|
| H1 | Nested typealias to a non-generic type allows outer-generic omission | `struct Foo<V> { typealias Bar = Int }`, access `Foo.Bar` |
| H2 | Nested struct with its OWN generic allows outer omission | `struct Foo<V> { struct Bar<U> }`, access `Foo.Bar<X>` |
| H3 | Same as H2 but with `~Copyable` constraints | `struct Foo<V: ~Copyable> { struct Bar<U: ~Copyable> }` |
| H4 | Default generic parameters on structs allow the outer to be omitted | `struct Foo<V = Void>` |
| H5 | Hoisted typealias pattern bypasses the generic-nesting constraint | Module-level `struct __FooBar<U>`, nested `typealias Bar<U> = __FooBar<U>` |
| H6 | Module-scope typealias that ignores the outer namespace | `typealias FooBar<U> = __FooBar<U>` |

## Method

Single-file Swift package. Each variant declares the shape and attempts
the short-form access. Commented-out sections mark the outcomes — either
compile error text (verbatim) or compiler crash.

Toolchain: Apple Swift 6.3.1 (swiftlang-6.3.1.1.2)
Platform: macOS 26 (arm64)
Date: 2026-04-24

## Results

| ID | Result | Evidence |
|----|--------|----------|
| H1 | **CONFIRMED** — works | `Foo.Bar` (where `Bar = Int`) compiles and runs; outer `V` is not needed because `Bar` doesn't reference it |
| H2 | **REFUTED** | `error: generic parameter 'V' could not be inferred` / `note: explicitly specify the generic arguments to fix this issue` |
| H3 | **REFUTED** | Same error as H2; the `~Copyable` constraint makes no difference |
| H4 | Not tested (Swift struct default generics limited in 6.3); would still need to specify V explicitly at access sites per H2 evidence |
| H5 | **COMPILER CRASH** | `Stack dump… 9. While evaluating request ResolveTypeRequest(while resolving type , H5_Foo.Bar<H3_Handle>)`. Swift 6.3.1 segfaults in `applyUnboundGenericArguments` when the outer generic is omitted at a nested-typealias access. Filing upstream is warranted. |
| H6 | **CONFIRMED** — works, but doesn't solve the problem | A module-scope typealias like `typealias FooBar<U> = __FooBar<U>` works, but puts the type at module scope under a compound name, violating [API-NAME-001] / [API-NAME-002] / [API-IMPL-005] |

## What this rules out

The user's desired shape — `Ownership.Box<V>` as a bare CoW type AND
`Ownership.Box.Unique<U>` as a nested ~Copyable type accessible without
the outer `V` — is **not expressible in Swift 6.3.1**.

Any nested type under a generic outer (whether struct, enum, or typealias)
that has its own generic parameters requires specifying the outer's
generics at every access site (H2, H3). The hoisted-typealias workaround
crashes the compiler (H5). Module-scope typealiases sidestep the
constraint but violate Institute Nest.Name discipline (H6).

## Viable paths that respect both the Swift type system and Institute naming

**Path A — namespace-only Box**:
```swift
extension Ownership {
    public enum Box {}                       // namespace enum, NO generic
}

extension Ownership.Box {
    public struct Unique<V: ~Copyable>: ~Copyable { … }   // SE-0517 raw-pointer
    public struct <CoW-variant-name><V> { … }             // future CoW sibling
}
```

- `Ownership.Box.Unique<FileHandle>` ✓ compiles (no outer generic to omit)
- `Ownership.Box.<CoW><Int>` ✓ compiles
- Gives up "`Ownership.Box<V>` as bare CoW type"
- Matches [API-NAME-001a] — namespace is justified by 2+ sibling types

**Path B — sibling types at `Ownership` scope**:
```swift
extension Ownership {
    public struct Box<V> { … }                              // CoW
    public struct Unique<V: ~Copyable>: ~Copyable { … }     // raw pointer
}
```

- `Ownership.Box<Int>` ✓ bare CoW preserved
- `Ownership.Unique<FileHandle>` ✓ works
- Gives up the nesting (`.Unique` is not "inside" `.Box`)
- Exactly mirrors Apple's `Swift.Box` / `Swift.UniqueBox` split

**Path C — 0.1.0 minimum**:

Ship just `Ownership.Box.Unique<V: ~Copyable>` under Path A's namespace
shape. Defer the CoW sibling until needed, or until Apple's `Swift.Box`
ships (whichever comes first, after which we typealias).

## What this explicitly does NOT allow

| Attempt | Outcome |
|---------|---------|
| `Ownership.Box<V>` as bare CoW + `.Unique<U>` nested, accessed as `Ownership.Box.Unique<U>` | Refuted by H2/H3 (Swift requires outer `V`) |
| Hoisted typealias pattern (module-level type + nested typealias) | Crashes compiler (H5) |
| Default generic parameters to make `V` optional | Would not change the access-site behavior tested in H2 |
| `typealias BoxUnique<U> = __BoxUnique<U>` at module scope | Works (H6) but violates Institute naming |

## Promotion

Findings promoted to
`swift-ownership-primitives/Research/naming-box-ecosystem-survey.md`
v1.3.0 as empirical closure of the "hoisting rescue" line of inquiry.

## Upstream bug

H5's compiler crash is a real bug worth filing:
- Toolchain: Apple Swift 6.3.1 (swiftlang-6.3.1.1.2)
- Reproducer: this experiment, H5 short form uncommented
- Crash site: `applyUnboundGenericArguments` in `ResolveTypeRequest`
  for `H5_Foo.Bar<H3_Handle>` where `Bar` is a nested typealias to a
  hoisted generic type and the outer generic is omitted
- Severity: medium — the same pattern with explicit outer generic
  works; the crash is a type-checker diagnosis gap

## References

- `swift-ownership-primitives/Experiments/unified-vs-two-type-box-design/EXPERIMENT.md` — sibling experiment
- `swift-ownership-primitives/Research/naming-box-ecosystem-survey.md` — ecosystem context
- `/Users/coen/Developer/.claude/skills/code-surface/SKILL.md` — [API-NAME-001], [API-NAME-001a]

## Provenance

Commissioned 2026-04-24 in response to the user's follow-on question
about using type hoisting to achieve simultaneous bare-`Box` and
nested-`Box.Unique` access.
