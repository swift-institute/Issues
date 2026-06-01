# Swift Issue: `~Copyable` `@_rawLayout` Trailing-Field Value-Witness Dominance Violation

**Classification**: ICE / compiler crash (LLVM module verifier abort, signal 6).
**Upstream**: PENDING filing (`swiftlang/swift#PENDING`). Distinct from
[`swiftlang/swift#86652`](https://github.com/swiftlang/swift/issues/86652) — see
"Relationship to #86652" below.
**Status**: STILL BROKEN on every toolchain sampled (Apple Swift 6.3.2, 6.4-dev,
6.5-dev on macOS arm64; Swift 6.3.1-RELEASE and 6.4-dev nightly on Linux
aarch64). Not fixed on `nightly-main` as of 2026-05-28.
**Workaround**: declare the trailing scalar field *before* the `@_rawLayout`
buffer (field reorder); see "Workaround" below.

## Summary

When a `~Copyable` type stores a **generic `@_rawLayout`-backed buffer**
followed by a **trailing fixed-size (scalar) stored property**, and the type (or
a member) has a `deinit`, Swift IRGen emits the compiler-synthesized
**`destroy`** and **`assignWithTake`** value-witness functions as a per-element
loop over the raw-layout storage. The post-loop offset of the trailing field is
computed as `stride(Element) × capacity`. The `stride` value is loaded
(`!invariant.load` from the element value-witness table) **inside the loop body**,
but the `mul` that uses it is placed in the **loop-exit block**, which is also
reachable directly from the loop pre-header on the zero-trip path. The stride
load therefore does not dominate its use. LLVM's module verifier rejects the
module and `swiftc -O` / `swift build -c release` aborts (signal 6):

```
Instruction does not dominate all uses!
  %25 = load i64, ptr %24, align 8, !invariant.load !17
  %37 = mul i64 %25, 8
<unknown>:0: note: Broken module found, compilation aborted!
error: compile command failed due to signal 6
```

The backtrace shows `llvm::report_fatal_error` from
`PassModel<…, llvm::VerifierPass, …>` inside `swift::performLLVMOptimizations`.

## The broken symbol (demangled)

From `-emit-irgen` (pre-LLVM-opt) IR, the functions carrying the invalid IR are
**compiler-synthesized value witnesses**, not user code:

```
$s4main3BoxVwxx  ->  destroy value witness for main.Box
$s4main3BoxVwta  ->  assignWithTake value witness for main.Box
```

This confirms the working hypothesis's *value-witness* characterization. See
[`evidence/demangle.txt`](evidence/demangle.txt).

## The responsible pass

**None — the IR is invalid as emitted by Swift IRGen.** A full
`-Xllvm -print-after-all` run produces **no** `IR Dump After` lines before the
abort; the crash is at `Running pass "verify" on module`, i.e. LLVM's module
`VerifierPass`, the first thing `performLLVMOptimizations` runs. No transform
pass (LICM, GVN, SimplifyCFG sink, …) hoists the load — the verifier is the
detector, not the cause. The cross-block use is present directly in the IRGen
output. See [`evidence/pass-identification.log`](evidence/pass-identification.log)
and the annotated CFG at [`evidence/destroy-witness.cfg.ll`](evidence/destroy-witness.cfg.ll).

(This corrects the original hypothesis, which guessed an optimizer pass was
hoisting the `!invariant.load` across a branch. It is not hoisted; IRGen places
the post-loop `mul %stride, capacity` in a block the stride load does not
dominate.)

### CFG (def / branch / use)

```llvm
loop:
  %stride = load i64, ptr %5, align 8, !invariant.load !17   ; DEF (loop only)
  %6 = mul i64 %1, %stride                                   ; OK  (same block)
  br i1 %9, label %exit, label %cond
exit:                                  ; preds = %loop, %cond ; also reached WITHOUT loop
  %10 = mul i64 %stride, 8                                   ; USE not dominated by DEF
```

## Trigger characterization (ingredient list)

Reduced from the production crash via single-element removal with clean rebuilds.
All of the following are REQUIRED — removing any one makes `swiftc -O` compile
cleanly:

1. **Generic element** (`Element: ~Copyable`). A concrete element makes the
   `@_rawLayout` size a compile-time constant, so no `stride × capacity`
   runtime `mul` is generated → no crash.
2. **`@_rawLayout(likeArrayOf: Element, count: N)` storage** field whose size is
   `stride(Element) × N` (runtime, since `Element` is generic).
3. **A `deinit`** on the type whose value witnesses are synthesized. Without it
   the composite (loop-bearing) value witnesses are not generated.
4. **A trailing fixed-size stored property declared AFTER the `@_rawLayout`
   field.** With no field after the buffer, no post-loop offset `mul` exists.
5. **`-O` (release).** Debug (`-Onone`) compiles cleanly and the program runs
   (prints `1`, exits 0).

Not required: a loop in the user's `deinit` body (a trivial `deinit { _ = field }`
still crashes); a separate outer wrapper struct (a single struct reproduces);
cross-module split; a reference-typed field.

