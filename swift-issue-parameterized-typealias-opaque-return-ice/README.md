# Swift Issue: Parameterized-Typealias × Parameterized-Protocol Opaque-Return ICE

> **Status**: FIXED upstream in Swift 6.4-dev (nightly-main, snapshot
> `swift-DEVELOPMENT-SNAPSHOT-2026-05-12-a`). Still firing on Swift 6.3.2
> (the current Xcode default toolchain).
>
> **Upstream destination**: `swiftlang/swift`. Not yet filed (fix is already
> in 6.4-dev; verification of matching swiftlang/swift commit pending).
> **Search (2026-07-30)**: `"failed to produce diagnostic" typealias opaque`
> over swiftlang/swift issues — 0 hits for this trigger surface.
> **Eligibility: NOT YET ELIGIBLE** — no self-contained reducer exists (the
> standalone shape below compiles clean on every tested toolchain), so a
> filing could only point at the in-cohort case, which does not meet the
> general-report bar. The path to eligibility is the canary in this entry's
> `Tests/` flipping red, i.e. the standalone shape starting to reproduce.
> **Workaround on 6.3.2**: file-split — keep parser declarations in a file
> that does NOT import the test-support module exposing the parameterized
> typealias; keep test-method bodies in a sibling file that imports the
> module. See [§ Workaround](#workaround-on-632) below.

## Symptom

```
error: failed to produce diagnostic for expression; please submit a bug
report (https://swift.org/contributing/#reporting-bugs)
```

Fires during `swift test` (test-target compilation) at the `}` of
`var body: some SomeProtocol<TypeParam, Output, Error>` declarations in
files that import a module whose public surface contains either:

- a `public typealias X = Generic<Concrete>` (parameterized typealias —
  typealias to a generic instantiation), OR
- a `public extension Generic where Base == Concrete { ... }` (Base-constrained
  extension on a generic type).

Each trigger is independently sufficient. Removing both eliminates the ICE.
The library targets (`swift build`) compile cleanly — only test-target
compilation (`swift test`) reaches the ICE site.

## Origin

Surfaced 2026-05-16 in `swift-ascii-parser-primitives`'s Step 3 of the
byte-arc cohort dispatch (an internal working document item 2).
Step 3 attempted to migrate consumer references from
`ByteInput`/`ByteIterator`/`TestBytes` (top-level) to
`Parser.Test.Input`/`.Iterator`/`.Bytes` (nested), after the parent rename
committed `Parser.Test.Input = Parser_Primitives.Input.Slice<Parser.Test.Bytes>`
as a public typealias in `Parser_Primitives_Test_Support`. The 4 parser
declarations in `Declarative Parser Syntax Tests.swift` then ICE'd during
test-target compilation.

Full investigation: 11 hypotheses tested, 8 disconfirmed. See
[INVESTIGATION-ARC.md](INVESTIGATION-ARC.md) for the round-by-round record.

## Fix Status

| Toolchain | Status | Evidence |
|---|---|---|
| Swift 6.3.2 (Xcode default) | **FIRES** | 4 ICEs at lines 121/162/205/258 of `Declarative Parser Syntax Tests.swift` in the cohort |
| Swift 6.5-dev (2026-05-12-a snapshot) | **FIXED** | 0 ICE messages in `TOOLCHAINS=swift swift test`; remaining 82 errors are unrelated SE-0499 fallout in swift-pair-primitives |

## Minimal Reproducer Status

A single-file `swiftc`-buildable reproducer was attempted
([`Sources/Reproducer/Crash.swift.txt`](Sources/Reproducer/Crash.swift.txt);
converted 2026-07-30 from the loose `reproducer.swift` into the repository's
two-target layout, where `Tests/Reproducer.swift` runs it as an
out-of-process CANARY — green while the standalone shape stays clean, red if
it ever starts reproducing) but it does NOT reproduce the ICE on Swift 6.3.2.
Re-verified 2026-07-30: compiles clean on 6.3.3-RELEASE, Apple Swift 6.4, and
main-snapshot-2026-07-11 (+assertions). The shape (parameterized
protocol with 3 primary associated types, parameterized typealias for a
generic instantiation, consumer with `var body: some P<I, O, F>` opaque
return) compiles cleanly when all declarations are in one module.

A 2-module SwiftPM reproducer with simple body (returning a single P
conformer) also did not reproduce on 6.3.2. The triggering shape appears to
require additional consumer-side complexity (result builder, chained
`.map` transformations, multiple parser conformers in the same file) that
the cohort exhibits but which is harder to capture in an isolated
reproducer.

**Accepted reduction limit**: the in-cohort case is the canonical reference.
See `swift-ascii-parser-primitives/Tests/Declarative Parser Syntax Tests/Declarative Parser Syntax Tests.swift`
at baseline commit `17b97da`, with `swift-parser-primitives` at `eb01abd`
or any commit exposing `Parser.Test.Input` as a public typealias.

Reduction did empirically identify the trigger surface via 11 in-cohort
hypothesis tests (see [INVESTIGATION-ARC.md](INVESTIGATION-ARC.md)).

## Workaround on 6.3.2

**Option H — SwiftPM `exclude` the offending file** (applied, verified 2026-05-16):

The single test file that contains the ICE-triggering parser declarations
(`Declarative Parser Syntax Tests.swift`) is excluded from compilation via
the test target's `exclude:` clause. The file stays in the repo with
cohort-renamed types so it's re-enable-ready when 6.4 ships.

```swift
.testTarget(
    name: "Declarative Parser Syntax Tests",
    dependencies: [
        "ASCII Decimal Parser Primitives",
        .product(name: "Parser Primitives Test Support", package: "swift-parser-primitives"),
    ],
    exclude: ["Declarative Parser Syntax Tests.swift"]
)
```

Empirical confidence: **HIGH — directly validated 2026-05-16**. Applied in
`swift-ascii-parser-primitives` at commit `fa7b5a8`. `swift test` produces
29 tests pass / 0 ICEs. Other 3 cohort packages (parser-primitives,
parser-machine-primitives, byte-parser-primitives) pass cleanly with the
public typealias `Parser.Test.Input` retained.

**Pattern coverage redundancy**: the deferred file exercises the
`var body: some Parser.\`Protocol\`<TypeParam, …>` declarative-syntax pattern.
The same pattern is exercised redundantly by parser-primitives'
`Tests/Parser Take Primitives Tests/Parser.Builder Tests.swift`, which
passes cleanly on 6.3.2 with the same high-level shape. Deferring ascii's
file loses no unique pattern coverage.

**Workarounds tried and rejected**:

- *File-split (parser decls in one file, test bodies in another)* — earlier
  H12 claim of "validated" was WRONG (see investigation arc). Direct test:
  ICE persists in the parser-declaration file regardless of which file
  imports Test_Support.
- *Subagent's Path C-original (remove public typealias, file-private aliases
  at consumers)* — verified insufficient when applied in production-shape
  configuration. ICE persists.
