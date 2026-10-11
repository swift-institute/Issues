# StackNesting::fixNesting crash (MandatoryAllocBoxToStack): discarding a ~Copyable result in a `do` with a pattern `catch … where`

Canonical work item: [swift-institute/Issues#85](https://github.com/swift-institute/Issues/issues/85). No upstream report; none is to be filed (Coen, 2026-10-11).

## Origin

The io_uring capability probe in swift-linux-foundation/swift-linux-standard, as first written at `66fea995e8f95f2ee516c82568758dd0c4fc88d0`, crashed the frontend on Linux in `StackNesting::fixNesting` (MandatoryAllocBoxToStack). It was then rewritten at `4a41a602`. The crashing shape:

```swift
do {
    _ = try Kernel.IO.Uring.setup(entries: …, params: &params)
    return true
} catch Kernel.IO.Uring.Error.setup(let code) where code == .posix(EPERM) || code == .posix(ENOSYS) {
    return false
}
```

## Swift 6.4 (2026-10-11): does not reproduce

`66fea99` itself no longer builds: its dependency `swift-primitives/swift-memory-map-primitives` is gone. Instead, `.github/workflows/platform-probes.yml` (job "Issues#85") takes swift-linux-standard main at `a3ea811f3c69f26692a3a1ea0ba33048f562366d`. It puts the shape above back into `Tests/Linux Kernel Standard Tests/Linux.Kernel.IO.Uring Tests.swift` with [`restore-original-probe.pl`](restore-original-probe.pl); the log confirms the diff applied. It then builds the tests. It also compiles the neutral [`Reduced.swift.txt`](Reduced.swift.txt) at `-Onone` and `-O`.

| Image | Compiler | Neutral file | Package, debug | Package, release (`-enable-testing`) |
|---|---|---|---|---|
| `swift:6.4.0-noble` | Swift 6.4 (swift-6.4-RELEASE) | clean | clean | clean |
| `swiftlang/swift:nightly-6.4.x-noble` | 6.4.4-dev (Swift 337447f0d839cb2), assertions | clean | clean | clean |

These are runs 38139500995 and 38140145412. The neutral file is also clean on macOS with Apple Swift 6.4. No 6.3.x Linux run was made to confirm that the neutral file triggered the crash originally. Closed as not reproducible on 6.4.
