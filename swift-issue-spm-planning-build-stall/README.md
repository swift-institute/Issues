# Swift Issue: SwiftPM Planning-Build Stall at Heavy Consumers

> **Per-issue restructure: deferred 2026-05-12.** The minimum reproducer for
> this bug is a multi-package SwiftPM workspace topology with URL/local
> identity-dedup edges, not a single-file Swift snippet. The per-issue
> convention set by sibling
> [`swift-issue-pointer-arithmetic-linux-miscompile/`](../swift-issue-pointer-arithmetic-linux-miscompile/)
> assumes a single `swiftc`-buildable `Tests/Reproducer.swift` +
> `Sources/Reproducer/main.swift` pair; SwiftPM planner-stage bugs at
> workspace topology don't fit that shape. The forensic record below +
> [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) carry the audit trail; a
> minimal multi-package SwiftPM fixture is still listed as "pending" below.

**Upstream destination**: `swiftlang/swift-package-manager` (adjudicated
2026-07-30 under Issues#69/#79: SwiftPM reproducers stay in this
repository; only the upstream target differs from the compiler entries).
**Upstream**: [`swiftlang/swift-package-manager#9441`](https://github.com/swiftlang/swift-package-manager/issues/9441)
(symptom match; verified closed as completed on 2026-07-30), with the
workaround documented by
[PR #9493](https://github.com/swiftlang/swift-package-manager/pull/9493)
(merged 2025-12-12). The exact planner-stage bug at our workspace's
URL/local-identity-dedup topology is a separate variant — PR #9493's fix is
present in the 2026-03-16 dev snapshot, and the snapshot still reproduces
our stall identically. Not yet filed as a standalone issue.
**Eligibility (2026-07-30): NOT YET ELIGIBLE for upstream filing.** No
reproducer fixture is retained. Missing, precisely: a synthetic
multi-package workspace with URL/local identity-dedup edges that stalls in
the planning stage — the same scripted-generator approach the sibling
[`swift-issue-spm-identity-conflict-path-enumeration-hang`](../swift-issue-spm-identity-conflict-path-enumeration-hang/)
uses (`evidence/gen-synthetic.sh`) is the stated path to eligibility.
Filing remains principal-gated once a fixture exists.
**Status**: RESOLVED via structural workaround (comprehensive URL-to-local
mirror config). Root-cause toolchain bug fixed upstream in Swift 6.3-dev (PR
#9493, merged 2025-12-12) but not yet in Apple Swift 6.3.1 (Xcode 26.4.1).
**Productionized mitigation**: [`coenttb/swift-package-mirrors`](https://github.com/coenttb/swift-package-mirrors)
(private). A minimal SwiftPM reproducer mirrored into this directory as a
test target is pending.

## Forensic Record

This subdirectory holds the per-issue forensic notes migrated from
`swift-institute/Research/` on 2026-05-11:

- [`INVESTIGATION-ARC.md`](INVESTIGATION-ARC.md) — Full investigation: hot
  loop in `_platform_memmove`-deep stack inside swift-package's planning
  code, URL/local identity-dedup walk, refuted hypotheses (duplicate-product
  declarations, etc.), and the comprehensive-mirroring structural mitigation.