- *Struct wrapper instead of parameterized typealias* — heavy consumer-side
  rewrite (~340 call sites), forwarding conformances non-trivial.
- *Separate library target for parser declarations* — violates `[MOD-DOMAIN]`
  ("a new target MUST represent a coherent semantic domain"). The deferred
  file's content has no coherent semantic identity.
- *Roll back the parent rename* — loses the `[API-NAME-002]` cleanup win
  and three commits of cohort work.

**Trigger model — underdetermined**. The apparent ingredients (parameterized
typealias in module-export scope + parameterized opaque return in same
target) are present in BOTH:

- parser-primitives `Parser.Builder Tests.swift` — passes
- ascii `Declarative Parser Syntax Tests.swift` — ICEs

So the apparent pattern is necessary but not sufficient. Some additional
structural factor in ascii's file distinguishes it; the precise minimum was
not isolated. See INVESTIGATION-ARC.md § "Final findings 2026-05-16".

## When This Workaround Can Be Removed

When the workspace migrates default toolchain to Swift 6.4+ (currently
6.4-dev only). Remove the `exclude:` clause from
`swift-ascii-parser-primitives/Package.swift`; the file's content is
already at canonical `Parser.Test.*` names. No content change required.

Revalidation step before sunset: `TOOLCHAINS=swift swift test` in
`swift-ascii-parser-primitives` (with `exclude:` removed) should produce
zero `failed to produce diagnostic` messages. Verified on snapshot
`swift-DEVELOPMENT-SNAPSHOT-2026-05-12-a` 2026-05-16.

## Cross-References

- `swift-institute/Research/swift-compiler-bug-catalog.md` § A8 (this bug)
- `INVESTIGATION-ARC.md` — round-by-round investigation, 11 hypothesis tests
- an internal working document item 2 — cohort context
- an internal working document — roadmap and D2 cost-shape correction
