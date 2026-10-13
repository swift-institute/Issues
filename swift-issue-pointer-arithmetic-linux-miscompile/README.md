# Swift Issue: Pointer Arithmetic Release-Mode Miscompile

**Upstream:** [`swiftlang/swift#77558`](https://github.com/swiftlang/swift/issues/77558) — filed 2024-11-12. **Not fixed on Swift 6.4.**

**Status 2026-10-13 (Swift 6.4, swiftlang-6.4.0.34.1):** the misload
reproduces under `swift test -c release` on macOS 27 arm64 and on the
`swift:6.4` Linux image on aarch64 and x86_64. Debug builds are correct
everywhere. It fires whether the load sits inside an `#expect` closure
or in plain code, so the test computes the value in plain code and
wraps only the comparison in `withKnownIssue`, gated on release builds
(Windows excluded until its CI leg shows whether it fires). The earlier
6.3-era analysis below, including "fixed on 6.4-dev nightly-main", is
kept as history and no longer describes the current toolchain.

The original 6.3-era summary: a `.pointee` load after a pair of chained
`.advanced(by:)` calls on `UnsafeMutablePointer<Int>` — at least one
with a negative offset — reads from the wrong address under SwiftPM
`swift test -c release` on Linux 6.3.1 release.

## Trigger characterization

- **Where**: SIL optimizer or LLVM backend. The structural SIL pattern is `ref_tail_addr` on `_ContiguousArrayStorage<Int>` followed by chained `index_addr` instructions with mixed-direction folded offsets; dead-store elimination of the array literal's intermediate-index stores leaves an uninitialized-memory read at the folded offset.
- **Affected via SwiftPM-test path**: `swift test -c release` on `swift:6.3-jammy` Docker (Linux x86_64 AND aarch64). Fires; the in-tree `withKnownIssue` harness catches it as a recorded known issue.
- **NOT affected via bare `swiftc -O` on current 6.3.x distributions**: empirically verified 2026-05-11 — neither Apple Swift 6.3.1 (macOS arm64) nor `swift:6.3-jammy` Docker (Linux x86_64 / aarch64) reproduces the bug standalone on any of the probed repro shapes (operator-wrapped, direct `.advanced(by:)`, function-wrapped, byte-for-byte mirror of the test body). See [`evidence/README.md`](evidence/README.md) for the discrepancy analysis. The convergence-discussion's earlier "macOS arm64 standalone fires" observation is no longer reproducible on the current distribution; the SwiftPM-test-runner build flag combination appears to gate the firing on the current minimum repro.
- **Unaffected by toolchain version**: `swiftlang/swift:nightly-main-jammy` (Swift 6.4-dev) does NOT reproduce via either path — upstream fix landed.
- **Trigger (when firing)**: ≥2 chained `.advanced(by:)` calls on `UnsafeMutablePointer<Int>`, with at least one negative offset, over array literal storage.
- **Does NOT depend on**: SwiftPM `swiftSettings`, the `unsafe` keyword (SE-0466), user-authored operator overloads, `.strictMemorySafety`, `.Lifetimes`, `.LifetimeDependence`, or any other experimental / upcoming feature.

The investigation visited three sequential hypotheses (`.Lifetimes`
trigger → `unsafe`-keyword trigger → actual chained-advance trigger),
each refuted by the next experiment. See
[`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) for the convergence
chronology and [`evidence/README.md`](evidence/README.md) for the
2026-05-11 standalone-doesn't-fire discrepancy analysis.

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
  firing. The red flip IS the upstream-fix detection signal — surfaced
  on the per-issue CI matrix's `Linux nightly` leg via
  `swiftlang/swift:nightly-main-jammy`. **This is the load-bearing
  signal.**
- **`Sources/Reproducer/main.swift`** — standalone executable, retained
  as a local-probing tool. On current 6.3.x distributions (Apple
  Swift 6.3.1 / `swift:6.3-jammy` Docker) the bare `swiftc -O` /
  `swift run` path does NOT fire the bug — exits 0. Kept in the
  package for ad-hoc probing against older Apple toolchains or
  candidate-fix-state toolchains where the firing surface may
  differ.

## Reproduction

From the Issues repo root:

```bash
# Debug: passes. Release: the bug fires and withKnownIssue records it.
swift test --filter swift_issue_pointer_arithmetic_linux_miscompile
swift test -c release --filter swift_issue_pointer_arithmetic_linux_miscompile

docker run --rm -v $(pwd):/work -w /work swift:6.4 \
    swift test -c release --filter swift_issue_pointer_arithmetic_linux_miscompile
# → "Test reproducer() recorded a known issue at Reproducer.swift:…:
#    Expectation failed: loaded == 20"
```

### Standalone executable

The standalone executable target (`swift-issue-pointer-arithmetic-linux-miscompile-Repro`) is retained as a local-probing tool. **Empirical 2026-05-11**: on Apple Swift 6.3.1 (macOS 26) AND `swift:6.3-jammy` Docker (Linux ARM64 + Linux x86_64), `swiftc -O` standalone does NOT fire the bug — exit 0 on every platform / optimization-level / repro-shape combination. The bug fires only through the SwiftPM-test path on Linux release. See [`evidence/README.md`](evidence/README.md) for the discrepancy analysis (likely SwiftPM-test-runner-gated firing per INVESTIGATION-ARC.md §Round 2).

```bash
swift run swift-issue-pointer-arithmetic-linux-miscompile-Repro; echo $?
# → exit 0 on current toolchains (does not fire). Useful for probing
#   older Apple toolchains or candidate fix toolchains where the
#   bug's surface may differ.
```

## Workaround for consumers

Collapse the two `.advanced(by:)` calls into one with the net offset,
OR insert an opaque side effect that observes every element before
the chained load (preventing the DSE of the live-element stores):

```swift
// Structural trigger pattern (fires via swift test -c release on Linux 6.3.1 release):
let advanced = base.advanced(by: 4)
let backed   = advanced.advanced(by: -2)
let value    = backed.pointee

// Workaround A — collapse the chain:
let backed = base.advanced(by: 2)   // 4 - 2 collapsed
let value  = backed.pointee

// Workaround B — force every element to be observed first:
for v in values { _ = v }
// ... then perform the chained advance normally
```

## Minimal code

The structural minimum repro (also in `Sources/Reproducer/main.swift`):

```swift
var values: [Int] = [0, 10, 20, 30, 40]
values.withUnsafeMutableBufferPointer { buf in
    let base     = buf.baseAddress!
    let advanced = base.advanced(by: 4)
    let backed   = advanced.advanced(by: -2)
    print(backed.pointee)   // expected 20; observed: wrong value via swift test -c release on Linux 6.3.1 release
}
```

Note: this exact form does NOT fire bare under `swiftc -O` on current
6.3.1 distributions — only via the SwiftPM-test-runner path. The in-tree
test harness at `Tests/Reproducer.swift` uses an operator-wrapped
variant (`base + Vec(4)`, `advanced - Vec(2)`) over the same chained
pattern; that's the form CI exercises.

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

Expected leg outcomes while the bug is live (Swift 6.4):

- **Debug legs**: GREEN — the bug does not fire; `when:` is false.
- **macOS release, Linux release**: GREEN with 1 known issue — the bug
  fires under `-O`; `withKnownIssue` records it.
- **Linux nightly** (`continue-on-error: true`): GREEN with 1 known issue
  while the bug fires there; RED ("Known issue was not recorded") once a
  fix lands.
- **Windows**: not gated; GREEN if the bug does not fire there, RED if it
  does (then add Windows to the gate).

The **weekly cron** (Monday 06:00 UTC) re-runs the matrix specifically to
detect the Linux-nightly flip without depending on unrelated pushes.

The universal-reusable's `ci-ok` aggregator job is emitted but treated as
informational only in this repo (no branch-protection rule references
it).

## Suggested labels

`bug`, `optimization`, `codegen`, `linux`, `darwin`, `unsafe-pointer`, `release-mode`
