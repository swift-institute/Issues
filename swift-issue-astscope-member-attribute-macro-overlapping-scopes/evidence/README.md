# Evidence

Copied unchanged from `swift-institute/windows-exception-29-reproducer` (private).

- `lane/`: branch `lane/astscope-member-attribute` at `0f646c6a6a605a799991e7a4aff234542ea73546`.
  - `final/scope.swift` is `Sources/Reproducer/Crash.swift.txt`; `final/run.sh` runs it (and the #175 reproduction) exactly as drafted.
  - `astscope/`: the reduction. `repro.swift` is the first one-file plugin with `N1`/`N2`/`N14` attribute counts, `min.swift` the A/B variants (`ONE`/`TWO`, member kinds, `@available`, `@MainActor`), `observable.swift` the toolchain-macro attempt, `run.sh` and `min.sh` the drivers, `swiftly-swiftc.sh` the macOS snapshot wrapper.
  - `workflows/astscope.yml.txt`, `workflows/final.yml.txt`: the lane's CI.
- `review/`: branch `review/astscope-94dae5` at `83912190b461a047cf59a8cfbdb788d9c5830857`. `rvw1/` is review round 1, `rvw/` round 2, each with its driver; `workflows/review-astscope.yml.txt` runs them on the Linux nightly and macOS main snapshot.
- `ci/`: excerpts of the runs, timestamps stripped.
  - `run-39788628757-final.txt`: the drafted reproduction on every toolchain (the matrix in the README). Crash text kept, unsymbolized frames dropped.
  - `run-39784950734-lane.txt`, `run-39786015934-lane.txt`: lane A/B results (shared with the #175 entry).
  - `run-39790505398-review-round1.txt`, `run-39795615821-review-round2.txt`: review results.
- `local-macos-6.4.2.txt`: this port's local run on Xcode Swift 6.4.2 (no assertions): reproducer, control, probe and test results.
- `stub/`: the stand-in `swiftc` used locally to show the harness reads a fired and a fixed result. It replays `replay.txt` (the Linux nightly abort text from run 39788628757) and compiles nothing.

The Swift sources kept here verbatim are stored as `.swift.txt`, so the repository formatter and linter never rewrite them: `review/rvw1/v10_M_no_parens.swift.txt`, `review/rvw1/v11_A_no_parens.swift.txt`, `lane/astscope/repro.swift.txt`, `lane/astscope/min.swift.txt`, `review/rvw1/v13_no_member_struct_member_func.swift.txt`, `review/rvw1/v12_let_member.swift.txt`, `review/rvw1/v09_no_littleEndian.swift.txt`, `review/rvw1/v08_A_no_definition.swift.txt`, `review/rvw1/v07_empty_struct_control.swift.txt`, `review/rvw1/v06_single_A_control.swift.txt`, `review/rvw1/v05_no_memberAttr_condition.swift.txt`, `review/rvw1/v04_no_protocolVersion.swift.txt`, `review/rvw1/v03_no_diagnostics_field.swift.txt`, `review/rvw1/v02_no_type_annot.swift.txt`, `review/rvw1/v00_baseline.swift.txt`, `review/rvw/v00_baseline.swift.txt`, `lane/final/scope.swift.txt`, `review/rvw1/v01_noA_decl.swift.txt`, `review/rvw/v25_noA_always_notype_control.swift.txt`, `review/rvw/v24_noA_always_single_control.swift.txt`, `review/rvw/v22_noA_always_nospace.swift.txt`, `review/rvw/v20_noA_always.swift.txt`, `review/rvw1/v14_no_windows_branch.swift.txt`, `review/rvw/v21_noA_always_nocap.swift.txt`, `review/rvw/v23_noA_always_nowin_noLE_nocomment.swift.txt`. Scripts and notes in this folder name them by their original `.swift` names; rename a file back to rerun it.
