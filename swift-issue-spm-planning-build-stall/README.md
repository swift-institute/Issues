# Swift Issue: SwiftPM Planning-Build Stall at Heavy Consumers

**Upstream**: [`swiftlang/swift-package-manager#9441`](https://github.com/swiftlang/swift-package-manager/issues/9441)
(symptom match), with the workaround documented by
[PR #9493](https://github.com/swiftlang/swift-package-manager/pull/9493)
(merged 2025-12-12). The exact planner-stage bug at our workspace's
URL/local-identity-dedup topology is a separate variant — PR #9493's fix is
present in the 2026-03-16 dev snapshot, and the snapshot still reproduces
our stall identically. Not yet filed as a standalone issue.
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
