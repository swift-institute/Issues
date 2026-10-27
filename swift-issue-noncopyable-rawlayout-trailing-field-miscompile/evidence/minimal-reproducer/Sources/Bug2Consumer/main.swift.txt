// Toolchain: Swift 6.3.1 (2026-04-30) — anchor added during Phase 7a sweep [EXP-007a]
// Revalidated: Swift 6.3.1 (2026-04-30) — STILL CRASHES
//
// Bug2Consumer: imports Bug2PropertyLib + Bug2Middleware
//
// Build: rm -rf .build && swift build -c release --target Bug2Consumer
// Expected: signal 6, "Found ownership error?!" in CopyPropagation
//
// NOTE: Bug2PropertyLib needs -disable-llvm-verify to get past Bug 1,
//       since it stores @_rawLayout types from Bug1Core.

public import Bug2PropertyLib
public import Bug2Middleware

// ── Direct usage ────────────────────────────────────────────────────

@inlinable
public func exerciseSmallBuffer() {
    var buf = SmallBuffer<NCElement>()
    buf.append(NCElement(1))
    buf.append(NCElement(2))
    buf.drain { print($0.value) }
}

// ── Through middleware ──────────────────────────────────────────────

@inlinable
public func exerciseMiddleware() {
    buildAndDrain()
}

exerciseSmallBuffer()
exerciseMiddleware()
print("Bug2: all patterns exercised")
