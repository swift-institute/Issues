# Evidence

Copied unchanged from `swift-institute/windows-exception-29-reproducer` (private).

- `lane/`: branch `lane/astscope-member-attribute` at `0f646c6a6a605a799991e7a4aff234542ea73546`. `final/case.swift` is `Sources/Reproducer/Crash.swift.txt`; `final/run.sh` runs it (and the #157 reproduction) exactly as drafted; `workflows/final.yml.txt` is the workflow. The lane's reduction sources (`astscope/repro.swift` with `-D CASES`, `astscope/min.swift` with `R_CASE`) are kept in the `swift-issue-astscope-member-attribute-macro-overlapping-scopes` entry's evidence, since they cover both records.
- `review/`: branch `review/enumcase-a1effe` at `14c3d7ea6b6ee32b283d06e483b279839f22471e`. `v0.swift` is the draft; `v1` to `v12` the reviewer's one-change variants; `run.sh` the driver; `workflows/review-enumcase.yml.txt` runs it on the Linux nightly and macOS main snapshot.
- `ci/`: excerpts of the runs, timestamps stripped.
  - `run-39788628757-final.txt`: the drafted reproduction on every toolchain (the matrix in the README).
  - `run-39784950734-lane.txt`, `run-39786015934-lane.txt`: lane A/B results; the enum-case rows are `-D CASES` and `R_CASE`.
  - `run-39790509955-review.txt`, `run-39794392449-review.txt`: review results.
- `local-macos-6.4.2.txt`: this port's local run on Xcode Swift 6.4.2: the reproducer with and without `-Xfrontend -enable-ast-verifier`, three controls, the probe and the test.

The Swift sources kept here verbatim are stored as `.swift.txt`, so the repository formatter and linter never rewrite them: `review/v11_no_macro_decl_args.swift.txt`, `review/v9_capability_empty.swift.txt`, `review/v6_struct_member.swift.txt`, `review/v5_no_macro_attr_on_enum.swift.txt`, `review/v4_no_case.swift.txt`, `review/v3_no_diagnostics_field.swift.txt`, `review/v1_empty_expansion.swift.txt`, `review/v10_other_attr.swift.txt`, `review/v0.swift.txt`, `lane/final/case.swift.txt`, `review/v2_no_capability_branch.swift.txt`, `review/v8_no_windows_branch.swift.txt`, `review/v7_no_take_loop.swift.txt`, `review/v12_combined_v7_v8.swift.txt`. Scripts and notes in this folder name them by their original `.swift` names; rename a file back to rerun it.