## Reproduction matrix

Run on the canonical minimum reproducer
[`Sources/Reproducer/Crash.swift.txt`](Sources/Reproducer/Crash.swift.txt):

```bash
swiftc -O -enable-experimental-feature RawLayout \
  -enable-experimental-feature ValueGenerics Crash.swift.txt -o /tmp/crash
```

| Toolchain (`swift --version`) | Platform | `-O` build | `-Onone` build + run |
|-------------------------------|----------|-----------|----------------------|
| Apple Swift 6.3.2 (`swiftlang-6.3.2.1.108 clang-2100.1.1.101`) | macOS arm64 | **CRASH** (verifier) | clean; prints `1`, exit 0 |
| Apple Swift 6.4-dev (`LLVM a3655ee8d8c4d74, Swift d13cbbfd336f246`, nightly `2026-03-16-a`) | macOS arm64 | **CRASH** | n/a |
| Apple Swift 6.4-dev (`LLVM d2079213f1d4451, Swift 82b7720768ba875`, nightly `2026-05-07-a`) | macOS arm64 | **CRASH** | n/a |
| Apple Swift 6.5-dev (`LLVM 7c86461e21cca7e, Swift 6da4da7153e8252`, nightly `2026-05-12-a`) | macOS arm64 | **CRASH** | n/a |
| Swift 6.3.1 (`swift-6.3.1-RELEASE`, `swift:6.3` Docker) | Linux aarch64 | **CRASH** | clean; prints `1`, exit 0 |
| Swift 6.4-dev (`LLVM d2079213f1d4451, Swift 82b7720768ba875`, `swiftlang/swift:nightly-main-jammy`) | Linux aarch64 | **CRASH** | n/a |

The bug is present on every sampled toolchain, including the latest 6.5-dev
nightly — it is **not yet fixed upstream**.

## Workaround

Declare the trailing scalar field **before** the `@_rawLayout` buffer so the
variable-size storage is the last stored property. With nothing after the
buffer, no field needs a `stride × capacity` offset and no post-loop `mul` is
generated:

```swift
struct Box<Element: ~Copyable>: ~Copyable {
    @_rawLayout(likeArrayOf: Element, count: 8)
    struct Raw: ~Copyable { init() {} }

    var position: Int   // scalar field FIRST
    var raw: Raw        // @_rawLayout buffer LAST

    init() { position = 0; raw = Raw() }
    deinit { _ = position }
}
```

This is exactly the production fix applied to
`swift-buffer-linear-primitives` (`Buffer.Linear.Inline.Scalar`, commit
`2b82466`) and `swift-buffer-ring-primitives`
(`Buffer.Ring.Inline.Scalar`, commit `e103122`): the `Index` field was moved
ahead of the inline buffer. Semantics-identical; `@inlinable` preserved.

`swift-storage-primitives`' `Storage.Inline` already carries the same field-order
discipline (`_storage` declared last) plus a `_deinitWorkaround: AnyObject?`
property for the separate runtime bug below.

## Relationship to `swiftlang/swift#86652`

Same `@_rawLayout` + value-generic family, **different defect**:

- **#86652** is a *runtime* miscompile — the synthesized member-destruction for
  a value-generic `@_rawLayout`/`InlineArray` field is silently skipped, so
  `~Copyable` elements leak (their `deinit` never runs). It compiles fine; the
  failure is observed at run time as missing destruction. Worked around with a
  dummy `AnyObject?` property. Tracked in this repo at
  [`../swift-issue-rawlayout-noncopyable-deinit/`](../swift-issue-rawlayout-noncopyable-deinit/).
- **This issue** is a *compile-time* abort — the synthesized `destroy` /
  `assignWithTake` value witnesses are emitted with an SSA dominance violation
  and the LLVM module verifier kills the build. It is triggered specifically by
  a **trailing fixed-size field after the `@_rawLayout` buffer** and worked
  around by **field reorder**.

Both are catalogued in
`swift-institute/Research/swift-compiler-bug-catalog.md` under the `#86652`
family; this entry is the standalone, dependency-free reducer for the
compile-time variant.

## Harnesses

Because the bug aborts the *compiler*, the triggering source cannot be a
compiled SwiftPM target (it would abort the whole package build). The trigger
ships as the [`Crash.swift.txt`](Sources/Reproducer/Crash.swift.txt) resource and
is compiled **out of process** by both harnesses:

- [`Tests/Reproducer.swift`](Tests/Reproducer.swift) — Swift Testing. Runs
  `swiftc -O` on `Crash.swift.txt` in a child process and wraps the result in
  `withKnownIssue`. **Green** while the subprocess build aborts with the verifier
  error (current state); flips **red** when an upstream fix lands and the source
  compiles cleanly.
- [`Sources/Reproducer/main.swift`](Sources/Reproducer/main.swift) — standalone
  executable. `exit(1)` if the subprocess build aborts (bug fired), `exit(0)` if
  it compiles cleanly (bug fixed) or the probe was inconclusive.
