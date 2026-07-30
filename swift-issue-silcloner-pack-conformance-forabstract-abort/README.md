# swift-issue-silcloner-pack-conformance-forabstract-abort

`swift-frontend` aborts (signal 6) when a SILCloner client pass remaps a
substitution map that carries a **pack conformance** while an **active pack
expansion** is in flight. The cloner's no-substitution-map conformance fallback
projects a pack element lane onto the conforming pack archetype; the resulting
`PackElementType` subject reaches `ProtocolConformanceRef::forAbstract`, which
cannot represent it:

```
Abort: function forAbstract at ASTContext.cpp:5924
Abstract conformance with bad subject type:
(element_type level=1
  (pack=pack_archetype_type conforms_to="Swift.(file).Equatable" name="each V"
    (interface_type=generic_type_param_type depth=0 index=0 name="V" param_kind=pack)))
```

## Upstream status

- **Matched upstream issue:** [swiftlang/swift#90275] — same abort, same
  `PackConformance::subst` / `InFlightSubstitution::expandPackExpansionShape`
  frames (there via `MandatoryAllocBoxToStack`). **Do not file a duplicate.**
- **Fix:** [swiftlang/swift#89916] *[SILCloner] Preserve expansion level when
  cloning pack conformances* (mainline [swiftlang/swift#89834]), merged to
  `release/6.4.x` as `5462b4ed24fafb0eabe28e32e6f06ae802f01f31`. The fix sets
  the `PreservePackExpansionLevel` flag in `SILCloner::getOpSubstitutionMap`'s
  substitution, so it covers **every** SILCloner client pass at once.
- **Not on the 6.3 line.** The 6.3-required Institute release gates tracked at
  swift-institute/Issues#58 stay red until the fix (or a backport) reaches a
  usable 6.3 toolchain — that event is exactly what this entry's
  `withKnownIssue` red flip detects.

## Institute tracking

swift-institute/Issues#58 — observed in production as release + `-O` +
`-enable-default-cmo` + WMO aborts in `CrossModuleOptimization`
(`canSerializeFunction` → `SILCloner::visitTryApplyInst` →
`getOpSubstitutionMap`) while compiling `Records`,
`Structured_Queries_Primitives`, and — under a wasm-embedded SDK, where
Embedded mode forces CMO regardless of optimization level — `Render_Primitive`
at `-Onone` on macOS arm64.

## Version story (each row `swift --version`-confirmed, macOS arm64 host)

| Toolchain | Result |
|---|---|
| `6.3.3-RELEASE` (swift.org, via swiftly) | **ABORT** — signal 6, `forAbstract at ASTContext.cpp:5924`, pass `CapturePromotion` |
| Apple Swift 6.4 (Xcode toolchain) | clean |
| `6.4.x-snapshot-2026-07-23` (+assertions) | clean |
| `main-snapshot-2026-07-11` (6.5-dev, +assertions) | clean |

The two snapshots are assertions-enabled builds, so the abort would still fire
were the defect present — the clean results are fix evidence, not
asserts-off silence.

## Minimal reproducer

Single file, no dependencies (`Sources/Reproducer/Crash.swift.txt`):

```swift
public func trigger<each V: Equatable>(
  action: sending @escaping (repeat (each V, Bool)) -> ()
) -> ((repeat each V)) -> ()
{
  { o in
    action(repeat (each o, false || (each o != each o)))
  }
}
```

Probe:

```sh
swiftc -emit-sil -swift-version 6 Crash.swift -o /dev/null   # aborts on 6.3.3
```

Load-bearing ingredients — each verified by an A/B pair on 6.3.3-RELEASE
(removing exactly that ingredient compiles clean):

1. `sending` on the escaping closure parameter (`Sendable` on the pack
   elements is **not** required — dropped relative to the upstream regression
   test in [swiftlang/swift#89834]);
2. the `false || …` **autoclosure** nesting — a nested closure capturing the
   pack expansion;
3. the `each o != each o` apply inside the `repeat` expansion, whose
   substitution map carries the `Pack{repeat each V}: Equatable` pack
   conformance.

## Pass identity — one cloner, several client passes

The minimal shape aborts in `CapturePromotion`; the Institute production
builds abort in `CrossModuleOptimization` (via `visitTryApplyInst`), and
upstream #90275 aborts in `MandatoryAllocBoxToStack`. All three are SILCloner
clients reaching the same `getOpSubstitutionMap` → `PackConformance::subst` →
`forAbstract` path, and #89916's one-flag fix in `SILCloner.h` covers them
all — verified here by the clean 6.4/6.5 columns above in both the single-file
and the cross-module shape below.

Two controlled negatives worth recording: host-native macOS
`-O -enable-default-cmo` two-module builds of a pack-generic throwing
cross-module call did **not** reproduce (consistent with Issues#58's
macOS-native negatives), and the abort does not require CMO at all — the
mandatory pipeline's `CapturePromotion` is enough.

## Cross-module confirmation (wasm-embedded, CMO forced at -Onone)

The cross-module production shape was confirmed with a two-target SwiftPM
package — module `A` declaring `public protocol P: Equatable`, module `B`
containing the trigger constrained `<each V: P>` — built with the 6.3.3
wasm-embedded Swift SDK, where Embedded mode forces the optimizing pipeline at
`-Onone`:

```sh
swift build --swift-sdk swift-6.3.3-RELEASE_wasm-embedded   # 6.3.3 toolchain
```

Result: identical abort while compiling `B`, with the pack archetype's
conformance resolving to the **cross-module** `A.(file).P` — matching the
`Render_Primitive` / `Records` production topology. The same package builds
clean with `main-snapshot-2026-07-11` + `swift-DEVELOPMENT-SNAPSHOT-2026-07-11-a_wasm-embedded`.
The single-file `Crash.swift.txt` is shipped as the entry's trigger per the
bare-`swiftc` preference ([ISSUE-002]); the package shape is fully specified
by this section.

## Flip semantics

`Tests/Reproducer.swift` compiles the trigger out of process and wraps the
probe in `withKnownIssue("swiftlang/swift#90275 …", when: probed compiler < 6.4)`:

| Leg | Today | On fix reaching the line |
|---|---|---|
| 6.3-line toolchain | GREEN (known issue matched) | **RED — the detection signal** |
| 6.4+ toolchain | GREEN (gate off, probe passes unguarded) | GREEN (RED only on regression) |

`Sources/Reproducer/main.swift` is the standalone probe: exit 1 = bug fired,
exit 0 = clean or inconclusive.

## Workaround

None adopted. Institute policy for this defect (Issues#58): no source
workarounds, no CMO suppression, no optimization downgrade, no CI weakening.
The blocked Swift 6.3 release gates wait on the toolchain, and this entry is
the instrument that reports when the wait is over.

[swiftlang/swift#90275]: https://github.com/swiftlang/swift/issues/90275
[swiftlang/swift#89916]: https://github.com/swiftlang/swift/pull/89916
[swiftlang/swift#89834]: https://github.com/swiftlang/swift/pull/89834
