# Members split on a defaulted invertible-protocol requirement mangle identically when their type is nested in a constrained extension

> **STATUS: STAGED — TERMINAL RECORD.** Per principal standing policy (2026-06-11),
> upstream filing does not exist as a step — this dossier is the record. The repo is
> public; pushing it is an outward act and stays principal-gated.
> Drafted 2026-06-11 from the `/issue-investigation` of catalog B7.
> The issue body below is written §A15-style to be self-contained.

---

**Classification**: Rejects-valid. Sema accepts the overload pair (and resolves call
sites correctly — `Sources/overload-resolution-control.swift` typechecks); symbol
emission then fails because both declarations mangle to the same name. **No silent
miscompile found**: every tested shape errors (see *Failure manifestations*).

**Environment**: macOS 26.2 (Darwin 25.2.0) arm64. Toolchain of record: Apple Swift
6.3.2 (`swift-6.3.2-RELEASE`, `TOOLCHAINS=org.swift.632202605101a`). Reproduces
identically on 6.2, 6.2.3, 6.3.1, 6.3.2 (swift.org and Xcode `swiftlang-6.3.2.1.108`),
and the main-branch development snapshots reporting `6.3-dev` (2026-01-07-a,
2026-01-09-a, 2026-02-05-a), `6.4-dev` (2026-03-16-a, 2026-05-07-a), and `6.5-dev`
(2026-05-12-a, 2026-05-27-a). **Not a regression; unfixed on 6.5-dev.**

## Reproducer

Single file, bare `swiftc`, no flags (`Sources/reproducer.swift`):

```swift
enum Tree<Element: ~Copyable> {}

extension Tree where Element: ~Copyable {
    enum Builder {
        static func build() {}
    }
}

extension Tree.Builder where Element: Copyable {
    static func build() {}
}
```

**Command**: `swiftc -emit-object reproducer.swift -o /tmp/repro.o`

**Observed**:

```
error: multiple definitions of symbol '$s4main4TreeOAARi_zrlE7BuilderO5buildyyFZ'
note: other definition here   (pointing at the body declaration)
```

**Expected**: builds. The pair is a legal constraint-split overload — the body member's
generic signature is `<Element: ~Copyable>` (inherited from the nesting extension), the
extension member's is `<Element: Copyable>`. `swiftc -typecheck` accepts it, and call
sites statically resolve the correct twin (`Tree<Int>.Builder.build()` → the Copyable
twin; `Tree<NC>.Builder.build()` → the body twin; control file typechecks).

## Failure manifestations (all build-time; none silent)

| layout | diagnostic |
|---|---|
| twins in one file | frontend: `multiple definitions of symbol '$s…'` with a note at the other definition |
| twins in two files, executable (`-Onone`, `-O`, `-wmo`) | SIL: `function type mismatch, declared as '<τ_0_0> (@thin Tree<τ_0_0>.Builder.Type) -> Int' but used as '<τ_0_0 where τ_0_0: ~Copyable> …'` — points at the **call site**, not either declaration |
| twins in two files, `-emit-library`, internal access | `ld: duplicate symbol 'static (extension in M):M.Tree< where A: ~Copyable>.Builder.build() -> Swift.Int'` |

The cross-file form is the one production code meets (twin lanes conventionally live in
separate files), and its diagnostic is the least actionable.

**Aggravation — the colliding "other definition" can be compiler-synthesized**: with
`public struct U: ~Copyable {}` (no written initializer) nested in the constrained
extension, declaring `public init()` in a `where Element: Copyable` extension collides
with the *implicit* `init()` (evidence §10b). Sema is constraint-aware here — the same
extension init spelled `where Element: ~Copyable` is correctly rejected as
`invalid redeclaration of synthesized 'init()'` — so Sema distinguishes precisely the
pair that the mangler then conflates.

## Investigation

**Ingredient list** (each verified independently; evidence §9, §10a):

