// Bug1Consumer: executable target that depends on Bug1Middleware
//
// Build: rm -rf .build && swift build -c release --target Bug1Consumer
// Expected: signal 6, "Instruction does not dominate all uses!"
//
// NOTE: The crash occurs when compiling Bug1Middleware, not this consumer.
// Building Bug1Middleware alone also crashes:
//   rm -rf .build && swift build -c release --target Bug1Middleware
//
// ── Toolchain Results ──────────────────────────────────────────────
// Swift 6.2.4 (Xcode 26.3): REPRODUCES — LLVM verifier crash in release
// Swift 6.3   (Xcode 26.4): REPRODUCES — LLVM verifier crash in release
//   Tested: 2026-03-25
//   Despite 6.3 commits 8ae2a7b584f/3a8a19ad7d0 ("remove deinit
//   requirement" / "force VWT-based destruction" for @_rawLayout),
//   the cross-module 2+ field LLVM IR domination bug persists.
//   _deinitWorkaround fields CANNOT be removed yet.

public import Bug1Core
public import Bug1Middleware

let buf = Buffer<Int>()
print("Bug1: Buffer<Int> created — should not reach here in release mode")
