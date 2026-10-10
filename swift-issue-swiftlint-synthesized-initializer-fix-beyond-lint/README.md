# `swift-issue-swiftlint-synthesized-initializer-fix-beyond-lint`

`swiftlint --fix` mutates **strictly more sites** than `swiftlint lint
--strict` reports. For `unneeded_synthesized_initializer` the reporting path
visits only types that are top level or nested in a `struct`/`class`; the
correction path additionally descends into types nested in an `enum` and types
declared inside an `extension`.

Both silent shapes are Swift Institute house idiom — the `Nest.Name` namespace
enum and extension-hosted nesting — so the silent class is not a corner case in
this ecosystem, it is the common case.

Upstream instrument: [realm/SwiftLint](https://github.com/realm/SwiftLint)
built-in rule `unneeded_synthesized_initializer` (default-enabled, correctable).
This is **not** a `swift-foundations/swift-linter` rule and not a compiler
defect.

## Minimal reproduction

`Sources/Reproducer/Fixture.swift.txt` declares six types, each with an explicit
memberwise initializer the rule considers redundant, differing only in the
enclosing declaration. Linted under `Sources/Reproducer/Config.yml.txt`
(`only_rules: [unneeded_synthesized_initializer]`):

```sh
swiftlint lint --strict --no-cache   # 3 violations
swiftlint --fix --no-cache           # Corrected unneeded_synthesized_initializer 6 times
```

| fixture | enclosing declaration | reported by `lint --strict` | mutated by `--fix` |
| --- | --- | --- | --- |
| `A` | none (top level) | yes | yes |
| `B` | `public enum` | **no** | **yes** |
| `C` | `public struct` | yes | yes |
| `D` | `internal enum` | **no** | **yes** |
| `E` | `extension` of a struct | **no** | **yes** |
| `F` | `public final class` | yes | yes |

## Measured

Against the **exact instrument the fleet's CI runs**: SwiftLint `0.63.3`
`swiftlint_linux_amd64`, sha256
`26db741d43f2f2dc26c0cf16911100a3e186c3d1dbb59e55ad3ac87b0de4538f` — the
`SWIFTLINT_SHA256` pin in `swift-institute/.github`'s `swift-ci.yml` — executed
inside the release-floor container image
`swiftlang/swift@sha256:8d614165059587ce9dcf6727a76aeff4cbf1cde41fde9a9281a43803be736224`,
the same image the `lint` job declares. 2026-08-10.

```
lint --strict reported lines: [4, 19, 43]        (A, C, F)
--fix:  Corrected unneeded_synthesized_initializer 6 times
```

SwiftLint `0.65.0` on macOS arm64 (Homebrew) reproduces the identical 3-vs-6
split, including the same three silent shapes.

### Positive control

Fixtures `A`, `C` and `F` are reported in the same run that silently corrects
`B`, `D` and `E`. Their presence is what proves the rule was enabled and the
fixture was linted — a run reporting nothing at all would be indistinguishable
from a misresolved configuration. The reproducer treats `reported == 0` as
*inconclusive*, never as *fixed*.

### Hazard-shape control

The six fixtures are identical but for the enclosing declaration, so the
enclosing declaration is isolated as the discriminator by construction rather
than by inference. The measurement diffs the **working tree** (surviving
initializers) against the **measured violation set**, not against SwiftLint's
own `Corrected N times` line — the claim is precisely that the tool's report
and the tool's mutation disagree, so the tool's report cannot also be the
measurement.

## Production observation

Reproduced end-to-end on a copy of `swift-foundations/swift-json` at
`8fbf175`, under that repository's real configuration chain (`.swiftlint.yml`
→ `swift-foundations/.github` → `swift-institute/.github`):

```
swiftlint lint --strict   →  68 violations
                             vertical_whitespace_between_cases 44
                             no_any_protocol_existential       17
                             direct_return                      3
                             redundant_nil_coalescing           2
                             shorthand_optional_binding         2
                             unneeded_synthesized_initializer   0

swiftlint --fix           →  Corrected unneeded_synthesized_initializer 1 time
                             in JSON.Decoder.Key.swift
                             in JSON.Decoder.Single.swift
                             in JSON.Decoder.swift
```

Three initializers deleted, none of them in the measured set. Each is nested in
a `JSON` namespace enum. The deletions also removed the initializers' doc
comments. This confirms the original report exactly.

## Why this is structural, not cosmetic

The standard mechanical-sweep protocol — measure with `--strict`, apply
`--fix`, re-verify with `--strict` — cannot detect these mutations. Both
measurements are clean; the unmeasured deletions ride along invisibly between
them. Any lane following that protocol on any repository in the fleet has been
landing unreviewed mutations whose count it has no way to know.

That is the blast radius: not this rule, but the verification protocol. A
`--fix` run is only as trustworthy as the set of rules whose report surface and
correction surface are known to coincide, and nothing currently establishes
that for any rule.

The countermeasure available today without any tool change is to diff the
working tree after `--fix` rather than to re-run `--strict`.

## Filed

`swift-foundations/swift-linter#47` (filed there by the discovering lane; the
rule's actual owner is upstream SwiftLint).

## Verdict

**GENUINE DEFECT**, and fleet-wide in blast radius.
