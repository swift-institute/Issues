# Swift Issue: `Tagged` key + institute `Dictionary`/`__HashIndexed` insert runtime metadata SIGSEGV

**Terminal record (STAGED).** Not filed upstream — Institute terminal-record policy
per [`ISSUE-008`] (standing principal ruling 2026-06-11: upstream filing at swiftlang,
issue OR PR, is not a resolution step). This directory is the terminal record.

**Classification**: Runtime crash (per [`ISSUE-010`]). The compiler accepts the source
and emits a binary; at runtime the type-metadata materialization for a `Tagged`-keyed
institute `Dictionary` returns null and the caller dereferences `[null + 0x10]` →
`EXC_BAD_ACCESS (code=1, address=0x10)` → SIGSEGV.

**Verdict**: **catalog §A9 — SAME CLASS** (`swift-institute/Research/swift-compiler-bug-catalog.md`).
Confirmed by BOTH type identity and the canonical `swift_getTypeByMangledName` →
`TypeLookupError("unknown error")` null-metadata signature — the same two-part
confirmation §A9's own new-site records use (2026-06-01 `Set.Ordered`, 2026-06-27
`Parser.Machine`). This is not a new bug: it is §A9's **original site 3**
(`Dictionary<Kernel.Event.ID, Registration>` in `Kernel.Event.Driver.init`, catalog
§A9 line ~465, workaround commit `a79ca49`) **re-surfacing** after that workaround was
**reverted 2026-05-23** (`44ab1f8`) and after the ADT-tower reshape relocated the code
into `ISO_9945.Kernel` and respelled the container onto the
`__Dictionary`/`__HashIndexed`/`Hash.Entry`/`Buffer.Linear` engine.

**Status**: FIRES on Apple Swift 6.3.x (6.3.2 Xcode-default and 6.3.3 CLI-default);
inherits the §A9 family fixed-forward status (fixed by Swift 6.4-dev, the fix travels
with the compiler binary — §A9 Correction 2026-05-28 controlled compiler/runtime swap).
No Institute-side code fix (the raw-storage wrapper was reverted on correctness grounds
2026-05-23); the affected io suite is guarded with a `compiler(<6.4)` `.disabled(if:)`
trait (staged on the swift-io branch `adt-tower-io-crash`, not landed).

---

## Environment

| Field | Value |
|-------|-------|
| Toolchain (repro of record) | Apple Swift 6.3.2 RELEASE, Xcode 26.4.1 (`swiftlang-6.3.2.1.108`) |
| Toolchain (fresh repro, this leg) | Apple Swift 6.3.3 (`swiftlang-6.3.3.1.3`), CLI default |
| OS / arch | macOS 26.5.1 (25F80), arm64 (Mac15,13) |
| Build config | reproduces in **DEBUG and RELEASE** (`-Onone` and `-O`) — NOT opt-level-gated |
| Package | swift-foundations/swift-io (`main` @ `8ea9692e`), test target `IO Events Tests` |

---

## Crash signature

```
EXC_BAD_ACCESS (code=1, address=0x10)   KERN_INVALID_ADDRESS at 0x10   (far = 16)
Thread (triggered), queue com.apple.root.default-qos.cooperative

#0  __Dictionary<>.insert<A, B>(key:value:)                     <stdin>
#1  closure #1 in ISO_9945.Kernel.Event.Driver.init(add:modify:remove:arm:poll:close:)
                                                                Kernel.Event.Driver.swift:136
#2  partial apply for closure #1 in …Driver.init(…)             <compiler-generated>
#3  ISO_9945.Kernel.Event.Source.register(descriptor:interest:) Kernel.Event.Source.swift:50
#4  SourceContractTests.`poll drops events for deregistered IDs`() IO.Event.Driver.Contract.Tests.swift:151
```

Faulting-thread register `x[9]` (fresh repro) / `x[10]` (record) holds:

```
demangling cache variable for type metadata for
  __Dictionary<__HashIndexed<Buffer<Storage<Memory.Allocator<Memory.Heap>><>
    .Contiguous<Hash.Entry<Tagged<ISO_9945.Kernel.Event, UInt>,
                           ISO_9945.Kernel.Event.Driver.Registration>>><>.Linear>>
```

Under `SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1` the preceding stderr line is the exact §A9
signature:

```
failed type lookup for <symbolic-mangled-name>: unknown error
```