1. A generic parent whose parameter suppresses a default (`enum Tree<Element: ~Copyable>`).
   Non-generic parent: passes (p20). Parent kind/copyability irrelevant — enum, struct,
   `~Copyable` struct all collide when ext-nested (s2/s4/s6) and all pass when
   body-nested (s1/s3/s5).
2. The member's type declared inside a **constrained extension** of the parent
   (`extension Tree where Element: ~Copyable { … }`). Nearest passing neighbors: the
   identical type nested in the parent's **primary body** (s1/s3/s5, p15–p17) and the
   identical members on a **top-level** inverse-generic type (p13/p14).
3. Twin A in the nested type's primary body (or compiler-synthesized, §10b).
4. Twin B, same signature, in an extension whose only requirement is the **defaulted
   conformance** (`where Element: Copyable`). Spelling twin B's extension
   `where Element: ~Copyable` instead: passes (F4 mangles distinctly) — though against
   a same-constraint body twin it is correctly Sema-rejected.

Member kind is irrelevant (init p01/s-sweep, instance method p22, static func
p23/reproducer). Generalizes to **`~Escapable`/`Escapable`** (same collision, inverse
index 1: `$s…TreeOAARi0_zrlE9UnboundedVAEyx_GycfC`, `Sources/escapable-analogue.swift`)
and to **depth-2 extension nesting** (p21). Not required: fields, conformances,
access modifiers, `@inlinable`, `~Copyable` on the parent or child nominal themselves,
SwiftPM, WMO, optimization flags, module boundaries.

**Mangled-form table** (demangle-verified, evidence §10; `P` parent, `U` nested type):

| declaration site of the member | rendered context | form |
|---|---|---|
| body of U, U body-nested | `P.U< where A: ~Copyable>` — inverse at **child** position | F1 |
| body of U, U **ext-nested** | `P< where A: ~Copyable>.U` — inverse at **parent** position | F2 |
| `extension U where A: Copyable` (any nesting) | `P< where A: ~Copyable>.U` | **F3 = F2 → collision** |
| `extension U where A: ~Copyable` | `(ext):(ext) P<…~Copyable>.U<…~Copyable>` | F4 |
| member-level `where A: Copyable` (SE-0267) | `P.U` — no inverse segment at all | F5 |

