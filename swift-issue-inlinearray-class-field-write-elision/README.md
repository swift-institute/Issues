# Swift Issue: `InlineArray`-backed value field stored in a class field has its writes elided under `-O`

**Classification**: miscompile (silent wrong codegen — dead-store elision of inline-value
field writes; no diagnostic, no crash). Sparse data silently lost in release.
**Upstream**: NOT filed (institute standing rule: never file upstream to swiftlang; this
directory is the terminal record).
**Status**: BROKEN on Apple Swift 6.3.2 (`swiftlang-6.3.2.1.108`), macOS arm64,
`swift test -c release` / `swiftc -O`. Debug (`-Onone`) is correct.
**Reproducer**: NO standalone minimal reproducer (see "Reducers" — three minimal variants
all PASS; the bug needs the full `Store.Inline` + `Bit.Vector.Static` + generic-`Box` stack,
exactly as [`swift-issue-rawlayout-noncopyable-deinit`](../swift-issue-rawlayout-noncopyable-deinit/)
/ [`swiftlang/swift#86652`](https://github.com/swiftlang/swift/issues/86652) report for their
family). The authoritative reproduction is the in-package release test (below).
**Workaround**: none clean within scope. The affected shape (a buffer-owned class `Box`
holding an inline `InlineArray` bitmap **sibling** to a `~Copyable` `@_rawLayout` substrate)
is release-broken; the institute deferred it to an architecture decision
(an internal working document — leaf-owned occupancy probe). The release-broken
tests are skip-guarded under `-O`.

## Summary

A value type backed by `InlineArray<n, UInt>` (`swift-bit-vector-primitives`
`Bit.Vector.Static`, wrapped in `Buffer.Slab.Header.Static`) is stored in a `final class`
field (`Buffer.Slab.Inline.Box.header`), **alongside** a `~Copyable` `@_rawLayout`-backed
substrate (`Store.Inline`, `swift-storage-primitives`). Under `-O`, **in-place subscript /
property writes to the `InlineArray`-backed field through the class reference are dropped**:

- `box.header.bitmap[slot] = true` (occupancy bit) → not persisted.
- `box.storage.initialization = .empty` (the ledger reset, an enum field of the `~Copyable`
  storage) → not persisted.

The **element write survives** because it goes through `Store.Inline`'s raw pointer
(`withUnsafeMutablePointer(to: &_storage)`), not a value-field store. So the data is written
to memory but the occupancy bitmap that records *which* slots are live is silently empty in
release. A subsequent `occupancy` / `isOccupied` read returns 0 / false; sparse occupancy is
lost. Debug (`-Onone`) does not elide the writes and is correct.

## Authoritative reproduction (in-package)

```
cd ~/Developer/swift-primitives/swift-buffer-slab-primitives
swift test            # 68 tests pass (debug)
swift test -c release # "Buffer.Slab.Inline" suite fails with 8 issues:
                      #   insert(42,at:2) then occupancy → 0  (expected 1)
                      #   sparse insert(0,4,7) then isOccupied(0/4/7) → false (expected true)
                      #   firstVacant() → 0 with slots occupied; isFull → false when full
```

The failures are exclusively the bitmap-state reads after a write. A deinit-counting
single-free test PASSES in release **by accident**: the dropped ledger-reset leaves the
substrate ledger `.linear(n)`, and that test's *contiguous* inserts make the substrate
oracle free the right (contiguous) slots — sparse occupancy would free the wrong slots.

## Isolation (what is and is not the trigger)

| Probe | Result under `-O` |
|-------|-------------------|
| **Element write** (`Store.Inline.initialize`, raw pointer) | persists ✓ |
| **Local** `var h: Header.Static; h.bitmap[i] = true; h.occupancy` | persists ✓ (write is NOT generally broken) |
| `box.header.bitmap[i] = true` via `_read`/`_modify` forwarder | **dropped** ✗ |
| `box.header.bitmap[i] = true` via direct `box.X` access | **dropped** ✗ |
| `box.header.bitmap[i] = true` via a `Box` method (`self.header…`) | **dropped** ✗ |

Three structural variants (forwarders / direct / Box-methods) fail identically after clean
release rebuilds. The write only persists when the field is a local value, not a class-stored
value mutated through the reference — and only in this full stack.

## Reducers (all PASS — minimal cases do not reproduce)

`evidence/`:
- `reducer-C-plain.swift` — `InlineArray` directly in a class field, and nested in two
  structs in a class field. Both correct under `-O`.
- `reducer-B-generic-box-deinit.swift` — generic `class Box<S: ~Copyable>` with a deinit that
  reads the `InlineArray`-backed bitmap (word/mask RMW), mutated through a `~Copyable` wrapper
  struct's method. Correct under `-O`.
- `reducer-A-rawlayout-sibling.swift` — adds a `@_rawLayout` sibling field next to the
  `InlineArray` bitmap in the class. Correct under `-O`.

So the trigger requires more than any of these in isolation — most likely the real
`Store.Inline` (generic `@_rawLayout(likeArrayOf: Element, count: n)` + `_deinitWorkaround:
AnyObject?` + `Store.Initialization` ledger) co-located with the `Bit.Vector.Static`
`InlineArray` bitmap and reached through a generic `S: Store.Protocol` substrate. Reducing
further is pending (matches the `swift-issue-rawlayout-noncopyable-deinit` "needs ≥3-package
full stack" situation).

## Relationship to `#86652` / `swift-issue-rawlayout-noncopyable-deinit`

Same family: full-stack-only, minimal-reducers-pass, `@_rawLayout`/inline storage + optimizer.
**Distinct symptom**: `#86652` / `rawlayout-noncopyable-deinit` omit element **destruction**
(deinit / value-witness); this issue elides element-field **writes** (operations). Whether
they share a root is open.

## Disposition

This finding is a primary technical input to the institute's deferred "sparse occupancy
placement" decision (an internal working document): a
buffer-owned class `Box` over inline storage is release-broken; the leaf-owned alternative
(occupancy bitmap in a `@_rawLayout` leaf, not a class value-field) plausibly sidesteps it
and is the decision's probe-first next step. The buffer-owned interim does NOT ship for the
inline slab until that ruling lands.
