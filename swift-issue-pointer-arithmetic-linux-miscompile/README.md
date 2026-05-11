# Swift Issue: Pointer Arithmetic Release-Mode Miscompile

**Upstream:** [`swiftlang/swift#77558`](https://github.com/swiftlang/swift/issues/77558) — filed 2024-11-12, **fixed on 6.4-dev nightly-main**, awaiting backport / 6.4 release.

A `.pointee` load after a pair of chained `.advanced(by:)` calls on
`UnsafeMutablePointer<Int>` — at least one with a negative offset —
reads from the wrong address under `-O` / `-Osize`. Cross-platform
(macOS arm64 + Linux x86_64); SIL and LLVM IR are byte-identical
between affected and unaffected source forms; the defect is at LLVM
optimization or backend codegen.

## Trigger characterization

- **Where**: LLVM optimizer or backend (SIL / LLVM IR byte-identical between trigger and non-trigger source).
- **Affected**: Swift 6.3.1 release + 6.4-dev nightly, `-O` / `-Osize`, macOS arm64 and Linux x86_64.
- **Unaffected**: `-Onone` on any platform; Swift 6.4-dev nightly-main (fixed upstream).
- **Trigger**: ≥2 chained `.advanced(by:)` calls on `UnsafeMutablePointer<Int>`, with at least one negative offset.
- **Does NOT depend on**: SwiftPM `swiftSettings`, the `unsafe` keyword (SE-0466), user-authored operator overloads, `.strictMemorySafety`, `.Lifetimes`, `.LifetimeDependence`, or any other experimental / upcoming feature.

The investigation visited three sequential hypotheses (`.Lifetimes`
trigger → `unsafe`-keyword trigger → actual chained-advance trigger),
each refuted by the next experiment. See
[`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) for the convergence
chronology.

## Layout — per-issue pattern

```
swift-issue-pointer-arithmetic-linux-miscompile/
├── README.md                    — this file
├── INVESTIGATION-ARC.md         — chronological convergence record
├── ISSUE-77558-COMMENT.md       — staged upstream-posting draft
├── Tests/
│   └── Reproducer.swift         — withKnownIssue flip-on-fix harness
├── Sources/
│   └── Reproducer/
│       └── main.swift           — standalone exit-code reproducer
└── evidence/                    — 16 bisection variants, plain .swift
    ├── README.md
    ├── Control.swift
    ├── WithLifetimes.swift
    └── … (14 more)
```

Two harnesses cover complementary surfaces:

- **`Tests/Reproducer.swift`** — Swift Testing. Wraps the 8-line repro
  in `withKnownIssue("swiftlang/swift#77558", when: { isLinuxRelease() })`.
  Green while the bug fires on Linux release (current state); the test
  flips **red** the moment upstream lands a fix and the bug stops
  firing. The red flip IS the upstream-fix detection signal — captured
  by `.github/workflows/nightly.yml` against
  `swiftlang/swift:nightly-main-jammy`.
- **`Sources/Reproducer/main.swift`** — standalone executable. The
  bug fires on `swiftc -O` on both Linux AND macOS; SwiftPM
  `swift test -c release` masks the macOS case for reasons related to
  test-framework build flags. The executable closes that gap with an
  exit-code assertion: `exit(observed == 20 ? 0 : 1)`.

## Reproduction

From the Issues repo root:

```bash
# Test harness — green on macOS (when:-predicate false on macOS); green on
# Linux release with `withKnownIssue` catching the firing bug; red on Linux
# nightly = fix landed upstream.
swift test --filter swift_issue_pointer_arithmetic_linux_miscompile                  # debug
swift test -c release --filter swift_issue_pointer_arithmetic_linux_miscompile       # fires on Linux

# Linux release through SwiftPM test runner — fires the bug, withKnownIssue catches it:
docker run --rm -v $(pwd):/work -w /work swift:6.3-jammy \
    swift test -c release --filter swift_issue_pointer_arithmetic_linux_miscompile
# → "Test reproducer() recorded a known issue at Reproducer.swift:62:21:
#    Expectation failed: unsafe backed.pointee == 20"
```

### Standalone executable

The standalone executable target (`swift-issue-pointer-arithmetic-linux-miscompile-Repro`) is retained as a local-probing tool. **Empirical 2026-05-11**: on Apple Swift 6.3.1 (macOS 26) AND `swiftlang/swift:6.3.1-RELEASE` (Linux ARM64 + Linux x86_64), `swiftc -O` standalone does NOT fire the bug — exit 0 on every platform/optimization-level combination. The bug fires only through the SwiftPM-test path on Linux release. See [`evidence/README.md`](evidence/README.md) for the discrepancy analysis (likely SwiftPM-test-runner-gated firing per INVESTIGATION-ARC.md §Round 2).

```bash
swift run swift-issue-pointer-arithmetic-linux-miscompile-Repro; echo $?
# → exit 0 on current toolchains (does not fire). Useful for probing
#   older Apple toolchains or candidate fix toolchains where the
#   bug's surface may differ.
```

## Workaround for consumers

Avoid the user-authored operator wrappers; call `.advanced(by:)`
directly and inline the offsets, OR collapse the two `.advanced(by:)`
calls into one with the net offset:

```swift
// Triggers the bug:
let advanced = base.advanced(by: 4)
let backed   = advanced.advanced(by: -2)
let value    = backed.pointee

// Workaround:
let backed = base.advanced(by: 2)   // 4 - 2 collapsed
let value  = backed.pointee
```

## Minimal code

The 8-line repro (also in `Sources/Reproducer/main.swift`):

```swift
var values: [Int] = [0, 10, 20, 30, 40]
values.withUnsafeMutableBufferPointer { buf in
    let base     = buf.baseAddress!
    let advanced = base.advanced(by: 4)
    let backed   = advanced.advanced(by: -2)
    print(backed.pointee)   // expected 20; observed: wrong value under -O
}
```

## Heisenbug character

Any diagnostic instrumentation reading the result pointer between the
second `.advanced(by:)` and the `.pointee` load masks the bug:

- Print statements between the second advance and the load.
- Intermediate `let _ = UInt(bitPattern: backed)` materializations.
- `print()` of the address inside a `#expect` message string.

The reduced repro deliberately omits all such instrumentation.

## CI status

The Issues repo's `.github/workflows/ci.yml` is a per-issue matrix wrapper
around the centralized `swift-institute/.github` reusable workflow. Each
push touching `swift-issue-pointer-arithmetic-linux-miscompile/**` or
`Package.swift` runs the full reusable (macOS / Linux release / Linux
nightly / Windows + format + lint + advisory linters) with `test-filter:
swift-issue-pointer-arithmetic-linux-miscompile`. Per-leg status checks
are named `swift-issue-pointer-arithmetic-linux-miscompile / <reusable-job>`.

Expected leg outcomes while the bug is live upstream:

- **macOS**: GREEN — `withKnownIssue`'s `when:` predicate is false on
  macOS; wrapped block runs unguarded and passes.
- **Linux release**: GREEN with 1 known issue — bug fires under `-O`;
  `withKnownIssue` catches it; suite passes.
- **Linux nightly** (`continue-on-error: true`): GREEN with 1 known issue
  until upstream fix propagates to `swiftlang/swift:nightly-main-jammy`;
  RED (withKnownIssue flip) after fix lands.
- **Windows**: GREEN — bug is Linux-specific.

The **weekly cron** (Monday 06:00 UTC) re-runs the matrix specifically to
detect the Linux-nightly flip without depending on unrelated pushes.

The universal-reusable's `ci-ok` aggregator job is emitted but treated as
informational only in this repo (no branch-protection rule references
it).

## Suggested labels

`bug`, `optimization`, `codegen`, `linux`, `darwin`, `unsafe-pointer`, `release-mode`