**Root cause** (swiftlang/swift @ `6f5d855aedf`): per the SE-0427 mangling rule,
*presence* of an invertible-protocol conformance is never mangled — only absence.
`ASTMangler::gatherGenericSignatureParts` (`lib/AST/ASTMangler.cpp`, the
"If both signatures have exactly the same requirements, **ignoring conformances for
invertible protocols**…" early-out) therefore reports the `where Element: Copyable`
extension as contributing nothing, and `ASTMangler::appendExtension`
(`lib/AST/ASTMangler.cpp:3094`, "Mangle the extension unless … the extension is
unconstrained") skips extension mangling and renders the member as a plain member of
the nominal (form F2/F3). When the nominal is itself declared inside the constrained
parent extension, the body member's real context *is* that rendering — two distinct
declarations, one symbol. The extension's `Copyable` requirement is *significant*
relative to a suppressed-default parameter (Sema treats it so; the f3 redeclaration
control proves it), but the mangler's redundancy test cannot see it.

## Workarounds (both verified, incl. depth-2 nesting and the production packages)

1. **Member-level `where Element: Copyable` clause** (SE-0267), both twins in the body
   (`Sources/workaround-member-where.swift`) — the member-where twin mangles F5,
   distinct from everything. Shipped in swift-tree-{unbounded,keyed,n}-primitives
   (`7137543`/`d116555`/`c6f9888`).
2. **Both twins extension-homed** (`Sources/workaround-extension-twins.swift`) — F4 vs
   F3 are distinct. Shipped in swift-stack-primitives (`7e4200a`). Constraint: the
   primary body must then declare no same-signature member (the Copyable-extension twin
   still *occupies* the F2/F3 symbol).

## Differentiation from the known-adjacent family

- **swiftlang/swift#89684** (house dossier
  `swift-issue-conditional-extension-typealias-name-capture`): Sema name-resolution bug
  (a conditional extension's `typealias` named after an enclosing generic parameter)
  producing a bogus rejects-valid *diagnostic at typecheck*. No mangling involvement;
  our reproducer contains no typealiases, and our pair **passes** `-typecheck`.
- **swiftlang/swift#89389** (backport request for PR #87066): the **runtime demangler**
  lacks inverse-assoc cases (`Rj`/`RJ`) → metadata SIGSEGV when *consuming* one
  well-formed symbol. Ours is the **compile-time mangler** producing the *same* symbol
  for two declarations; nothing reaches a runtime.
- **swiftlang/swift#74303 / #69615**: runtime
  `__swift_instantiateConcreteTypeFromMangledName` / `getTypeByMangledNameInContext`
  null-lookup family — runtime resolution failures of single symbols, as is catalog
  §A15 (`swift-issue-noncopyable-sametype-conditional-conformance`, a runtime
  conditional-conformance check failure). Ours never executes: the build fails.

None of the four involves two Sema-distinct declarations mapping to one mangled name.

## Production triggers (Swift Institute, [MEM-COPY-017] constructing twins)

- swift-stack-primitives `7e4200a` — `Stack<Element>.Bounded.init(capacity:)` and the
  `Stack.Builder` constructing grammar; in-file workaround notes at
  `Sources/Stack Bounded Primitive/Stack.Bounded.swift:126` and
  `Sources/Stack Primitives/Stack.Builder.swift:154`.
- swift-tree-unbounded/keyed/n-primitives `7137543`/`d116555`/`c6f9888` — the W5
  construction twins; member-level where-clauses shipped.
- **Catalog-narrative correction (for the seat)**: B7's recurrence entry states that on
  a nested-in-extension type "even EXTENSION-HOMED twins collide". Reconstruction in an
  isolated copy of swift-tree-unbounded-primitives **falsifies** this: extension-homed
  twins build clean there (six distinct constructor symbols, evidence in
  an internal investigation report); re-homing the `~Copyable` twins into the body reproduces the
  recorded collision exactly (both init pairs, demangle-matched). The demangled
  collision form F2/F3 *renders as* "(extension in …)…" for **both** definitions —
  including the body twin — which explains the "extension-level twins mangle
  identically" reading. The resolution ladder's "extension-homed twins (top-level
  generic types only)" restriction is likewise falsified (F4-vs-F3 is distinct at every
  tested nesting depth). Catalog amendment is the catalog owner's call; this investigation is read-only
  outside `/tmp` and this repository.

## Re-run checklist (revalidation on any future toolchain)

```sh
cd Sources
swiftc -typecheck reproducer.swift                      # expect: clean (Sema accepts)
swiftc -emit-object reproducer.swift -o /tmp/r.o        # expect: multiple definitions of symbol
swiftc -emit-object escapable-analogue.swift -o /tmp/e.o   # expect: same, Ri0_zrl symbol
swiftc -emit-object production-shape-init.swift -o /tmp/p.o # expect: same, init form
swiftc -emit-object workaround-member-where.swift -o /tmp/w1.o      # expect: clean
swiftc -emit-object workaround-extension-twins.swift -o /tmp/w2.o   # expect: clean
```

A toolchain on which the reproducer **builds** moves this dossier to *fixed-upstream*;
re-run the workaround files before relying on either spelling remaining necessary.

---

## House records (not part of the §A15-style body)

- Catalog: `swift-institute/Research/swift-compiler-bug-catalog.md` §B7 (entry at
  Research commit `610e697`; correction proposed above, not applied here).
- Internal report: an internal investigation report (constraint-model history,
  package-copy reconstruction record, deviation notes).
- Probes: `/tmp/b7-{matrix,versions,forms,parent-sweep,severity}/`; early anchors and
  the tree-unbounded package copy under an internal probe directory
  (placement predates the brief, disclosed in the report).
- Evidence captures: `evidence/captures.txt` (§1–§11, toolchain of record).
