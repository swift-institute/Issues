# [Compiler][Rejects valid] Callable syntax rejects an escaped parameter label across modules

Canonical Issue: [swift-institute/Issues#114](https://github.com/swift-institute/Issues/issues/114)

Upstream: [swiftlang/swift#86058](https://github.com/swiftlang/swift/issues/86058)

## Trigger

A public type in one module has both an unlabeled initializer and an initializer
whose label is a backtick-escaped identifier containing spaces. In a second
module, callable syntax selects the unlabeled overload and rejects the value.
The explicit `.init` spelling selects the labeled initializer and succeeds.

## Reproduction

From the repository root:

```sh
swift test --filter swift_issue_callable_syntax_escaped_parameter_label
swift run swift-issue-callable-syntax-escaped-parameter-label-Repro
```

The test uses an out-of-process compiler and stages the two modules separately.
It verifies the `.init` control first, then checks that callable syntax fails.
`withKnownIssue` is green while the defect reproduces and flips red when the
upstream fix reaches the tested toolchain. The executable exits `1` while the
defect reproduces and `0` after it is fixed.

## Workaround

Use explicit initializer syntax:

```swift
Example.init(`the condition is satisfied`: true)
```

## Provenance

This portable reduction replaces the `@Splat`-generated fixture and its
package-local test formerly maintained by
[`swift-foundations/swift-splat`](https://github.com/swift-foundations/swift-splat).
It preserves the generated initializer shape, module boundary, failing callable
form, and successful explicit-initializer control without retaining a package
dependency or macro implementation.

The original report was recorded on Swift 6.2 / Xcode 26 beta. The active
upstream issue is the public coordinate above; no private or machine-local
information is included here.
