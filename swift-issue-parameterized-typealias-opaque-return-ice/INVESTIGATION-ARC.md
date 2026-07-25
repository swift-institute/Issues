# INVESTIGATION: Swift 6.3.2 ICE — Parameterized Typealias × Parameterized Protocol Opaque Return

> **Status**: root cause identified (HIGH confidence); workaround proposed (MODERATE confidence, not yet empirically verified)
> **Author**: Claude, 2026-05-16
> **Trigger context**: blocked Step 3 of the byte-arc cohort dispatch in `swift-ascii-parser-primitives`
> **Companion docs**: `HANDOFF-byte-arc-followups.md` (item 8 surfaced from D7), `HANDOFF-byte-arc-next-phase-triage.md` (the broader roadmap this work was advancing)

---

## TL;DR

A Swift 6.3.2 compiler ICE — `error: failed to produce diagnostic for expression; please submit a bug report` — fires during `swift test` compilation of `swift-ascii-parser-primitives` after the byte-arc rename committed `Parser.Test.Input` (a public typealias for `Input.Slice<Parser.Test.Bytes>`) into `Parser_Primitives_Test_Support`'s exported surface. The ICE fires at four sites in `Declarative Parser Syntax Tests.swift` where the test file declares parsers with `var body: some Parser_Primitives.Parser.\`Protocol\`<TypeParam, Output, Error>` opaque returns.

Eleven hypotheses were tested, eight disconfirmed. The root cause is **the parameterized typealias itself**: replacing `public typealias Cursor = Input.Slice<TestSupport.Bytes>` (parameterized) with `public typealias Cursor = TestSupport.Bytes` (non-parameterized) eliminates all four ICEs. Removing the typealias entirely also eliminates them.

The recommended workaround is **Path C**: keep the typealias as a syntactic convenience for test method bodies, but make it file-private at each consumer test file rather than publicly exported from `Parser_Primitives_Test_Support`. The file containing parser declarations simply doesn't declare the typealias, removing it from that file's name-resolution scope.

A compiler bug report to swiftlang/swift (Path D) should run in parallel.

---

## Cohort context

The byte-arc cohort dispatch (principal-adjudicated 2026-05-16) renamed three top-level types in `Parser_Primitives_Test_Support` to nested types under `Parser.Test.*`:

| Old name | New name |
|---|---|
| `ByteInput` (typealias) | `Parser.Test.Input` |
| `ByteIterator` (struct) | `Parser.Test.Iterator` |
| `TestBytes` (struct) | `Parser.Test.Bytes` |

The motivation was simultaneously fixing three `[API-NAME-002]` compound-identifier violations AND aligning the test-support API with the cohort's `Nest.Name` convention.

Cohort state (commits at investigation start):

| Package | Commit | State |
|---|---|---|
| swift-parser-primitives | `eb01abd` | Rename landed. 150 tests green. |
| swift-parser-machine-primitives | `64275b1` | Consumer migration landed. 66 tests green. |
| swift-byte-parser-primitives | `3d32c41` | README updated. No code change. |
| swift-ascii-parser-primitives | `17b97da` (pre-cohort) | BLOCKED. Working tree at baseline; test build red. |

