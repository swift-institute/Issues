
- Toolchain: Xcode-beta 27.2, Apple Swift version 6.4.2 (swiftlang-6.4.2.1.4 clang-2100.4.1.1), target arm64-apple-ios27.0
- Package: pointfreeco/swift-issue-reporting at b23bb44, target IssueReporting
- Settings: SWIFT_OPTIMIZATION_LEVEL=-O SWIFT_COMPILATION_MODE=wholemodule (Debug configuration otherwise); Debug -Onone builds fine
- Crash: While emitting IR SIL function "@$s14IssueReporting012withExpectedA0_14isIntermittent6fileID0G4Path4line6column_ySSSg_Sbs12StaticStringVAJS2uyyKXEtF" for withExpectedIssue(_:isIntermittent:fileID:filePath:line:column:_:) (Internal/Deprecations.swift:12)
- Top frames: llvm::Value::setMetadata <- IRBuilderBase::CreateCast <- swift::irgen::reemitAsUnsubstituted <- emitApplyArgument <- IRGenSILFunction::visitFullApplySite
- Full log available on request (local build log).
- Found 20 Oct 2026 while building an optimised build of an app that depends on swift-issue-reporting.
- Also with SWIFT_OPTIMIZATION_LEVEL=-O and per-file compilation: While emitting IR SIL function "@$s14IssueReporting07_recordA07message8severity6fileID0F4Path4line6columnySSSg_AA0A8SeverityOS2SS2itF" (_recordIssue). Log: /private/tmp/claude-501/trace-build-ios2.log