The `.insert<A,B>` tries to materialize the full type metadata of the composed
`__Dictionary<__HashIndexed<… Hash.Entry<Tagged<…>, …> …>>` engine via its
demangling cache; `swift_getTypeByMangledName` returns `TypeLookupError("unknown error")`;
the load of the null metadata pointer at offset `+0x10` faults.

Evidence `.ips` files:
- `evidence/ips-of-record-020857.ips` — the crash of record (2026-07-06 02:08, Xcode 6.3.2).
- `evidence/io-fresh-repro-112246.ips` — fresh in-package repro this leg (6.3.3, worktree).
- `evidence/reducer-t1-minimal-112726.ips` — the minimal reducer (t1), frame-identical `#0`.

---

## Production shape

```swift
// swift-iso-9945, ISO 9945 Core, Kernel.Event.ID.swift:25
public typealias ID = Tagged<ISO_9945.Kernel.Event, UInt>            // the Tagged KEY

// swift-kernel, Kernel Event, Kernel.Event.Driver.Registration.swift:20
package struct Registration: ~Copyable, Sendable { … }               // the ~Copyable value

// swift-kernel, Kernel.Event.Driver.swift:119,136 (inside `init(add:…)`'s Shared class)
typealias Registry = Dictionary_Primitives.Dictionary<Kernel.Event.ID, Registration>
shared.registry.insert(key: id, value: Registration(descriptor: box.take()!, interest: interest))  // ← SIGSEGV
```

swift-io compiles with `-enable-experimental-feature SuppressedAssociatedTypes`
(Package.swift) — the feature whose incomplete-on-6.3 codegen §A9 pins as the root cause.

---

## Factor bisection

A 5-target reducer (`reducer/`) imports the **real** `Kernel.Event.ID` (a
`Tagged_Primitives.Tagged`) + the **institute** `Dictionary_Primitives.Dictionary`,
and isolates each candidate factor. All targets built and run on the CLI-default 6.3.3.

| # | Target | Key | Value | Context | DEBUG | RELEASE |
|---|--------|-----|-------|---------|-------|---------|
| t0 | control | `UInt` (non-Tagged) | `~Copyable` struct | straight-line | **PASS** (0) | — |
| t1 | tagged-copyable | `Kernel.Event.ID` (Tagged) | `Int` (**Copyable**) | straight-line | **CRASH** (139) | **CRASH** (139) |
| t2 | tagged-noncopyable | `Kernel.Event.ID` (Tagged) | `~Copyable` struct | straight-line | **CRASH** (139) | **CRASH** (139) |
| t3 | closure | `Kernel.Event.ID` (Tagged) | `~Copyable` struct | `@Sendable` closure on a `final class` | **CRASH** (139) | **CRASH** (139) |
| t4 | actor | `Kernel.Event.ID` (Tagged) | `~Copyable` struct | detached cooperative `Task` | **CRASH** (139) | **CRASH** (139) |

Every crashing target emits the `failed type lookup … unknown error` §A9 signature and
`t1`'s frame `#0` is byte-identical to production (`__Dictionary<>.insert<A,B>`, same
`x[9]` metadata symbol, same `0x10` fault) with `#1 main` instead of the Driver closure.

### Minimal trigger (3 meaningful lines)

```swift
import Dictionary_Primitives
import ISO_9945_Core
import Hash_Tagged_Primitives

var d = Dictionary_Primitives.Dictionary<ISO_9945.Kernel.Event.ID, Int>()
_ = d.insert(key: .init(Int32(7)), value: 42)   // ← SIGSEGV (exit 139)
```

### What the bisection establishes (refinements over §A9)

1. **Tagged key is the load-bearing factor** — `t0` (non-Tagged `UInt` key) PASSES;
   every Tagged-key target crashes.
2. **§A9 axis-C open cell RESOLVED**: institute `Dictionary` + Tagged key + **Copyable**
   value (`t1`, `Int`) **CRASHES**. The `~Copyable` *user value* is **not** required for
   the institute container — the `__Dictionary`/`__HashIndexed`/`Hash.Entry`/`Buffer.Linear`
   engine itself composes `~Copyable` types into the mangled name, satisfying §A9's
   "`~Copyable` somewhere in the full mangled name" collapsed signal independent of the
   value. (Contrast stdlib `Dictionary` + Tagged key + Copyable value = **PASS**, §A9
   var-isolation row `Dictionary<Tagged<Tag, UInt>, Int>`.)
