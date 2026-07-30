// swiftlang/swift — Tagged + Atomic + ~Copyable cross-module conditional-conformance
// runtime metadata SIGSEGV — standalone executable reproducer.
//
// Companion to Tests/Reproducer.swift. This executable trips the bug
// directly: when the bug fires, the process is killed by the kernel with
// SIGSEGV (signal 11, exit code 139). When the bug does not fire, the
// program prints `result = 0` and exits 0.
//
// Exit code semantics:
//   0   — bug not fired; the .advance(within:) call returned cleanly
//   139 — bug fired (SIGSEGV during runtime metadata lookup for
//         Atomic<Tagged_Primitives.Tagged<…>>); the kernel killed the
//         process before the program could reach its own exit point.
//
// "exit(1) on crash-fired" is impossible for this bug class: the failure
// is a process-terminating signal in `swift_getTypeByMangledName`, not
// a recoverable runtime error. The CI per-issue matrix's macOS 6.3.x
// leg captures the 139 termination as the bug-fired signal.

import Synchronization
import Tagged_Primitives
import Ordinal_Primitives
import Cardinal_Primitives

// `SimpleTag` names this reproducer's phantom tag type as reported upstream
// and referenced verbatim in this issue's README/investigation notes;
// renaming would desync the reproducer from its own documentation (the two
// usage sites below cite [API-NAME-010] and are suppressed with reason).
enum SimpleTag: Sendable {}

// swiftlint:disable:next no_tag_suffix_phantom
let cursor = Atomic<Tagged<SimpleTag, Ordinal>>(.zero)
// reason: the literal `2` is a known-valid Cardinal for this probe; the
// force-try is not a runtime risk.
// swiftlint:disable:next no_tag_suffix_phantom force_try
let count: Tagged<SimpleTag, Cardinal> = try! .init(2)
let result = cursor.advance(within: count)
print("result = \(result.underlying.rawValue)")