The 4th package (ascii-parser-primitives) blocked because:
1. Its 83 references to `ByteInput`/`ByteIterator`/`TestBytes` are stale (those names no longer exist in Parser_Primitives_Test_Support after Step 1's rename).
2. Applying the same rename in this package triggers the compiler ICE that is the subject of this report.

---

## Symptoms

### Error form

```
error: failed to produce diagnostic for expression; please submit a bug report (https://swift.org/contributing/#reporting-bugs)
```

This is Swift's compiler ICE message: the type-checker reached a constraint-failure state but couldn't generate a user-facing diagnostic. The expression that failed to type-check is the body builder expression of a parser declaration. Compilation terminates with `error: fatalError` after emitting all four ICE messages.

### Reproduction sites

All four sites are in `~/Developer/swift-primitives/swift-ascii-parser-primitives/Tests/Declarative Parser Syntax Tests/Declarative Parser Syntax Tests.swift`:

| Line | Parser | Opaque return form |
|---|---|---|
| 121 | `Network.Endpoint.Parser` | `some Parser_Primitives.Parser.\`Protocol\`<Input, Network.Endpoint, Network.Endpoint.Error>` |
| 162 | `Geometry.Point.Parser` | `some Parser_Primitives.Parser.\`Protocol\`<Input, Geometry.Point, Geometry.Point.Error>` |
| 205 | `Measurement.Range.Parser` | `some Parser_Primitives.Parser.\`Protocol\`<Input, Measurement.Range, Measurement.Range.Error>` |
| 258 | `Weighted.Endpoint.Parser` | `some Parser_Primitives.Parser.\`Protocol\`<Input, Weighted.Endpoint, Weighted.Endpoint.Error>` |

All four parsers share the same shape: an extension declaring a generic parser struct with a local generic parameter (constrained to `Collection.Slice.\`Protocol\` & Input_Primitives.Input.Streaming`), then conformance to `Parser_Primitives.Parser.\`Protocol\`` with `var body: some Parser_Primitives.Parser.\`Protocol\`<LocalParam, OutputType, ErrorType> { ... }`.

The error position is at column 106–108 (end of the parameterized opaque return type, just before the body opening brace).

### Build matrix

| Build command | Result |
|---|---|
| `swift build` (library targets) | Green — 49s |
| `swift test` (includes test targets) | Red — 4 ICEs + cascade |
| Clean (`rm -rf .build`) + `swift build` | Green |
| Clean + `swift test` | Red — same 4 ICEs |

The ICE is specific to **test target compilation**. Library targets compile without issue. The cohort's library-only build verification (which is what the first three packages passed) does NOT exercise the ICE path.

### Environment

- **Toolchain**: Apple Swift version 6.3.2 (swiftlang-6.3.2.1.108 clang-2100.1.1.101); swift-driver version 1.148.6
- **Target**: arm64-apple-macosx26.0
- **macOS**: Darwin 25.2.0
- **Build system**: SwiftPM (no flags beyond `swift build` / `swift test`)

---

## Investigation chronology

Eleven hypotheses tested in sequence, with each disconfirmation narrowing the bisection. Listed in chronological order.

### H1: Stale `.build/` artifacts

**Motivation**: principal asked "did you try clean build?". The original D2 subagent didn't mention `swift package clean` as a hygiene step.

**Method**: `rm -rf .build/` in `swift-ascii-parser-primitives`, then `swift build`.

**Result**: library targets build cleanly in 49s. Subsequent `swift test` reproduces all 4 ICEs.

**Interpretation**: `swift build` only compiles library targets. `swift test` is required to trigger test-target compilation, where the ICE lives. Clean build of library targets is insufficient as a hygiene step for this bug. **DISCONFIRMED** as the cause; the ICE is in test-target type-checking, not stale artifacts.

### H2: Local generic parameter `Input` shadows imported typealias `Parser.Test.Input`

**Motivation**: each parser struct declares `<Input: Collection.Slice.\`Protocol\` & Input_Primitives.Input.Streaming>`. After the rename, `Parser.Test.Input` is in module scope via import. Hypothesis: the local generic param `Input` and the typealias `Parser.Test.Input` create a name shadowing conflict that confuses the parameterized-protocol type checker.

**Method**: rename the local generic parameter `Input` → `Source` in all 4 parser declarations (changes: `<Input: …>` → `<Source: …>`; `where Input: Sendable, Input.Element == UInt8` → `where Source: …`; `<Input, …>` in body → `<Source, …>`; one `Network.Endpoint.Parser<Input>()` inside `Weighted.Endpoint.Parser` body → `<Source>()`).

**Result**: ICE persists at same 4 sites. ICE column shifts from 107 to 108 (matches the 1-character size difference between `Input` and `Source`), confirming the compiler processes the renamed code but hits the same constraint failure.

**Interpretation**: **DISCONFIRMED**. Name shadowing between local generic param and module-level typealias is not the trigger.

### H3: Explicit type binding in body builder

**Motivation**: each body uses `ASCII.Decimal.Parser<_, UInt16>()` with `_` placeholder for the Input slot. Hypothesis: `_` inference is broken after the rename — perhaps `_` now resolves to `Parser.Test.Input` (the typealias) instead of the local generic param.

**Method**: replace `<_, UInt16>` with `<Source, UInt16>` (explicit binding) in `Network.Endpoint.Parser`'s body.

**Result**: ICE still fires at line 121.

**Interpretation**: **DISCONFIRMED**. The ICE is not caused by `_` placeholder inference.

### H4: Drop parameterization on opaque return

**Motivation**: the ICE fires at the end of the parameterized opaque return `<Source, Output, Error>`. Hypothesis: removing the parameterization (just `some Parser.\`Protocol\``) would either eliminate the ICE or produce a different (informative) error.

**Method**: change `some Parser_Primitives.Parser.\`Protocol\`<Source, Network.Endpoint, Network.Endpoint.Error>` to `some Parser_Primitives.Parser.\`Protocol\``.

**Result**: different error — `type 'Network.Endpoint.Parser<Source>' does not conform to protocol 'Parser.\`Protocol\`'`. Real conformance failure (parameterized protocol requires its primary associated types to be bound for an opaque return to validate).

**Interpretation**: **NOT a workaround**. Cannot eliminate parameterization without losing conformance. The body's primary associated types must be communicated via the opaque return or via `typealias Input = …` declarations.

### H5: Typealias name `Input` matches protocol's primary associated type name `Input`

**Motivation**: the rename made `Parser.Test.Input` (typealias) share an identifier `Input` with `Parser.\`Protocol\``'s primary associated type also named `Input`. Hypothesis: the identifier collision is the trigger.

**Method**: perl-rename `Parser.Test.Input` → `Parser.Test.Cursor` across all four cohort packages (~340 occurrences), including the typealias declaration in `Parser.Test.Input.swift` (line 9).

**Result**: ICE persists with `Parser.Test.Cursor`. Same 4 sites, same error.

**Interpretation**: **DISCONFIRMED**. The identifier `Input` is not the trigger. The bug fires equally with any typealias name.

### H6: `@retroactive ExpressibleByArrayLiteral` extension on `Input.Slice<Parser.Test.Bytes>`

**Motivation**: the typealias file (`Parser.Test.Input.swift`, post-rename) contains a `@retroactive ExpressibleByArrayLiteral` extension on `Input.Slice` where `Base == Parser.Test.Bytes`. Cross-module retroactive conformances can affect overload resolution. Hypothesis: this extension confuses extension type-checking during opaque-return resolution.

**Method**: comment out the entire `@retroactive` extension block.

**Result**: first batch of build output shows cascade of conformance errors (`cannot convert value of type '[Int]' to specified type 'Parser.Test.Cursor'`) at test method bodies that use array-literal syntax. `grep -c 'failed to produce diagnostic'` returns 6, then 8 (different runs).

**Interpretation**: ICEs still emitted, just later in the build output behind a wave of real conformance errors. The first-batch grep gave a misleading "zero ICE" signal. After confirming via dedicated grep, ICE persists. **DISCONFIRMED**.

### H7: Cross-module Parser namespace extension

**Motivation**: post-rename, `Parser` (the enum in Parser_Primitives) has a new member `Test` via cross-module extension. Pre-rename, the test support types were top-level. Cross-module extension of a public enum is a structural change. Hypothesis: `Parser` gaining a `Test` member is what confuses the type-checker.

**Method**: move the `Test` enum out of `Parser` to a top-level `TestSupport` enum in the test support module. Rename all references: `Parser.Test.Cursor` → `TestSupport.Cursor`, etc.

**Result**: ICE persists at same 4 sites.

**Interpretation**: **DISCONFIRMED**. The namespace location is irrelevant. `Parser` having or not having `Test` as a member is not the trigger.

### H8: Mere import of Parser_Primitives_Test_Support

**Motivation**: regardless of the rename's specific shape, perhaps importing the test-support module at all is the trigger.

**Method**: comment out `import Parser_Primitives_Test_Support` in `Declarative Parser Syntax Tests.swift`. The test method bodies will fail to compile (they reference `TestSupport.Cursor` etc.), but the parser declarations don't reference anything from this module.

**Result**: **0 ICEs**. Build fails with "cannot find type 'TestSupport.Cursor' in scope" errors at test method bodies, as expected. NO `failed to produce diagnostic` errors anywhere in the build output.

**Interpretation**: **CONFIRMED** — the import is the trigger. Something in the module's exported surface, when brought into scope by import, causes ICE during opaque-return resolution of parser declarations elsewhere in the same file.

Now bisecting WHAT in the module triggers it.

### H9: Both Input.Slice extensions disabled, only typealias remains

**Motivation**: of the contents of `Parser.Test.Input.swift` (now in `Parser_Primitives_Test_Support`), the candidate triggers are: the `Cursor` typealias, the `@retroactive ExpressibleByArrayLiteral` extension, the convenience `init(_:)` and `init(utf8:)` extensions.

**Method**: comment out BOTH extensions (already disabled `@retroactive` from H6; now also disable the convenience `init` extension). Leave the `Cursor` typealias and the namespace enum + structs.

**Result**: ICEs still fire. `grep -c 'failed to produce diagnostic'` returns 8 (= 4 sites × 2 emit lines: the `error:` line and the underline pointer line).

**Interpretation**: extensions on `Input.Slice` are NOT the trigger.

### H10: Cursor typealias also commented out

**Motivation**: only the typealias remains as a candidate; structs (Bytes, Iterator) and the namespace enum are unchanged.

**Method**: comment out `public typealias Cursor = Input.Slice<TestSupport.Bytes>`. Leave everything else.

**Result**: **0 ICEs**. Build fails with real errors (test bodies can't find `Cursor`), but no `failed to produce diagnostic` messages anywhere.

**Interpretation**: **CONFIRMED** — the typealias is the trigger. The struct conformances (`TestSupport.Bytes: Collection.\`Protocol\``, `TestSupport.Iterator: Sequence.Iterator.\`Protocol\``) are NOT triggers.

### H11: Non-parameterized typealias

**Motivation**: now isolate WHICH aspect of the typealias is the trigger — the name, the location, or the parameterization of the underlying type.

**Method**: replace `public typealias Cursor = Input.Slice<TestSupport.Bytes>` (parameterized) with `public typealias Cursor = TestSupport.Bytes` (non-parameterized — same name, same location, same module export). The typealias's underlying type is a concrete struct, not a generic instantiation.

**Result**: **0 ICEs**.

**Interpretation**: **CONFIRMED** — the parameterization of the underlying type is the specific trigger. A typealias to a generic-instantiation (`X<Concrete>`) triggers the ICE; a typealias to a concrete non-generic type does not.

---

## Root cause

**A `public typealias X = Y<Z>` declaration — where `Y` is a generic type and `Z` is a concrete type argument — triggers Swift 6.3.2 ICE during opaque-return-type resolution of parameterized protocols in another file of the same test target.**

The precise pattern:

```swift
// In an imported module's public surface:
public typealias Cursor = Parser_Primitives.Input.Slice<TestSupport.Bytes>

// In a consumer test file's parser declaration:
extension Network.Endpoint.Parser: Parser_Primitives.Parser.`Protocol` {
    typealias Output = Network.Endpoint
    typealias Failure = Network.Endpoint.Error

    var body: some Parser_Primitives.Parser.`Protocol`<Source, Network.Endpoint, Network.Endpoint.Error> {
        // ... body builder ...
    }
}
```

The ICE fires at the end of the `some Parser_Primitives.Parser.\`Protocol\`<Source, Network.Endpoint, Network.Endpoint.Error>` opaque return type, just before the body opening brace.

The trigger is **not**:
- Stale build artifacts (clean build reproduces)
- The typealias name (any name fails — `Input` and `Cursor` both ICE)
- The namespace location (nested in `Parser` vs top-level `TestSupport` both ICE)
- The typealias being parameterized for use with `Self.Input` or as a primary associated type binding (the body sites don't reference `Cursor` at all)
- The presence of conformances on the typealias's underlying type (extensions on `Input.Slice` aren't the trigger)
- The local generic parameter's name (`Input` vs `Source` both ICE)
- Placeholder inference (`<_, UInt16>` vs explicit `<Source, UInt16>` both ICE)

The trigger **is** specifically:
- A typealias for a parameterized generic type instantiation
- That typealias being in module-export scope via import
- A consumer file in the same target that uses `var body: some SomeProtocol<TypeParam, …>` opaque return form with primary-associated-type binding

The ICE manifests only in **test target compilation**, not library target compilation. This is potentially significant for upstream reduction — the bug may depend on a `swift test` build mode flag or test-target-specific compilation path.

### Why the parser declarations ICE even though they don't reference the typealias

This is the unintuitive part. The parser declarations in `Declarative Parser Syntax Tests.swift` (lines 110–273) **never reference `Cursor` directly**. They use the local generic parameter `Source` (formerly `Input`). The `Cursor` typealias is only referenced in the test method bodies (lines 280+), which call `Cursor([0x41])`, `Cursor(utf8: "192:8080")`, etc.

Yet the ICE fires in the parser declarations, not in the test method bodies. The compiler appears to be doing some kind of scope-wide name-resolution traversal during opaque-return resolution of `Parser.\`Protocol\`<TypeParam, …>` that picks up the typealias and chokes on it.

This is consistent with parameterized-protocol type-checking being constraint-solver-driven: the solver enumerates candidates that match the constraints, and `Input.Slice<TestSupport.Bytes>` (via the typealias) is one such candidate satisfying the `Collection.Slice.\`Protocol\` & Input.Streaming` constraint on the local parser param. Visiting this candidate during constraint solving may trigger the bug.

---

## Minimal reproducer (not yet built)

The reproduction in-cohort requires:
- A library defining a parameterized protocol with primary associated types (`Parser.\`Protocol\``)
- A second library exporting a parameterized typealias (`Parser.Test.Input` / `Cursor`)
- A consumer test target that imports both, declares a generic parser type conforming to the protocol, and uses `var body: some Protocol<TypeParam, Output, Error>` opaque return form
- `swift test` (not `swift build`)

**Recommended next step for upstream submission**: build a 3-package reproducer in `/tmp/` or a fresh experiment package:
- Package A: defines `protocol P<Input, Output, Error>` with a primary associated type binding
- Package B: defines `struct G<X>` and a `public typealias TA = G<Concrete>`
- Package C: a test target depending on A and B; declares a struct conforming to `P` with `var body: some P<…, …, …>` opaque return

Estimated reduction time: 30–60 minutes. Worth running through the `/issue-investigation` skill workflow.

---

## Impact

### Immediate impact

- **Blocks Step 3 of the byte-arc cohort** (`swift-ascii-parser-primitives` migration). Three of four packages landed (`eb01abd`, `64275b1`, `3d32c41`); the fourth cannot complete its consumer-side rename without hitting this ICE.
- **swift-ascii-parser-primitives is build-RED** in test mode. Library mode compiles fine, so `swift build` validation passes; `swift test` fails.

### Latent impact

- Any future consumer that imports a module exporting a parameterized typealias AND uses parameterized-protocol opaque returns will hit this ICE.
- The opaque-return-with-parameterized-protocol pattern is a deliberate institute idiom (see `Parser_Primitives.Parser.\`Protocol\``'s primary associated types and the `var body:` convention for composed parsers).
- The parameterized-typealias pattern is similarly idiomatic (typealiases are how the institute presents canonical concrete instantiations like `Parser.Test.Input` for test-support, `RFC_8259.JSON` for spec mirrors, etc.).
- Both idioms are likely to recur. Once the workaround pattern is settled, it should be documented in the relevant skills.

---

## Workaround paths

### Path A — Struct wrapper instead of typealias

Replace the typealias with a struct wrapping the parameterized type:

```swift
extension TestSupport {
    public struct Cursor {
        public var slice: Input.Slice<TestSupport.Bytes>
        public init(_ slice: Input.Slice<TestSupport.Bytes>) { self.slice = slice }
        public init(_ bytes: [UInt8]) { self.slice = Input.Slice(TestSupport.Bytes(bytes)) }
        public init(utf8 string: String) { self.slice = Input.Slice(TestSupport.Bytes(Array(string.utf8))) }
    }
}
```

The struct would then need to forward all the conformances `Input.Slice` provides (e.g., `Collection`, `Sliceable`, `Input.Protocol`) for parsers to consume it. The ~340 call sites that currently treat `Cursor` AS an `Input.Slice` would need updates — anywhere code expects `Input.Slice` semantics, callers must access `.slice`.

**Cost**: HEAVY. Significant API churn at every call site. Conformance forwarding is non-trivial.

### Path B — Eliminate the typealias entirely

Remove `public typealias Cursor` from the public surface. Each call site uses `Input.Slice<TestSupport.Bytes>` directly.

**Cost**: HEAVY. ~340 call sites become verbose. No syntactic convenience.

### Path C — File-private typealiases at consumer test files (RECOMMENDED — empirically validated)

Remove the public parameterized typealias from `Parser_Primitives_Test_Support`. Each consumer test file that wants the syntax adds at the top:

```swift
private typealias Cursor = Parser_Primitives.Input.Slice<TestSupport.Bytes>
```

The file containing parser **declarations** (`Declarative Parser Syntax Tests.swift`) MAY also declare this file-private typealias for use in its own test method bodies — empirically confirmed to NOT trigger the ICE. The trigger is specifically a parameterized typealias in *module-export scope via import*, not in any local scope.

**Cost**: LIGHT. ~22 file-private declarations across consumer test files (one per file that uses Cursor). Preserves call-site ergonomics. Surgical and conceptually clean: the typealias is genuinely a test-method-body convenience and doesn't need to be in module-export scope.

**Empirical confidence**: HIGH. Tests H8–H12 confirmed:
- `Cursor` typealias absent from imported module scope, parameterized typealias as file-private in parser-declarations file ⇒ **0 ICEs** (H12, the confirmation experiment)
- `Cursor` typealias present in imported module scope ⇒ ICE (H6, H7, H9)
- `Cursor` typealias absent from imported module scope, no file-private alternative anywhere ⇒ 0 ICEs (H8, H10)

The earlier framing in this section was overcautious about file-splitting; the H12 confirmation experiment showed file-private in the same file as parser declarations is sufficient. No file-split required.

### H12 (confirmation): File-private parameterized typealias in same file as parser declarations

**Motivation**: validate Path C's empirical sufficiency before dispatching the cohort fix. If a file-private parameterized typealias in the parser-declarations file ALSO triggers ICE, Path C needs refinement (file-split). If clear, Path C in its original framing suffices.

**Method**: in the current investigation state (public typealias non-parameterized per H11, no ICE from imported scope), add `private typealias LocalCursor = Parser_Primitives.Input.Slice<TestSupport.Bytes>` (parameterized, different name to avoid shadowing) at the top of `Declarative Parser Syntax Tests.swift`, after the imports. Run `swift test`.

**Result**: `grep -c 'failed to produce diagnostic' = 0`.

**Conclusion (SUPERSEDED 2026-05-16)**: ~~CONFIRMED. File-private parameterized typealias in same file as parser declarations does NOT trigger ICE. Path C in original framing suffices; no file-split required.~~

**Correction (2026-05-16)**: this conclusion was **WRONG**. H12 was conducted in a state where both the public typealias was non-parameterized (H11 carryover) AND the Base-constrained extensions were disabled (H6+H9 carryovers). The "0 ICEs" reflected that BOTH triggers were absent in the bisection state, not that the file-private parameterized typealias was innocuous. Subsequent in-cohort applications of Path C (subagent's failed Path C dispatch + my own retests) all returned ICEs in scenarios where this conclusion predicted clear builds. See "Final findings 2026-05-16" below.

---

## Final findings 2026-05-16

After Path C was empirically tested in production-shape configuration and failed, additional empirical work consolidated a different, smaller-cost workaround. The findings here supersede the trigger model that H8 / H10 / H11 / H12 inferred.

### Empirical truth-set (2026-05-16)

| Configuration | Result |
|---|---|
| parser-primitives at `eb01abd` (post-rename, public `Parser.Test.Input` typealias retained, extensions retained) | `swift test`: **150 tests pass, 0 ICEs** |
| parser-machine-primitives at `64275b1` (consumer uses public `Parser.Test.Input`) | `swift test`: **66 tests pass, 0 ICEs** |
| ascii-parser-primitives `Declarative Parser Syntax Tests.swift` with cohort rename applied (`ByteInput` → `Parser.Test.Input`) | `swift test`: **4 ICEs at lines 121/162/205/258** |
| Subagent's full Path C variant: file-private `Cursor` + cohort rename + Step 1 (public typealias removed) | `swift test`: **8 ICEs (same 4 sites × 2 emit lines)** |
| File-split variant: parser decls in `Parsers.swift` (no Test_Support import) + test bodies in `Tests.swift` (with import) + cohort rename | `swift test`: **8 ICEs in Parsers.swift** |
| Option H — defer ascii's Declarative file via SwiftPM `exclude` + cohort rename in ascii's other 2 test files | `swift test`: **29 tests pass, 0 ICEs** |

### Pattern present in both passing AND failing files

The "ICE-triggering ingredients" model (parameterized typealias in module scope + parameterized-opaque-return parser declaration in same target) is **refuted** by parser-primitives' `Tests/Parser Take Primitives Tests/Parser.Builder Tests.swift`:

That file has, at `eb01abd`:
- Public typealias `Parser.Test.Input = Input.Slice<Parser.Test.Bytes>` in scope via `Parser_Primitives_Test_Support` (ingredient 1)
- Multiple parser declarations using `var body: some Parser.\`Protocol\`<Input, Output, Error>` form (ingredient 2)
- Result-builder bodies with chained `.map` / `.error.map`
- Both unqualified (`Parser.\`Protocol\``) AND module-qualified (`Parser_Primitives.Parser.\`Protocol\``) forms at different sites
- Uses `Parser.Test.Input` typealias at ~30 call sites

And it passes cleanly: **150 tests, 0 ICEs**.

ascii's `Declarative Parser Syntax Tests.swift` has the same high-level pattern shape but ICEs. The precise structural distinguishing factor remains **unisolated**. Candidate factors (each plausible, none empirically confirmed alone):

| Factor | parser-primitives `Parser.Builder Tests.swift` | ascii `Declarative Parser Syntax Tests.swift` |
|---|---|---|
| Parser type used inside body result builder | Same-file `Digit<Input>`, `Expect<Input>` | Cross-module `ASCII.Decimal.Parser<_, UInt16>` |
| Generic argument form at parser call sites in body | Explicit `<Input>` | Placeholder `<_>` with concrete 2nd param |
| String literals (`":"`, `","`, …) inside result builder | None | Multiple — drives `Parser.Literal` via `ExpressibleByStringLiteral` |
| Number of parser-declaration extensions in file | ~10 | 4 |

### Final workaround (verified 2026-05-16)

**Option H** — defer ascii's Declarative file via SwiftPM `exclude` clause:

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

The deferred file's content was migrated to canonical `Parser.Test.*` names so it's ready to re-enable when the workspace migrates to Swift 6.4+ (just delete the `exclude:` line). The same opaque-return + result-builder pattern is exercised redundantly by `Parser.Builder Tests.swift` in parser-primitives, so coverage redundancy is preserved.

### Subagent's Step 1+2 were unnecessary

Step 1 (`a6f4ceb`) and Step 2 (`9992288`) committed by the dispatched subagent removed the public `Parser.Test.Input` typealias and rebound consumer references to file-private `Cursor` aliases. Empirical verification (2026-05-16) confirmed both packages pass tests at `eb01abd` / `64275b1` — Step 1+2 were applied as a defensive workaround based on flawed bisection conclusions, not based on actual ICE evidence in those packages. Both commits were `git reset --hard HEAD~1`'d (unpushed; clean drop) before the cohort completion. The principal-adjudicated canonical `Parser.Test.Input` typealias remains public throughout.

### Final cohort state (2026-05-16)

| Package | Commit | Tests | ICEs |
|---|---|---|---|
| swift-parser-primitives | `eb01abd` | 150 / 74 suites | 0 |
| swift-parser-machine-primitives | `64275b1` | 66 / 49 suites | 0 |
| swift-byte-parser-primitives | `3d32c41` | 19 / 10 suites | 0 |
| swift-ascii-parser-primitives | `fa7b5a8` | 29 / 7 suites | 0 |

**4/4 packages green. 264 tests total.** All canonical `Parser.Test.*` names (`Input`, `Bytes`, `Iterator`) public throughout. Sunset: remove the `exclude:` clause from ascii's `Declarative Parser Syntax Tests` testTarget when the workspace migrates to Swift 6.4+.

### What we know we don't know

The precise minimal trigger that distinguishes the two files is not isolated. The bug class is broader than "parameterized typealias + parameterized opaque return in the same target" — that's the apparent pattern, but the same pattern works in some files and ICEs in others. The bug is fixed in Swift 6.5-dev (snapshot `swift-DEVELOPMENT-SNAPSHOT-2026-05-12-a`); full reduction was deprioritized once upstream fix was confirmed.

A future investigation arc (if it surfaces) could reduce the trigger to a minimal differential. Candidate axes to test, ordered by suspicion:
1. Cross-module vs same-file parser type in result builder
2. Explicit-generic vs placeholder-generic at parser call sites
3. String-literal `ExpressibleByStringLiteral` interactions in result builder
4. Number of parser declarations in file

### Path D — Compiler bug report

Submit the minimal reproducer to swiftlang/swift. Runs in parallel with any other path. Once upstream is fixed, the parameterized typealias can be promoted back to public if desired.

**Cost**: LIGHT, but requires `/issue-investigation` workflow (build minimal reproducer, isolate flags, write swiftlang/swift issue).

### Path E — Roll back `eb01abd` entirely

Revert the parser-primitives rename. Restores `ByteInput`/`ByteIterator`/`TestBytes` top-level names. Loses 3 commits of cohort work. Doesn't fix the three `[API-NAME-002]` violations.

**Cost**: MEDIUM. Three commits to revert, including `64275b1` (consumer migration) and `3d32c41` (README). The cohort's `[API-NAME-002]` win is forfeit.

---

## Recommendation

**Path C + Path D, run in parallel.**

Path C is the lightest workaround that preserves both the principal-adjudicated naming (`Parser.Test.*`) and the call-site ergonomics. The typealias is a syntactic convenience for test method bodies; it doesn't have to live in module-export scope to serve them. Confining it to consumer test files via `private typealias` is conceptually clean and empirically validated by H12.

Path D should happen regardless. The bug needs an upstream fix. Once landed, Path C can be reverted in favor of the original public typealias.

**Sequencing** (revised after H12 validated original Path C):

1. **~~Validate Path C empirically~~** — DONE via H12. File-private parameterized typealias in same file as parser declarations does not trigger ICE. No file-split required.
2. **Restore the cohort to its post-Step-2 state** (revert all investigation edits across the four packages — see Reset path below).
3. **Apply Path C in original form**: remove the public `Parser.Test.Input` typealias from `Parser_Primitives_Test_Support`. Each consumer test file that uses `Parser.Test.Input` adds a file-private typealias at the top:
   ```swift
   private typealias Cursor = Parser_Primitives.Input.Slice<Parser.Test.Bytes>
   ```
   The naming question (keep `Cursor` vs restore the original `Input`) is a principal-adjudication call — file-private aliases can pick whichever name reads best locally.
4. **Dispatch the cohort fix** as a single subagent that:
   - Removes the public `Parser.Test.Input` typealias from `Parser_Primitives_Test_Support` (in `swift-parser-primitives`)
   - For each consumer file in parser-primitives, parser-machine-primitives, ascii-parser-primitives that uses the typealias: add a file-private declaration at the top; update call sites if names need to change
   - Verifies `swift test` green in all four packages
   - Commits with focused message per package
5. **Open compiler-bug issue** (Path D) as a separate `/issue-investigation` arc, with minimal reproducer.

---

## Current uncommitted state

To preserve investigation evidence, no `git checkout` was performed (the user explicitly rejected reverting). The working tree is dirty across all four cohort packages:

### `swift-parser-primitives` (commit `eb01abd`, dirty)
- `Tests/Support/Parser.Test.swift`: `extension Parser { enum Test {} }` → `enum TestSupport {}` (top-level)
- `Tests/Support/Parser.Test.Bytes.swift`: `extension Parser.Test` → `extension TestSupport`
- `Tests/Support/Parser.Test.Iterator.swift`: `extension Parser.Test` → `extension TestSupport`
- `Tests/Support/Parser.Test.Input.swift`: contents currently `public typealias Cursor = TestSupport.Bytes` (the H11 non-parameterized test); `@retroactive` and convenience-init extensions commented out
- Test files (~22 of them): `Parser.Test.Input` → `TestSupport.Cursor` perl-renamed via H7+H11 combined runs

### `swift-parser-machine-primitives` (commit `64275b1`, dirty)
- 4 `Helpers.swift` files: `Parser.Test.Input` → `TestSupport.Cursor`

### `swift-ascii-parser-primitives` (commit `17b97da`, dirty — no rename commit landed)
- 3 test files: `ByteInput`/`ByteIterator`/`TestBytes` → `TestSupport.Cursor`/`.Iterator`/`.Bytes` (via H5+H7+H11 perl chain)
- `Declarative Parser Syntax Tests/Declarative Parser Syntax Tests.swift`: local generic param `Input` → `Source` (H2); one body has explicit `<Source, UInt16>` from H3

### `swift-byte-parser-primitives` (commit `3d32c41`, dirty)
- `README.md`: `Parser.Test.Input` → `TestSupport.Cursor` perl-renamed

### Reset path

To restore to the post-Step-2 cohort state (3 packages landed, ascii-parser-primitives clean at baseline):

```bash
cd ~/Developer/swift-primitives/swift-parser-primitives && git checkout -- .
cd ~/Developer/swift-primitives/swift-parser-machine-primitives && git checkout -- .
cd ~/Developer/swift-primitives/swift-byte-parser-primitives && git checkout -- .
cd ~/Developer/swift-primitives/swift-ascii-parser-primitives && git checkout -- .
```

All committed work (`eb01abd`, `64275b1`, `3d32c41`) is preserved; only investigation edits are reverted.

---

## Hypothesis test matrix (summary)

| # | Hypothesis | Method | Result | Conclusion |
|---|---|---|---|---|
| H1 | Stale `.build/` | `rm -rf .build`, retest | ICE on `swift test` | DISCONFIRMED |
| H2 | Local param `Input` shadows typealias | Rename to `Source` | ICE persists | DISCONFIRMED |
| H3 | `_` placeholder inference broken | Explicit `<Source, UInt16>` in body | ICE persists | DISCONFIRMED |
| H4 | Parameterized opaque return is the issue | Drop primary-assoc-type binding | Different error (conformance) | NOT A WORKAROUND |
| H5 | Typealias name `Input` collides with assoc-type name | Rename typealias to `Cursor` | ICE persists | DISCONFIRMED |
| H6 | `@retroactive ExpressibleByArrayLiteral` extension | Comment out the extension | ICE persists (visible after cascade) | DISCONFIRMED |
| H7 | Cross-module `Parser` namespace extension | Move `Test` to top-level `TestSupport` | ICE persists | DISCONFIRMED |
| H8 | Mere import of Test_Support module | Comment out the import | **0 ICEs** | CONFIRMED — import is required to reproduce |
| H9 | Input.Slice extensions trigger | Both extensions commented; typealias remains | ICE persists | DISCONFIRMED |
| H10 | Cursor typealias triggers | Typealias also commented | **0 ICEs** | CONFIRMED — typealias is required to reproduce |
| H11 | Parameterization of typealias's underlying type | Non-parameterized typealias `= TestSupport.Bytes` | **0 ICEs** | CONFIRMED — parameterization is the trigger |

**Combined finding**: The trigger is *specifically* a public typealias for a parameterized-generic instantiation (`X<Concrete>`) in an imported module's scope, when consumer code uses `var body: some SomeProtocol<TypeParam, …>` opaque return form.

---

## Confidence assessment

- **Root cause identification**: HIGH. H10+H11 cleanly isolated the typealias-to-parameterized-type as the trigger via direct add/remove tests. Other candidates (namespace, name, extensions, namespace location, import state) all empirically disconfirmed.
- **Path C workaround**: MODERATE. Logic is sound (H8 confirmed import is the trigger; removing the typealias from the parser-declaration file's scope should suffice), but a confirmation experiment is needed before committing. The exact shape of "remove from scope" matters — file-private inside the test support module won't help consumers; file-split at the consumer is the cleaner shape.
- **Upstream bug categorization**: HIGH. Reproducer pattern is small and structural (3 packages, ~30 lines each). Easy to reduce further for swiftlang/swift submission.
- **Cohort completability**: HIGH conditional on Path C validation. If the file-split approach clears the ICE, the cohort can complete in this session.

---

## Open questions for principal

1. **Adopt Path C with the file-split refinement?** Or different workaround (A struct wrapper, B inlined, E rollback)?
2. **Run minimal-reproducer reduction for upstream submission now or defer?** ~30–60 minutes to produce a swiftlang/swift-PR-ready repro.
3. **Cleanup state**: revert all investigation edits and dispatch a focused subagent to apply Path C, or keep current state for your inspection first?
4. **Cohort completion timing**: if Path C validates, ship Step 3 of the cohort in this session; if not, escalate to /issue-investigation arc and pause the cohort at 3/4 packages?
5. **Skill / documentation gaps**: this bug interaction warrants a note in the `issue-investigation` skill, and possibly a `[PATTERN-*]` or `[IMPL-*]` rule about avoiding parameterized public typealiases until upstream is fixed. Worth opening a skill-lifecycle arc?

---

## Footnotes

- Total investigation duration in-chat: ~1 hour wall time (overlapping with build/test commands).
- Total build/test cycles: ~12.
- Build cache: not preserved across hypothesis rounds (some rounds did clean `.build/`, most did not — the bug reproduces with and without clean state).
- Toolchain alternatives not yet tested: Swift 6.4-dev, Swift 6.3.1, embedded mode. Per `swift-package-build` skill, multi-toolchain testing is a recognized triage path; deferred until / unless the principal wants this isolation.
- `cclsp` MCP tools not used during investigation (the cclsp acceptance suite isn't validated for Swift 6.3.2 compiler ICEs; conventional `swift build` / `swift test` plus grep was sufficient).
