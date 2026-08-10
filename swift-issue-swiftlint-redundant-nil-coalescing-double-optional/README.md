# `swift-issue-swiftlint-redundant-nil-coalescing-double-optional`

SwiftLint's `redundant_nil_coalescing` fires on `?? nil` applied to a
**double optional** (`T??`), where the operator is the flattening step and
not dead code. `swiftlint --fix` deletes it, the file stops compiling, and
the very next `swiftlint lint --strict` reports the broken file **clean**.

Upstream instrument: [realm/SwiftLint](https://github.com/realm/SwiftLint)
built-in rule `redundant_nil_coalescing`, enabled fleet-wide via the Tier 1
`opt_in_rules` list in `swift-institute/.github`'s `.swiftlint.yml`. This is
**not** a `swift-foundations/swift-linter` rule and not a compiler defect.

## Minimal reproduction

`Sources/Reproducer/Fixture.swift.txt`, linted under
`Sources/Reproducer/Config.yml.txt` (`only_rules: [redundant_nil_coalescing]`):

```swift
public static func doubleOptional<C: Collection>(_ bytes: C) -> Int? where C.Element == UInt8 {
    let fast: Int? =
        bytes.withContiguousStorageIfAvailable { (buffer: UnsafeBufferPointer<UInt8>) -> Int? in
            buffer.isEmpty ? nil : Int(buffer[0])
        } ?? nil
    return fast
}
```

`withContiguousStorageIfAvailable` returns `Int??`: the **outer** optional is
`nil` when the collection has no contiguous storage, the **inner** optional is
the closure's own result. `?? nil` flattens `Int??` to `Int?`.

```sh
swiftc -typecheck -swift-version 6 Sources/Fixture.swift   # exit 0
swiftlint lint --strict --no-cache                          # 2 violations
swiftlint --fix --no-cache                                  # both `?? nil` deleted
swiftc -typecheck -swift-version 6 Sources/Fixture.swift   # error
swiftlint lint --strict --no-cache                          # 0 violations
```

## Measured

Against the **exact instrument the fleet's CI runs**: SwiftLint `0.63.3`
`swiftlint_linux_amd64`, sha256
`26db741d43f2f2dc26c0cf16911100a3e186c3d1dbb59e55ad3ac87b0de4538f` — the
`SWIFTLINT_SHA256` pin in `swift-institute/.github`'s `swift-ci.yml` — executed
inside the release-floor container image
`swiftlang/swift@sha256:8d614165059587ce9dcf6727a76aeff4cbf1cde41fde9a9281a43803be736224`
(`Swift version 6.4-dev`, `x86_64-unknown-linux-gnu`), the same image the `lint`
job declares. 2026-08-10.

| step | result |
| --- | --- |
| `swiftc -typecheck` before | exit 0 |
| `swiftlint lint --strict` | 2 × `redundant_nil_coalescing` (lines 8, 14) |
| `swiftlint --fix` | `Corrected redundant_nil_coalescing 2 times` |
| `swiftc -typecheck` after | `error: value of optional type 'Int?' must be unwrapped to a value of type 'Int'` |
| `swiftlint lint --strict` after | `Found 0 violations, 0 serious in 1 file` |

SwiftLint `0.65.0` on macOS arm64 (Homebrew) reproduces this identically.

### Positive control

`Probe.singleOptional` applies `?? nil` to an ordinary `Int?`. There the rule
is **right**: the operator is dead code and the correction is sound. It is
reported in the same run as the hazard site, which is what proves the
instrument ran and the rule was enabled — a run that reported nothing would be
indistinguishable from a broken configuration.

### Hazard-shape control

The two sites differ **only** in the optionality depth of the coalesced
expression. Restoring `?? nil` at the double-optional site alone restores
compilation; restoring it at the single-optional site alone does not change
compilation either way. The optionality of the left-hand expression is
therefore the discriminator, isolated by substitution.

## The precise predicate that is wrong

`redundant_nil_coalescing` matches `?? nil` on the syntax of the operator and
its right-hand operand alone. It does not consult the **type** of the
left-hand expression, so it cannot distinguish `T? ?? nil` (redundant) from
`T?? ?? nil` (flattening). The rule needs the left-hand expression to be a
single optional; that is a type-level fact SwiftLint's syntax-only rule engine
does not have.

The second half is independent of the first: after the correction, the file
does not compile, and `swiftlint lint --strict` still exits 0. Lint cannot
detect that its own correction broke the build.

## Production site

`swift-foundations/swift-json`, `Sources/JSON/JSON.Decode.swift:51` and
`Sources/JSON/JSON.Serializable.swift:223`. Both return `Self?` from the
closure, where the post-correction diagnostic reads `declared closure result
'Self?' is incompatible with contextual type 'Self'`. The concrete `Int?`
reduction here produces the unwrap diagnostic instead; the class is the same.

At the time of measurement both production sites still carry `?? nil` — the
lane reverted its correction.

## Workaround

`.flatMap { $0 }` in place of `?? nil` is semantically exact on a double
optional and is not matched by the rule. Not a suppression.

## Filed

`swift-foundations/swift-institute-linter-rules#70` (filed there by the
discovering lane; the rule's actual owner is upstream SwiftLint plus the Tier 1
`.swiftlint.yml` that enables it).

## Verdict

**GENUINE DEFECT.** Independently reproduced from a minimal fixture on the
CI-exact instrument, with a positive control and a substitution-isolated
discriminator.
