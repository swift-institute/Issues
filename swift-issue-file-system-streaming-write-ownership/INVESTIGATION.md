# swift-file-system `Streaming.write(chunk:to:)` — SIL ownership-verifier crash

> **STAGED TERMINAL RECORD** ([ISSUE-008] standing policy: no upstream filing at swiftlang).
> This dossier is the terminal record. Not filed, not to be filed. Staged locally only.

## Classification

**ICE / Crash** ([ISSUE-010]) — SIL ownership verifier abort (`signal 6`) during optimization
of `File.System.Write.Streaming.write(chunk:to:)`. Blocks `swift build -c release` of
`swift-file-system` (module **File System Core**), which in turn blocks `swift-pdf`'s release build.

Root-cause class: **CopyPropagation `try_apply` borrow-scope shortening** — same family as
catalog **§A5** and **§A23** (this entry). Differentiated from upstream #89787 / #78447 below.

## Environment

| | |
|---|---|
| Package | `swift-file-system` HEAD `7f1b013` (`main`) |
| Crashing module | `File System Core` |
| Crashing function | `File.System.Write.Streaming.write(chunk:to:)` — `$s16File_System_Core...5WriteO9StreamingO5write5chunk2to...ContextVtAI5ErrorOYKFZ` |
| **Default toolchain (crashes)** | `Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)`, `Target: arm64-apple-macosx26.0` |
| **Dev toolchain (FIXED)** | `Apple Swift version 6.5-dev (LLVM 8f81a64f6a8bcf6, Swift 4d0c97fa5b05711)`, `Build config: +assertions` (snapshot `swift-DEVELOPMENT-SNAPSHOT-2026-05-27-a` = `swift-latest`, bundle id `org.swift.64202605271a`) |
| Config | `-O` (release) only; `-Onone` (debug) compiles clean |
| Reproduction | **standalone single-file `swiftc -O`** (no SwiftPM, no WMO, no deps) — `reducer.swift` |

> NOTE on version label: the dispatch brief labelled `org.swift.64202605271a` as "6.4-dev".
> Empirically (`swift --version`) it is **6.5-dev** with `+assertions`. Per the snapshot-label
> discipline, the empirical string governs. The other installed snapshot bundle ids
> (`...05071a`, `...05121a`, `...03161a`) silently fall back to the 6.3.3 default and are not
> selectable; `org.swift.64202605271a`/`swift-latest` is the only functioning dev toolchain here.

## Reproducer (`reducer.swift`)

Standalone, single file, zero dependencies. Mirrors the production shape at
`Sources/File System Core/File.System.Write.Streaming+API.swift:264-272`.

```swift
enum InnerError: Error { case io(String) }
enum OuterError: Error {
    case wrapped
    init(_ e: InnerError) { self = .wrapped }
}

struct Descriptor: ~Copyable, Sendable {
    var raw: Int32
    init(raw: Int32) { self.raw = raw }
    deinit { /* closes fd */ }
}

struct Context: ~Copyable, Sendable {
    var descriptor: Descriptor?
    let isAtomic: Bool
    init(descriptor: consuming Descriptor, isAtomic: Bool) {
        self.descriptor = consume descriptor
        self.isAtomic = isAtomic
    }
}

@inline(never)
func writeAll(_ span: borrowing Span<UInt8>, to descriptor: borrowing Descriptor) throws(InnerError) {
    if descriptor.raw < 0 { throw InnerError.io("bad fd") }
    if span.count == 0 { throw InnerError.io("empty") }
}

func write(chunk span: borrowing Span<UInt8>, to context: borrowing Context) throws(OuterError) {
    do {
        try writeAll(span, to: context.descriptor!)
    } catch {
        throw OuterError(error)            // typed-throws error MAPPING
    }
}
// + top-level driver (see reducer.swift)
```

## Command / Observed / Expected

**Command**: `swiftc -O reducer.swift`

**Observed** (Swift 6.3.3, `-O`):
```
Found outside of lifetime use?!
Value:   %6 = begin_borrow %1 : $Context
Consuming User:   end_borrow %6 : $Context
Non Consuming User:   try_apply %15(%5, %13) : $@convention(thin)
        (@guaranteed Span<UInt8>, @guaranteed Descriptor) -> @error InnerError, normal bb3, error bb4
Found ownership error?!
<unknown>:0: error: fatal error encountered during compilation
4.  While running pass #226 SILFunctionTransform "CopyPropagation"
        on SILFunction "@$s...5write5chunk2to...OuterErrorOYKF" for 'write(chunk:to:)'
error: compile command failed due to signal 6
```