3. **Not DEBUG-only**: crashes in **RELEASE** too (`t1`–`t4`, `-O`, exit 139). This is an
   emission/codegen defect (consistent with §A9, whose fix travels with the binary), NOT
   an optimizer bug — and cleanly distinct from §A15 (which is `-Onone`-only and broken
   on every toolchain incl. 6.5-dev). The insert path forces the metadata in both modes;
   only a fully-specialized fast path (e.g. §A9's `Atomic<Tagged>.load`) would evade it.
4. **Closure/actor context is incidental**: straight-line `main` reproduces (`t1`). The
   production `@Sendable` `_register` closure + cooperative-executor context are not causal.

---

## §A9 comparison

| Axis | §A9 (established) | This site |
|------|-------------------|-----------|
| Trigger type | `Tagged_Primitives.Tagged` in a generic container forcing full metadata | `Tagged<ISO_9945.Kernel.Event, UInt>` key in institute `Dictionary`/`__HashIndexed` — same |
| Signature | `swift_getTypeByMangledName` → `TypeLookupError("unknown error")` → null-metadata deref `0x10` | identical (`far=16`, `failed type lookup … unknown error`) |
| Container-agnostic (axis B) | stdlib `Dictionary`, institute `Dictionary`, `Set.Ordered`/`Hash.Table`, `Parser.Machine` all crash | institute `Dictionary`/`__HashIndexed` engine — a predicted new surface |
| Root cause | incomplete `SuppressedAssociatedTypes` codegen on 6.3 | same (swift-io enables the feature) |
| Fix | 6.4-dev+ (fix travels with the binary) | inherited (per 2026-06-01 Set.Ordered new-site precedent — direct re-run on a dev snapshot deferred; snapshots currently trip forward gates) |
| Disposition | no Institute code fix; `compiler(<6.4)` `.disabled(if:)` guard; require 6.4+ | same |

**Historical note.** This is §A9 site 3 (the io/kernel `Kernel.Event.Driver` registry)
re-manifesting one consumer out. Its 2026-05-22 raw-storage workaround (`a79ca49`) was
reverted 2026-05-23 (`44ab1f8`) on correctness grounds, and the ADT-tower reshape then
(a) relocated the code from `swift-kernel` into `ISO_9945.Kernel` and (b) respelled the
registry from the old container onto the new `Hash.Indexed`-backed `__Dictionary` engine
— the same reshape `Set.Ordered` underwent (`3e44537`), whose 2026-06-12 re-probe
confirmed the new engine still SIGSEGVs (axis-B container-agnosticism holds for the new
backing). No green history was ever possible at prior pins: the io test path was
unbuildable until the W2 consumer dominoes landed, at which point the crash appeared.

---

## Reducer

`reducer/` is a self-contained SwiftPM package (5 executable targets above). It is kept
nested rather than wired into the Issues umbrella `Package.swift` because its transitive
graph (`swift-iso-9945`) is far heavier than the umbrella's current deps, and the §A9
family is already umbrella-represented by
`swift-issue-tagged-noncopyable-atomic-metadata-crash`. To run:

```bash
cd reducer
rm -f Package.resolved && swift build            # DEBUG; then swift build -c release
for t in t0-control t1-tagged-copyable t2-tagged-noncopyable t3-closure t4-actor; do
  SWIFT_DEBUG_FAILED_TYPE_LOOKUP=1 .build/debug/$t; echo "[$t] exit=$?"
done
# t0 → exit 0 ; t1..t4 → exit 139 (SIGSEGV) with "failed type lookup … unknown error"
```

---

## Disposition / workaround

Per [`ISSUE-008`] "fixed on dev, not in Xcode": no Institute-side code fix (the
raw-storage wrapper is rejected on correctness grounds — §A9 Update 2026-05-23). The io
`SourceContractTests` suite is guarded with a `.disabled(if: Toolchain.hasTaggedMetadataSIGSEGV)`
trait gated on `compiler(<6.4)` — a `.disabled(if:)` trait, NOT `withKnownIssue` (a
SIGSEGV kills the runner before swift-testing can register a known issue; only skipping
the body yields a clean 6.3.x run, and the guard auto-recovers on 6.4+). Staged on the
swift-io worktree branch `adt-tower-io-crash` (committed, not landed).

---

## See also

- `swift-institute/Research/swift-compiler-bug-catalog.md` §A9 — canonical ecosystem entry (addendum drafted this leg)
- `swift-issue-tagged-noncopyable-atomic-metadata-crash/` — the §A9 sibling Issues entry (Atomic/`.advance` + `Set.Ordered` sites)
- swift-io `Tests/Support/Toolchain.swift` (staged) — the `compiler(<6.4)` gate, mirroring graph's guard
