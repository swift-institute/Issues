# Swift Issue: serialized extension-lookup-table `dataLength` overflows `uint16_t` when a type has too many extensions

**Upstream:** **STAGED — not yet filed.** Standalone single-file `swiftc -emit-module` reducer per the [ISSUE-002] gold standard. A duplicate search (below) surfaced no existing report of this size-limit overflow. Filing to `swiftlang/swift` is gated on explicit principal approval.

**Classification:** dual manifestation of one serialization defect —
- **ICE / compiler crash** (signal 6, assertion) on **asserts-enabled** toolchains, and
- **silent module miscompile** (a truncated extension table that later makes valid member references fail to resolve) on **release** toolchains.

## Summary

Swift serializes, per module, an on-disk extension-lookup table keyed by a type's
**base name**. For each key it writes a `dataLength` header. `dataLength` is computed
as a `uint32_t` but **written and read back as a `uint16_t`**, so it silently wraps once
the serialized data for a single base name exceeds **65535 bytes**.

The data for a base name grows with the number of `extension`s of types carrying that
name:

```
dataLength(baseName) = 8 · (#extensions of types named baseName)
                     + Σ  mangledNameSize(extended nominal)   // only for NESTED extended types
```

(A module-scope extended type contributes only its 8-byte term; a **nested** extended
type — e.g. `Outer.Inner` — additionally contributes the size of its mangled name, so it
overflows with far fewer extensions.)

When the sum crosses 65535:

- **Asserts toolchain** → `swiftc -emit-module` aborts:
  ```
  Assertion failed: (dataLength == static_cast<uint16_t>(dataLength)),
  function EmitKeyDataLength, file Serialization.cpp, line 239.
  ```
- **Release toolchain** → the assert is compiled out; the length wraps mod 65536; the
  table is written **truncated**; the module emits with exit 0. Downstream consumers then
  cannot resolve members that live past the truncation point:
  ```
  error: type '`Burgerlijk Wetboek`.`2`' has no member 'Artikel 999'
  ```

The release path is the more dangerous of the two: a **shipping** compiler silently
produces a `.swiftmodule` whose public API is partly unreachable, with no diagnostic at
producer or consumer beyond a generic "has no member".

## Exact signatures (both verified)

**Asserts toolchain** — `swift-frontend` aborts during module emission:
```
Assertion failed: (dataLength == static_cast<uint16_t>(dataLength)),
function EmitKeyDataLength, file Serialization.cpp, line 239.
Please submit a bug report ... and include the crash backtrace.
Stack dump:
0.  Program arguments: .../swift-frontend -frontend -emit-module ...
```

**Release toolchain** — emit succeeds (a ~1 MB `.swiftmodule` is written), then a consumer:
```
error: type '`Burgerlijk Wetboek`.`2`' has no member 'Artikel 999'
error: type '`Burgerlijk Wetboek`.`2`' has no member 'Artikel 500'
error: type '`Burgerlijk Wetboek`.`2`' has no member 'Artikel 250'
```
(The truncation is severe — not merely the tail; mid-range members are dropped too.)

## Minimal reproducer

`reproducer.swift` — one nested namespace `` `Burgerlijk Wetboek`.`2` `` with **N = 1000**
sibling article extensions, each adding a trivial nested `struct`. Built with **bare
`swiftc -emit-module`** (no SwiftPM, no flags, no features):

```swift
public enum `Burgerlijk Wetboek` { public enum `2` {} }
extension `Burgerlijk Wetboek`.`2` { public struct `Artikel 0` {} }
extension `Burgerlijk Wetboek`.`2` { public struct `Artikel 1` {} }
// … 998 more …
```

```bash
# Asserts toolchain — hard crash:
swiftc -emit-module -module-name Burgerlijk_Wetboek_Boek_2 \
       -o /tmp/m.swiftmodule reproducer.swift          # signal 6, EmitKeyDataLength

# Release toolchain — silent truncation, exposed by a consumer:
mkdir -p /tmp/m
swiftc -emit-module -module-name Burgerlijk_Wetboek_Boek_2 \
       -o /tmp/m/Burgerlijk_Wetboek_Boek_2.swiftmodule reproducer.swift   # exit 0 (!)
printf 'import Burgerlijk_Wetboek_Boek_2\nlet _ = `Burgerlijk Wetboek`.`2`.`Artikel 999`.self\n' > /tmp/c.swift
swiftc -typecheck -I /tmp/m /tmp/c.swift               # error: has no member 'Artikel 999'
```

**Expected (post-fix):** both build cleanly and the consumer resolves every article.

### Threshold

On the toolchains below, the faithful reproducer (nested `` `Burgerlijk Wetboek`.`2` ``)
overflows between **N = 750 (ok)** and **N = 800 (overflow)**. The exact N depends on the
mangled-name size of the extended type: a generic short-named nested type (`Outer.Inner`)
needs ≈ 2450 extensions; a longer / cross-module-referenced nested name needs far fewer.
The real package that surfaced this (below) overflows at **736**. `reproducer.swift` ships
N = 1000 for a reliable margin on both toolchains — bump N if a future toolchain mangles
more compactly.

## Root cause

