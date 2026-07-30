# `swift-issue-unbound-generic-typealias-member-lookup`

**Classification:** rejects-valid / name-lookup inconsistency.

**Upstream:** NOT FILED (upstream contact is principal-gated,
swift-institute/Issues#58).

**Tracks:** swift-institute/Issues#81.

Nested member-type lookup does not look through an **unbound generic
`typealias`**. The same member resolves through every other tested base —
so the alias sugar, which carries no information the lookup needs, is what
breaks it. The rejection is specific to a base that is both **generic**
and an **alias**; a base with only one of those two properties resolves
fine (see the matrix).

## Minimal reproducer

`Sources/reproducer.swift` — 5 declarations (plus the `Bare` alias), 4
probes, no dependencies, no flags beyond `-swift-version 6`:

```swift
public struct Carrier<Substrate> {}
public protocol P {}
extension Carrier {
    public typealias Member = P
}
public typealias Alias<T> = Carrier<[T]>
public typealias Bare = Carrier

// OK: unbound generic NOMINAL base
extension Carrier.Member { func viaNominal() {} }
// OK: bound generic ALIAS base
extension Alias<Int>.Member { func viaBoundAlias() {} }
// error: 'Member' is not a member type of type 'Alias'
extension Alias.Member { func viaUnboundAlias() {} }
// OK: NON-generic alias to an unbound generic NOMINAL base
extension Bare.Member { func viaNonGenericAliasToUnboundNominal() {} }
```

```sh
swiftc -typecheck -swift-version 6 reproducer.swift
```

**Observed:**

```
reproducer.swift:31:17: error: 'Member' is not a member type of type 'reproducer.Alias'
```

**Expected:** clean compile. `Alias.Member` should resolve exactly as
`Carrier.Member` does — naming a protocol member needs no generic
arguments, which is precisely why the unbound *nominal* base is accepted.

## Inconsistency matrix

| # | Base of the member lookup | Result |
|---|---|---|
| 1 | `Carrier.Member` — unbound generic **nominal** | accepted |
| 2 | `Alias<Int>.Member` — **bound** generic alias | accepted |
| 3 | `ConcreteAlias.Member` — non-generic alias to a **concrete instantiation** (`typealias ConcreteAlias = Carrier<[Int]>`) | accepted |
| 4 | `Alias.Member` — **unbound generic alias** | **rejected** |
| 5 | `Bare.Member` — non-generic alias to an **unbound generic nominal** (`typealias Bare = Carrier`) | accepted |

Row 4 is the only rejection. Rows 1–3 were the original filing's evidence;
row 5 was added by the swift-institute/.github#122 adjudication (2026-07-30,
"W8") and sharpens the claim: it is not "an alias base breaks lookup" — a
non-generic alias to an unbound generic nominal (row 5) works fine — it is
specifically **a base that is both an alias and generic-and-unbound**
(row 4) that breaks. Row 1 (generic, not an alias) and rows 2/3/5 (an
alias, but not unbound-generic) each isolate one of the two properties and
both resolve; only their conjunction in row 4 rejects.

Secondary observations from the original reduction:

- Not specific to protocols. With an unbound generic alias base, a nested
  `struct` and a nested `typealias` member are rejected with the same
  diagnostic (`'Nested' is not a member type of type 'GBox'`).
- Not specific to `~Copyable`, suppressed associated types, or conditional
  extensions — the reducer above uses none of them. (Distinct from
  `swift-issue-conditional-extension-typealias-name-capture`, which is
  about a conditional extension's typealias *capturing* an enclosing
  generic parameter's name and emitting a bogus conformance error; here
  nothing is captured and nothing is conditional.)
- The diagnostic is also poor: it asserts the member does not exist
  rather than pointing at the unbound-alias base, and the note-free form
  gives no route to the accepted spellings.

## Toolchains

Reproduces identically on every toolchain checked; **not a regression** —
there is no known-good version.

| Toolchain | Result |
|---|---|
| Swift 6.3.3 (release) | rejected |
| Swift 6.4 (`swiftlang-6.4.0.27.1`) | rejected |
| 6.4.x nightly snapshot (2026-07-23) | rejected |
| `main` nightly snapshot (2026-07-11) | rejected |

Independently reproduced on Linux x86_64 / Swift 6.3.3 in CI (original
filing) and locally on macOS arm64 / Apple Swift 6.4 (`swiftlang-6.4.0.27.1`)
for this materialization pass (2026-07-30, `swiftc -typecheck -swift-version
6 Sources/reproducer.swift`, all five rows confirmed).

## Ecosystem impact — DECOUPLED (2026-07-30, swift-institute/.github#122)

This was originally the blocker behind
[swift-primitives/swift-set-algebra-primitives#1](https://github.com/swift-primitives/swift-set-algebra-primitives/issues/1):
the [DS-028] front-door pattern declared the public spelling of a hoisted
carrier as a **generic** `typealias` (`typealias Set<E: …> = __Set<…>`),
with a hoisted-protocol nested `typealias` (`extension __Set { public
typealias `Protocol` = __SetProtocol }`) — making the consumer spelling
`Set.`Protocol`` a row-4 lookup.

The swift-institute/.github#122 adjudication (2026-07-30) ruled this
pattern combination **unsupported at the architecture-doctrine level**
(disposition (c), not (a) wait-on-compiler): a generic front-door alias is
not a vocabulary host on any toolchain, so the ecosystem unblocks by
respelling the capability protocol as a top-level, non-underscored name
(`Membership`/`Indexable`/`Traversable`, pending naming-authority
confirmation) rather than by waiting for this issue.

**This issue is therefore decoupled from
swift-primitives/swift-set-algebra-primitives#1.** It remains open purely
as the correct, isolated upstream-track record of the compiler
inconsistency — no Institute package build depends on a fix landing.

## Harness

The bug is a **type-check rejection**, not a codegen fault, so unlike this
repository's usual exit(0)/exit(1) codegen convention, the standalone form
is a `swiftc -typecheck` exit-code probe (`Sources/Reproducer/main.swift`).
`Sources/reproducer.swift` is NOT a live SwiftPM target — row 4 fails to
typecheck by design, which would break the whole Issues package build — so
it ships as a loose file compiled OUT OF PROCESS. `Tests/Reproducer.swift`
wraps the same probe in `withKnownIssue`, unconditional (`when: { true }`,
matching the "not a regression, no known-good toolchain" status); the red
flip is the fix-detection signal.

## License

Reproducer only; repository license (Apache 2.0) applies.