**Expected**: clean compilation. The borrowed `Context` is live across the `try_apply`
(its `descriptor` field is the call's `@guaranteed` argument); the `end_borrow` must not
precede the `try_apply`.

## Investigation

### Pipeline-stage analysis ([ISSUE-005] / [ISSUE-019])

| Stage | Command | Result |
|---|---|---|
| Raw SIL (SILGen) | `swiftc -emit-silgen reducer.swift` | **WELL-FORMED** — `end_borrow %10/%11` occur in *both* the normal (bb3) and error (bb4) continuations, *after* the `try_apply`. |
| `-O` pipeline | `swiftc -O reducer.swift` | **CRASH** at pass **#226 CopyPropagation** — borrow scope shortened so `end_borrow` precedes the `try_apply`. |
| `-Onone` (debug) | `swiftc -Onone reducer.swift` | **CLEAN** (matches production: debug builds succeed). |
| `-sil-verify-all` | `swiftc -Xfrontend -sil-verify-all reducer.swift` | Surfaces the ownership-verification failure as early as the **mandatory** pass #448 `MoveOnlyChecker`, confirming the borrowing-`~Copyable`-field-across-`try_apply` lowering is fragile pre-optimizer; the default `-Onone` pipeline (verification off) compiles it cleanly. |

**Root cause**: SILGen emits a correct borrow scope for the `borrowing Context`. The
`do { try callee(span, to: context.descriptor!) } catch { throw Mapped(error) }` lowers to a
`try_apply` with normal+error continuation blocks; the borrowed `context` (and its
`@guaranteed descriptor` field) is consumed by that `try_apply`. **CopyPropagation** shortens
the `begin_borrow`/`end_borrow` scope of `context` to end *before* the `try_apply`, then
ownership verification flags "outside of lifetime use". This is the §A5 mechanism, now captured
with a clean single-file reducer (§A5 had previously believed WMO + cross-module inlining were
required — disproven here).

### Toolchain matrix

| Toolchain | `-O` | `-Onone` |
|---|---|---|
| 6.3.3 (Xcode default, `swiftlang-6.3.3.1.3`) | **CRASH** (CopyPropagation #226) | clean |
| 6.5-dev (`swift-latest`/`2026-05-27-a`, `Swift 4d0c97fa5b05711`, **+assertions**) | **clean — FIXED** | clean |

The 6.5-dev build is clean even under `+assertions` (which would *amplify*, not mask, malformed
SIL) — strong evidence the fix is genuine, not assertion-hidden.

### Stale-cache rule-out ([PKG-BUILD-010])

The crash reproduces from absolute scratch (fresh `/tmp` single file, no `.build`, no module
cache state), definitively excluding the "signal-6 = stale cache" hypothesis for the underlying
bug. (The package's own `Package.resolved` was separately found malformed — a stale
`localSourceControl`+URL pin for the non-existent `swift-buffer-arena-primitives`; deleting and
re-resolving fixed resolution. That is an environment artifact, not the compiler bug.)

### Duplicate differentiation ([ISSUE-007])

| Upstream | Why DISTINCT |
|---|---|
| **#89787** "[6.4 regression] SILGenCleanup ownership crash: catch with enum-case pattern on a non-trivial typed-throws error" | Crashes in **SILGenCleanup** (not CopyPropagation); requires a `catch <enum-case-pattern>` (`catch MyError.noData`) — ours uses a plain `catch { throw Error(error) }` with NO pattern match; no `~Copyable` borrow involved. **Opposite version profile**: #89787 is a 6.4 regression that *works* on 6.3.2; ours *crashes* on 6.3.3 and is *fixed* by 6.5-dev. |
| **#78447** "Compiler crash `Found outside of lifetime use?!`" | Same generic verifier message but triggered by C-header struct pointers; unrelated trigger. |

Shared error string (`Found outside of lifetime use?!`) is the ownership verifier's generic
diagnostic and is not itself a duplicate signal.

## Resolution (SHIPPED 2026-06-30 — STRUCTURAL fix, no suppression)

**Principal decision**: ship a genuine STRUCTURAL rewrite. Ungated `@_optimize(none)` (and every
other suppression attribute) is FORBIDDEN — a footgun that would silently survive into Swift 6.5
(where the bug is fixed). The structural fix below is correct on all toolchains, so it carries
no compiler gate.

### Shipped fix — `borrowing` Context methods (swift-file-system commit `4b19e6b`, `main`, unpushed)

The three descriptor-field-projecting throwing helper calls were moved into `borrowing` methods
on `File.System.Write.Streaming.Context` — `write(chunk span:)`, `write(chunk buffer:)`,
`sync()` — each propagating `File.System.Write.Error`. The static API now maps the error at the
call boundary:

```swift
public static func write(chunk span: borrowing Swift.Span<Byte>, to context: borrowing Context) throws(Error) {
    do { try context.write(chunk: span) } catch { throw Error(error) }
}

extension File.System.Write.Streaming.Context {
    borrowing func write(chunk span: borrowing Swift.Span<Byte>) throws(File.System.Write.Error) {
        try File.System.Write.writeAll(span, to: descriptor!)
    }
}
```

Inside a `borrowing` method, `self` is a whole-function `@guaranteed` parameter — there is no
nested `begin_borrow`/`end_borrow` scope for CopyPropagation to shorten. In the caller, the
wrapped call (`context.write(chunk:)`) takes the whole `context` as `@guaranteed self`, not a
field projection, so the context borrow spans the call by construction. `swift build -c release`
of swift-file-system goes **crash→clean** (exit 0, verified 2026-06-30). Applied uniformly to the
three affected sites: `write(chunk span:to:)`, `write(chunk buffer:to:)`, `commit(_:)` (its
`syncFile(context.descriptor!, …)` site). The reusable-buffer API (`write(to:…using:fill:)`,
~166–180) and the whole Atomic API were verified UNAFFECTED — their `context`/`tempFile` are
*owned locals*, not borrowed parameters; the bug requires a borrowed `~Copyable` parameter.

### Empirical correction to the original "try_apply" framing

The abort is NOT specific to the typed-throws `try_apply`. A reducer that eliminated the
`try_apply` by giving the helper a non-throwing `Result<Void, …>`-returning form **still
crashed** — the SIL then shows a plain `%N = apply … -> @owned Result<…>` as the offending
"Non Consuming User", with the same `begin_borrow`/`end_borrow`-of-`Context` shortened before it.
So the trigger is the *field-projected nested borrow scope* of the borrowed `~Copyable` value,
independent of whether the consuming call is a `try_apply` or a plain `apply`. This is why the
structural fix targets the borrow scope (whole-function `@guaranteed self`) rather than the
error-mapping continuation. (Reducer variants under scratchpad `reducer-exp/`: `v0_baseline`
crashes; `vB_shim`/`vBmethod_shim` (Result, no try_apply) crash; `vA_borrowing_method` clean.)

### Why the simplest §A5 fix does NOT apply here

§A5's preferred fix is to replace `do/catch` with `try?` (avoids the `try_apply` lowering). It
does **not** fit `write(chunk:to:)` because the `catch` performs an error-type *mapping*
(`File.System.Write.Error` → `File.System.Write.Streaming.Error`), which `try?` discards.
Hoisting the descriptor out of the borrow (`let fd = context.descriptor!`) is also **illegal**:
`Kernel.Descriptor` is itself `~Copyable` (owning fd, closes via the `Context`'s field deinit),
so it cannot be copied out of a `borrowing` binding.

### Rejected — suppression attributes (`@_optimize(none)` / `-sil-disable-pass`)

`@_optimize(none)` on each crashing function, OR a module-wide
`-Xllvm -sil-disable-pass=CopyPropagation` (release only) in `Package.swift`, would also avoid
the crash (both verified on the reducer). Both were REJECTED by the principal: ungated
suppression is a footgun that would silently survive into Swift 6.5, and the module-wide flag
costs the whole **File System Core** module its CopyPropagation pass. The structural fix
supersedes them and needs no removal when the toolchain reaches Swift 6.5+ (it is already
correct there).

## Artifacts

- `reducer.swift` — standalone crashing reproducer (this dir)
- `reducer-workaround.swift` — `@_optimize(none)` variant, compiles + runs clean (this dir)
- Catalog entry: `swift-institute/Research/swift-compiler-bug-catalog.md` **§A23**
- Full crash/SIL log: scratchpad `file-system-crash.log`