`lib/Serialization/Serialization.cpp`, `class ExtensionTableInfo` (the
`llvm::OnDiskChainedHashTableGenerator` trait for the module's extension table):

- `getNameDataForBase(nominal)` returns the extended nominal's mangled-name size
  (**positive**, added to `dataLength`) when the nominal is nested, or a **negative**
  module-reference id (not added) when it is module-scope.
- `EmitKeyDataLength(...)` computes
  `uint32_t dataLength = (sizeof(uint32_t) * 2) * data.size();` then adds each positive
  `getNameDataForBase`, asserts `dataLength == static_cast<uint16_t>(dataLength)`
  (**line 239**), and writes it with `writer.write<uint16_t>(dataLength)`.

The width is the whole bug: the value is accumulated in 32 bits, range-checked only under
`assert`, and then narrowed to 16 bits on the wire. The paired reader deserializes the same
16-bit width, so a producer that wraps writes a length the consumer reads as
`length mod 65536`, truncating the entry.

## Why a real package has this many extensions

This is **not** a stress test — it is the natural shape of a faithful legal encoding.

The Swift Institute / rule-institute legal-encoding convention encodes each **statutory
provision as its own type in its own file** (one-type-per-file), nested under its code/book
namespace via an `extension`. *Burgerlijk Wetboek Boek 2* (Dutch Civil Code, Book 2) has
**698 articles**; each is `extension `Burgerlijk Wetboek`.`2` { struct `Artikel N` { … } }`,
and multi-paragraph articles add nested `lid` structs — **736 extension-table entries for
the single base name `2`**. The 1:1 correspondence with the legal source is the point: every
article is independently addressable, documented (uniform DocC), and unit-tested, and the
namespace mirrors the statute's own `Boek → Titel → Artikel → lid` structure.

Civil-law codes are large by nature (the BW spans thousands of articles across ten books),
so any faithful encoding produces thousands of extensions of a small set of book namespaces.
The same ceiling is reachable by **any** domain that models a large flat catalog as N
extensions of one namespace type — code generators, DSLs, per-case type families,
protocol-witness tables, etc.

## Affected toolchains (verified)

| Toolchain | `swift --version` | Behavior |
|---|---|---|
| Xcode default (release / NoAsserts) | `Apple Swift version 6.3.3 (swiftlang-6.3.3.1.3 clang-2100.1.1.101)`, `arm64-apple-macosx26.0` | **Silent** emit; consumer cannot resolve truncated articles |
| DEVELOPMENT-SNAPSHOT-2026-05-27-a (`org.swift.64202605271a`, +assertions) | `Apple Swift version 6.5-dev (LLVM 8f81a64f6a8bcf6, Swift 4d0c97fa5b05711)`, `arm64-apple-macosx26.0` | **Crash** at `EmitKeyDataLength`, `Serialization.cpp:239` |

The `uint16_t` narrowing is present on `main`, so every current toolchain is affected; the
assertion is merely the visible face of it on +assertions builds.

## Suggested fix

1. **Widen the on-disk width.** Serialize the extension-table `dataLength` (and, for safety,
   `keyLength`) as `uint32_t`, or as a VBR/variable-length quantity, in both the writer
   (`ExtensionTableInfo::EmitKeyDataLength`) and the paired reader. This is a module-format
   change and needs a format-version bump.
2. **At minimum, fail loudly on release.** Replace the `assert` with a real serialization
   diagnostic ("type `X` has too many extensions to serialize") so a **shipping** compiler
   never silently emits a truncated, partly-unreachable module. The silent-truncation path
   is the worst manifestation and should not depend on `+assertions` to be caught.

## Duplicate search

No existing report of this **size-limit / count-limit** overflow was found. The nearest
historical serialization issues are **distinct** — they are deserialization *ordering* /
*cross-reference* crashes, not a `uint16` length overflow driven by extension count:

- [#46791 (SR-4208)](https://github.com/swiftlang/swift/issues/46791) — crash deserializing a module where one extension uses another (ordering, not size).
- [#46500 (SR-3915)](https://github.com/swiftlang/swift/issues/46500) — crash during deserialization in the merge-module step.
- [#47806 (SR-5231)](https://github.com/swiftlang/swift/issues/47806) — cross-reference deserialization failure.
- [#46493 (SR-3908)](https://github.com/swiftlang/swift/issues/46493) — extension methods visible without importing (lookup, not serialization size).

## Workaround (consumer side)

Until the format is widened, the only lever is to **reduce the number of extension-table
entries for the overflowing base name** — i.e. put more provisions per `extension` block.
Note that **one extension per article does not help** (it is already one per article — 698
blocks); the entry count is what overflows, so relief requires *coarser* grouping:

- **Several articles per shared `extension` block** (e.g. one `extension `…`.`2` { … }` per
  *Titel*, declaring that Titel's articles as members) collapses ~698 entries toward the
  number of groups. Fewest entries, but couples provisions in one file (against
  one-type-per-file) and is what the package's constraints currently forbid.
- **Split the base name** across more namespaces (e.g. `Boek2A` / `Boek2B`, or a per-Titel
  sub-namespace) so no single base name accrues > ~730 entries. Also currently constrained
  out (flat `BW.`2`` spelling is required).

Neither is desirable; the real fix is upstream (widen the width). See the package handoff
for the constraint context.

## CI validation (this entry is wired into the Issues repo CI)

Because the asserts path aborts the compiler mid-emit, the trigger ships as a **resource**
(`Sources/Reproducer/Crash.swift.txt`) and is compiled **out of process**. Both harnesses
detect **both** manifestations — the `EmitKeyDataLength` abort (asserts) **and**, when emit
succeeds, a consumer that cannot resolve `Artikel 999` against the truncated module (release):

- `Tests/Reproducer.swift` — Swift Testing harness wrapping the probe in `withKnownIssue(...)`.
  **Green while the bug fires; flips red the moment an upstream fix lands** (emit succeeds and
  the consumer resolves every article).
- `Sources/Reproducer/main.swift` — standalone exit-code probe (`exit(1)` bug fired / `exit(0)`
  absent or inconclusive).
