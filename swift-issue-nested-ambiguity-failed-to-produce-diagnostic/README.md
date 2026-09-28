# Swift Issue: "failed to produce diagnostic" when an ambiguous call is the argument of an ambiguous overloaded call

**Upstream:** **NOT FILED.** This directory is the institute's record.

**Classification:** Type-checker diagnostic failure. The input is ill-formed: the
inner call is genuinely ambiguous. The compiler does not report that ambiguity.
Instead it emits its internal fallback error, which asks the user to file a bug.
It is not a crash of the `swift-frontend` process, and there is no stack dump.

## Minimal reproducer

`reproducer.swift` (also staged as `Sources/Reproducer/Crash.swift.txt` for the
out-of-process harness):

```swift
protocol P {}
protocol Q {}
extension Int: P, Q {}
func make<T>(_ value: T) -> Int { 0 }
func make<each T>(_ value: (repeat each T)) -> Int { 0 }
func check(_ value: some P) {}
func check(_ value: some Q) {}
check(make(1))
```

```bash
xcrun swiftc -typecheck reproducer.swift
```

**Actual:**

```
reproducer.swift:8:1: error: failed to produce diagnostic for expression; please submit a bug report (https://swift.org/contributing/#reporting-bugs)
```

**Expected:** a real diagnostic. `_ = make(1)` on its own correctly reports
`error: ambiguous use of 'make'`, because a one-element pack `(repeat each T)` with
`T == Int` matches as well as the plain generic `T`. The same error, or
`ambiguous use of 'check'`, should appear here.

## Trigger characterization

Each ingredient was removed in turn; the result is a proper diagnostic unless noted.

| Ingredient | Removed / replaced by | Result |
|---|---|---|
| inner overload pair: generic `T` + tuple pack `(repeat each T)` | `T` + `[T]`, or a concrete `Int` + pack | proper `ambiguous use of …` |
| pack as a tuple `(repeat each T)` | variadic `repeat each T` | proper `ambiguous use of 'check'` |
| two outer overloads constrained on different protocols | one `check` | proper `ambiguous use of 'make'` |
| protocols unrelated to each other | `some P` vs `Int` / `Int` vs `Int?` | proper `ambiguous use of 'make'` |
| call nested as an argument | `let x = make(1)` | proper `ambiguous use of 'make'` |
| `some P` parameters | `<T: P>` generic parameters | still fails to diagnose |
| result builders / `@_disfavoredOverload` | not needed | still fails to diagnose |

`evidence/result-builder-shape.swift` shows the shape it was found in: a result
builder with a plain-generic and a tuple-pack `buildExpression`, passed to two
overloaded consumers.

## Toolchains

It fails the same way on every toolchain available here (macOS arm64), so it is
long-standing, not a 6.4 regression:

| `swiftc --version` | Result |
|---|---|
| Apple Swift version 6.3.3 (swift-6.3.3-RELEASE) | fails to produce diagnostic |
| Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1) — Xcode 27.1 | fails to produce diagnostic |
| Apple Swift version 6.4-dev (LLVM 264fd65923c28d9, Swift ef761e567dc94ee) — 6.4.x snapshot 2026-07-23 | fails to produce diagnostic |
| Apple Swift version 6.5-dev (LLVM 18d2bfb70c14d89, Swift c13d82e5987aecb) — snapshot 2026-06-12 | fails to produce diagnostic |
| Apple Swift version 6.5-dev (LLVM 1c31ac37011e294, Swift 830433945f993fe) — snapshot 2026-06-24 | fails to produce diagnostic |
| Apple Swift version 6.5-dev (LLVM 6f2057ffeafd4c6, Swift 83c32e02f71e4bb) — snapshot 2026-07-11 | fails to produce diagnostic |

The swift.org toolchains were run with
`-sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk`, because 6.3.3 cannot read
the 27.x SDK. Linux and Windows were not run locally; CI covers them.

## How it was found

In swift-sql's test suite, this call:

```swift
assertInlineSnapshot(of: Values { "Hello"; "Goodbye" }, as: .sql)
```

`Values { … }` without a row type is ambiguous between the `InsertValuesBuilder`
overloads (it is the same on unmodified pointfreeco swift-structured-queries, on 6.3.3
and 6.4). `.sql` is overloaded for `Value: Statement` and for `Value: QueryExpression`.
Together they give "failed to produce diagnostic" instead of the ambiguity error.
On its own, `let v = Values { "Hello"; "Goodbye" }` reports
`ambiguous use of 'buildExpression'` correctly.

## Workaround

Remove the inner ambiguity with an explicit type annotation. In swift-sql that is
`Values<String> { "Hello"; "Goodbye" }`, which compiles. In general, to see the real
error, bind the inner call to a separate `let`: the compiler then names the ambiguous
overload.

## Harness

`Tests/Reproducer.swift` and `Sources/Reproducer/main.swift` run
`swiftc -typecheck` on `Crash.swift.txt` in a child process, because the source does
not type-check and cannot be a compiled target. The bug fires on every toolchain
tested, so `withKnownIssue` uses `when: { true }`. The test flips red once a toolchain
reports a proper diagnostic instead of the fallback.

## Provenance

2026-09-28. Reduced from swift-sql `Tests/SQL Tests/Values Tests.swift` (before its
`Values<String>` annotation) by the builder-regression repro lane of the Rulings
coordinator.
