# Swift Issue: runtime SIGSEGV instantiating metadata for a generic type nested in a value-generic type

**Tracking record:** [swift-institute/Issues#105](https://github.com/swift-institute/Issues/issues/105).

**Upstream:** introduced by swiftlang/swift#89965 (main, 2026-06-16) and its
6.4.x cherry-pick swiftlang/swift#89995. **Fixed on main** by
[swiftlang/swift#91267](https://github.com/swiftlang/swift/pull/91267)
(merged 2026-08-07). No backport to `release/6.4.x` has landed, so every 6.4.x
release is affected. Nothing to file: the fix exists upstream.

**Classification:** runtime defect in `libswiftCore`. The program compiles
cleanly. It crashes when it runs, the first time metadata for
`Link<1>.Node<Int>` is built at run time.

## Minimal reproducer

`reproducer.swift` (also staged as `Sources/Reproducer/Crash.swift.txt` for the
out-of-process harness):

```swift
enum Link<let N: Int> {}

extension Link {
    struct Node<Element> {
        var element: Element
    }
}

print(_typeName(Link<1>.Node<Int>.self))
```

```bash
xcrun swiftc -Onone -module-name main reproducer.swift -o repro && ./repro
```

**Actual (6.4.x):** SIGSEGV, exit status 139, nothing printed. Under lldb the
crash is a null dereference in
`libswiftCore.dylib swift::nameForMetadata(...)`.

**Expected:** prints `main.Link<1>.Node<Swift.Int>` and exits 0, as Swift 6.3.3
does.

**`-O` hides it.** At `-O` the metadata for this shape is emitted statically and
the program prints the type name. The harness compiles at `-Onone` on purpose.

## Trigger characterization

From the original reduction (see `evidence/original/`). Each ingredient was
removed in turn; the crash needs all four.

| Ingredient | Removed / replaced by | Result |
|---|---|---|
| value-generic parent `Link<let N: Int>` | type-generic parent `Link<N>` | passes (`evidence/control-type-generic-parent.swift`) |
| nested type is itself generic | non-generic nested `Link<1>.Node` | passes (`evidence/control-non-generic-nested.swift`) |
| the type is nested | hoisted `struct Node<let N: Int, Element>` | passes |
| metadata requested at run time | `-O` (metadata emitted statically) | passes |

`~Copyable`, `InlineArray` storage, a self-referential generic argument and
Swift Testing are not needed.

The 6.5-dev runtime, before the fix, printed the cause before dying:
`integer value bound to non-value generic parameter`. The type decoder binds the
parent's value argument to a slot that expects a type.

## Toolchains

| Toolchain | Result | Source |
|---|---|---|
| Swift 6.3.3 (swift-6.3.3-RELEASE), linux/arm64 | passes | original reduction |
| Swift 6.4-dev (Swift db4e13695491982), linux/amd64 and linux/arm64, +assertions | crashes | original reduction |
| Apple Swift 6.4 (swiftlang-6.4.0.27.1), macOS arm64 | crashes | original reduction |
| **Apple Swift 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1), macOS arm64** | **crashes at `-Onone`, passes at `-O`** | this entry, 2026-10-27 (`evidence/macos-6.4.2-run.txt`) |
| Swift 6.4.4-dev nightly-6.4.x-noble (Swift 337447f0d839cb2 … a7875ddba7eabcb, 2026-10-11 to 2026-10-25) | crashes | recheck workflow comments on #105 |
| Swift 6.5-dev nightly-main-noble before the fix (Swift 83c32e02f71e4bb) | crashes | original reduction |
| Swift 6.5-dev nightly-main-noble (Swift 4f57c3ebcd65115, 488fdfe4523bb35, c2b0f686cc0dfdb, e2b4ba7fc0fbe87, f62414fd1d17227, 2026-10-11 to 2026-10-19) | passes: fixed by #91267 | recheck workflow comments on #105 |
| hosted macOS 26.6.2, Xcode 26.6 (17F113) | passes | recheck workflow comment on #105, 2026-10-11 |

The Xcode 26.6 result is not a fix: that Xcode ships a pre-6.4 toolchain, which
predates the regression. Xcode 27.x (Swift 6.4.x) still crashes, as the 6.4.2
row shows.

## Recheck workflow

[`.github/workflows/issue-105-toolchain-recheck.yml`](../.github/workflows/issue-105-toolchain-recheck.yml)
runs daily. It compiles the same snippet at `-Onone` on the `nightly-main-noble`
and `nightly-6.4.x-noble` images and on hosted macOS. It also checks
`release/6.4.x` for a backport of #91267. It posts one comment on #105 per new
toolchain revision and verdict. This entry is the Swift Testing record next to
it; the workflow is unchanged.

## Workaround

Hoist the generic type to module level and keep the spelling with a typealias
inside the value-generic parent:

```swift
struct __LinkNode<let N: Int, Element> { var element: Element }
extension Link { typealias Node<Element> = __LinkNode<N, Element> }
```

This is how swift-primitives/swift-link-primitives#3 mitigated it. Building with
`-O` also avoids it for code we compile, but not for consumers who build our
sources at `-Onone`.

## Harness

`Tests/Reproducer Tests.swift` and `Sources/Reproducer/main.swift` compile
`Crash.swift.txt` with `swiftc -Onone` in a child process and run the result as a
second child process, so the crash cannot take down the test runner. A child that
dies on a signal means the bug fired. A child that prints `….Node<Swift.Int>` and
exits 0 means it is absent. Anything else is inconclusive.

`withKnownIssue` uses `when:` the 6.4 compiler family
(`#if compiler(>=6.4) && !compiler(>=6.5)`), the toolchains known to crash. The
test flips red if a 6.4.x toolchain stops crashing, for example when #91267 is
backported. On 6.3 and on 6.5+ it is ordinary regression coverage.

Run locally on macOS arm64 only. Linux and Windows were not run here; CI and
the recheck workflow cover Linux.

## Provenance

Ported 2026-10-27 from `swift-institute/Experiments`
`value-generic-nested-generic-metadata-crash/` at commit
`f1c4db4d390c12af5ec454dfb506feaa4ec5e841` (Experiments PR #3, reduced
2026-08-09 from swift-primitives/swift-link-primitives `Link<let N: Int>.Node<Element>`).
The original files are in `evidence/original/`.
