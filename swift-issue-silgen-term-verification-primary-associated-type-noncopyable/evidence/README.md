# Evidence

Copied unchanged from `swift-institute/windows-exception-29-reproducer` (private), branch `main` at `7ad41ef5b24d08db52ede2c97b4fccdc3753dc04`. The `v3/` files last changed at `133e228082b60f1f63d8e79a79ad1d398561e9bf`.

- `v3/`: the reduction and its controls. `prelude.txt` and `b_nobody.body` are the larger mimic of swift-coder's `Coder.Case+Operation.swift` the lane started from. `m11_primary_on_coding.swift` is `Sources/Reproducer/Crash.swift.txt`.
- `run.sh`: the lane's driver for the Linux nightly (also runs `v/` and `v2/`, which belong to `swift-issue-irgen-nonthrowing-typed-throws-closure-crash`).
- `workflows/*.yml.txt`: the lane's workflows (`repro`: Windows 6.4 with two flag sets; `nightly`: Linux nightly, Windows 6.4.1 and a Windows snapshot that never started; `linux-detail`: m11 under several commands).
- `ci/`: excerpts of the decisive runs, result and crash lines only, timestamps stripped.
  - `run-39642339405-windows-6.4.1.txt`: Windows 6.4.1 `+assertions`, both flag sets. m11 and z1 abort; m12, m13, p1, q1, y1 compile.
  - `run-39643341814-nightly.txt`: Linux nightly 6.5-dev `+assertions` and Windows 6.4.1. Same split for `v3/`.
  - `run-39649025095-linux-detail.txt`: Linux nightly. `-emit-silgen` and `-c` abort, `-typecheck` passes, extra flags do not matter.
- `local-macos-6.4.2.txt`: this port's local run on Xcode Swift 6.4.2 (no assertions): reproducer, controls, probe and test results.
- `stub/`: the stand-in `swiftc` used locally to show the harness reads a fired and a fixed result. It replays `replay.txt` (the abort text from run 39649025095) and compiles nothing.

The Swift sources kept here verbatim are stored as `.swift.txt`, so the repository formatter and linter never rewrite them: `v3/y1_no_inverses.swift.txt`, `v3/z1_only_copyable_inverse.swift.txt`, `v3/q1_z1_case_parsing_serializing.swift.txt`. Scripts and notes in this folder name them by their original `.swift` names; rename a file back to rerun it.
