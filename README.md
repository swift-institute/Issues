# Issues

Minimal Swift packages reproducing toolchain and compiler bugs encountered
while developing the [Swift Institute](https://swift-institute.org)
ecosystem — the institute's own defect records: each entry carries the
reduced reproducer, evidence captures, duplicate differentiation against
upstream reports, and the verified workaround the ecosystem ships.

## Overview

Each `swift-issue-*/` subdirectory holds one minimum reproducer of a
single Swift toolchain or compiler bug. Reproducers are reduced to the
minimum trigger: no package-internal types, no transitive dependencies,
no special swiftSettings beyond what the bug requires.

When a bug catalog entry says "this code miscompiles on Linux release,"
the issue reproducer proves it — runnable from `swift test` (or directly
via the standalone executable) and verified by CI on every supported
platform.

The companion research repository is at
[swift-institute/Research](https://github.com/swift-institute/Research).
The companion experiments repository is at
[swift-institute/Experiments](https://github.com/swift-institute/Experiments).

## Per-Issue Convention

Every `swift-issue-*/` subdirectory follows this steady-state layout.
The convention was established by
`swift-issue-pointer-arithmetic-linux-miscompile/` and applies to every
subsequent issue.

```
swift-issue-<topic>/
├── README.md                  — bug summary, trigger characterization, workaround
├── INVESTIGATION-ARC.md       — (optional) multi-round convergence record
├── ISSUE-<NNNN>-COMMENT.md    — (optional, historical) extended characterization notes from earlier entries
├── Tests/
│   └── Reproducer.swift       — Swift Testing harness, withKnownIssue flip semantics
├── Sources/
│   └── Reproducer/
│       └── main.swift         — standalone exit-code reproducer
└── evidence/                  — (optional) bisection artifacts from investigation
    ├── README.md
    └── …
```

Each issue declares exactly two SwiftPM targets in the root
`Package.swift`:

```swift
.testTarget(
    name: "swift-issue-<topic>-Tests",
    path: "swift-issue-<topic>/Tests"
),
.executableTarget(
    name: "swift-issue-<topic>-Repro",
    path: "swift-issue-<topic>/Sources/Reproducer"
),
```

Target names match the issue directory so `swift test --filter
<issue-dir-underscored>` selects exactly this issue's tests via substring
match on the module-name prefix (SwiftPM converts hyphenated target
names to underscored module identifiers).

### Two harnesses per issue

- **`Tests/Reproducer.swift`** — Swift Testing. Wraps the bug's
  minimum trigger in `withKnownIssue("swiftlang/swift#NNNN",
  when: { <platform-precondition> })`. **Green** while the bug
  fires on the configured platforms (current toolchain state);
  flips **red** the moment the upstream fix lands and the bug
  stops firing. The red flip IS the fix-detection signal — captured
  by the weekly nightly CI cron.
- **`Sources/Reproducer/main.swift`** — standalone executable.
  `exit(0)` on no-bug-fired, `exit(1)` on bug-fired. Covers codegen
  surfaces that the SwiftPM test runner may mask on some
  toolchains. Useful for ad-hoc probing against a specific
  toolchain image (e.g., `docker run --rm swift:6.3 swift run
  swift-issue-<topic>-Repro`).

### Why `withKnownIssue` and not `.disabled(if: …)`

`.disabled(if: …)` is **silent** when upstream lands a fix — no
signal, no PR-trigger, no detection. `withKnownIssue` flips red the
moment the bug stops firing on the configured platform, which IS the
upstream-fix detection mechanism. Skipping via `.disabled` alone is a
regression of detection capability and is forbidden per the per-issue
convention.

### Adding a new issue

1. Create `swift-issue-<topic>/` at the repo root.
2. Write the bug `README.md` + (optional) `INVESTIGATION-ARC.md`.
3. Author `Tests/Reproducer.swift` and `Sources/Reproducer/main.swift`.
4. Add the two targets to the root `Package.swift`.
5. Push. CI auto-includes the new issue via `enumerate-issues`'s
   `ls -d swift-issue-*/` — zero CI maintenance.

## Building

Each issue is a target in this repo's root `Package.swift`. Clone and
test from the repo root:

```bash
git clone https://github.com/swift-institute/Issues.git
cd Issues
swift test                                                             # all issues
swift test --filter swift_issue_<topic>                                # one issue
swift run swift-issue-<topic>-Repro                                    # standalone executable
```

Requires Swift 6.3 or newer.

## CI

Continuous integration is per-issue × per-platform.

- A single `enumerate-issues` job emits the `swift-issue-*/`
  directory list as a JSON array.
- A `per-issue` matrix job consumes that list and calls the
  centralized
  [`swift-institute/.github`](https://github.com/swift-institute/.github)
  reusable workflow once per issue with `test-filter: <issue-dir>` —
  one full reusable invocation (macOS / Linux release / Linux nightly
  / Windows + format + lint + advisory linters) per issue. Each
  `(issue × reusable-job)` leg is its own status check.
- `fail-fast: false` — one issue's red leg never cancels sibling
  issues' legs.
- Weekly cron at Monday 06:00 UTC re-runs the matrix. The reusable's
  `linux-nightly` leg (`swiftlang/swift:nightly-main-jammy`) is where
  `withKnownIssue` flips red on upstream-fix-landing.
- No `ci-ok` aggregator-gating. The Issues repo's branch protection
  doesn't reference `ci-ok`; per-issue test legs are the actionable
  signals; one red issue does not block merges.

For an issue reproducer, **a permanently-red Linux release leg is the
bug's running evidence**. When the upstream fix lands and the
`withKnownIssue` block stops firing on `nightly-main-jammy`, that's the
signal to close the issue and either remove the reproducer or relocate
it as a regression fixture.

## Index

Each issue subdirectory documents its bug in `README.md`. Current
issues:

- [`swift-issue-conditional-extension-typealias-name-capture/`](swift-issue-conditional-extension-typealias-name-capture/) — conditional-extension member `typealias` named after an enclosing type's generic parameter captures declaring-context references; bogus rejects-valid `does not conform` diagnostic at `-typecheck` ([`swiftlang/swift#89684`](https://github.com/swiftlang/swift/issues/89684)); present 6.3.2 → 6.5-dev, unfixed.
- [`swift-issue-copypropagation-nonescapable-mark-dependence/`](swift-issue-copypropagation-nonescapable-mark-dependence/) — CopyPropagation `~Escapable` coroutine-yield crash ([`swiftlang/swift#88022`](https://github.com/swiftlang/swift/issues/88022)); **fixed** in Swift 6.3 (Xcode 26.4).
- [`swift-issue-embedded-wasm-mandatory-perf-crash/`](swift-issue-embedded-wasm-mandatory-perf-crash/) — Wasm Embedded `MandatoryPerformanceOptimizations` SIL crash on cross-module use of the `Tagged<Tag, Ordinal> + Tagged<Tag, Cardinal>` operator; verified on Swift 6.3.2 Wasm SDK Embedded. Terminal record — not filed. *(investigation-arc + standalone repro only; no `withKnownIssue` test harness yet)*
- [`swift-issue-functionsignatureopts-generic-typed-throws-error/`](swift-issue-functionsignatureopts-generic-typed-throws-error/) — `FunctionSignatureOpts` `!type.hasTypeParameter()` assertion (`SILArgument.cpp:40`) at `-O` on a generic function whose typed-throws error type carries its own generic parameter ([`swiftlang/swift#89617`](https://github.com/swiftlang/swift/issues/89617)); present 6.2 → 6.5-dev, unfixed.
- [`swift-issue-noncopyable-extension-member-mangling-collision/`](swift-issue-noncopyable-extension-member-mangling-collision/) — a member of a `where Element: Copyable` extension and the same-signature member in the primary body of a type nested in `extension P where Element: ~Copyable` mangle to one symbol (the defaulted requirement is never mangled; `ASTMangler` then treats the extension as unconstrained) — Sema-valid constraint-split twins die at IRGen with `multiple definitions of symbol`; generalizes to `~Escapable`, any member kind, depth-2 nesting; present 6.2 → 6.5-dev, unfixed. **Terminal record — STAGED, not filed** (standing policy). Workarounds: member-level `where` clause (SE-0267) or both twins extension-homed.
- [`swift-issue-noncopyable-rawlayout-trailing-field-miscompile/`](swift-issue-noncopyable-rawlayout-trailing-field-miscompile/) — `~Copyable` value-witness IRGen SSA dominance violation (LLVM "Instruction does not dominate all uses", signal 6 at `-O`) when a generic `@_rawLayout(likeArrayOf:count:)` buffer precedes a trailing scalar field in a type with a `deinit`. Swift 6.3.1 → 6.5-dev, macOS arm64 + Linux aarch64. Workaround: field reorder. Related to `swiftlang/swift#86652`. Terminal record — not filed.
- [`swift-issue-noncopyable-sametype-conditional-conformance/`](swift-issue-noncopyable-sametype-conditional-conformance/) — the runtime cannot verify a conditional conformance whose same-type requirement RHS is a `~Copyable` type: null-metadata SIGSEGV at `-Onone` AND silent wrong `is` results at any optimization level (catalog §A15; traced to `ProtocolConformance.cpp:1843`); broken on every compiler × runtime combination tested, 6.2 → 6.5-dev, unfixed. **Terminal record — STAGED, not filed** (standing policy). Verified workaround recorded in-dossier; the shipped mitigation is the `Memory.Pooling` capability seam.
- [`swift-issue-parameterized-typealias-opaque-return-ice/`](swift-issue-parameterized-typealias-opaque-return-ice/) — parameterized-typealias × parameterized-protocol opaque-return ICE ("failed to produce diagnostic"); **fixed** upstream on Swift 6.4-dev nightly-main.
- [`swift-issue-pointer-arithmetic-linux-miscompile/`](swift-issue-pointer-arithmetic-linux-miscompile/) — pointer-arithmetic release-mode miscompile ([`swiftlang/swift#77558`](https://github.com/swiftlang/swift/issues/77558)); **fixed** on 6.4-dev nightly-main.
- [`swift-issue-rawlayout-noncopyable-deinit/`](swift-issue-rawlayout-noncopyable-deinit/) — `@_rawLayout` element-destruction LLVM IR domination crash ([`swiftlang/swift#86652`](https://github.com/swiftlang/swift/issues/86652)).
- [`swift-issue-rawlayout-noncopyable-extension-rejection/`](swift-issue-rawlayout-noncopyable-extension-rejection/) — unconditional protocol-conformance extension leaks `Copyable` back to the primary declaration of a `~Copyable`-generic nested type; workaround `where Element: ~Copyable`. Terminal record — not filed.
- [`swift-issue-spm-planning-build-stall/`](swift-issue-spm-planning-build-stall/) — SwiftPM planning-build stall at heavy consumers. Terminal record — not filed.
- [`swift-issue-tagged-noncopyable-atomic-metadata-crash/`](swift-issue-tagged-noncopyable-atomic-metadata-crash/) — `Atomic<Tagged<Tag, Ordinal>>.advance(within:)` runtime metadata SIGSEGV on Apple Swift 6.3.x (demangle-time lookup of a cross-module conditional `AtomicRepresentable` conformance with `~Copyable` Tag suppression); **fixed** on Swift 6.4-dev nightly `2026-03-16-a` and later. Terminal record — not filed.

## License

[Apache 2.0](LICENSE.md).
