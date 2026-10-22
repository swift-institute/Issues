import Testing
@testable import Toolchain_Report

@Suite("Signature")
struct SignatureTests {
    static let darwin = """
        Stack dump:
        0.	Program arguments: /usr/bin/swift-frontend -frontend -c all.swift
        1.	Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1)
        3.	While evaluating request IRGenRequest(IR Generation for module IssueReporting)
        4.	While emitting IR SIL function "@$s14IssueReporting012withExpectedA0_".
         for 'withExpectedIssue(_:)' (at all.swift:12:8)
        0  swift-frontend           0x0000000108bfebb8 llvm::sys::PrintStackTrace(llvm::raw_ostream&, int) + 56
        2  swift-frontend           0x0000000108bff190 SignalHandler(int, __siginfo*, void*) + 356
        3  libsystem_platform.dylib 0x0000000189e06144 _sigtramp + 56
        4  swift-frontend           0x00000001089916ec llvm::MDAttachments::insert(unsigned int, llvm::MDNode&) + 52
        5  swift-frontend           0x00000001089916ec llvm::MDAttachments::insert(unsigned int, llvm::MDNode&) + 52
        6  swift-frontend           0x0000000108991d14 llvm::Value::setMetadata(unsigned int, llvm::MDNode*) + 116
        8  swift-frontend           0x000000010308e134 swift::irgen::reemitAsUnsubstituted(swift::irgen::IRGenFunction&, swift::SILType) + 716
        10 swift-frontend           0x00000001031732e0 (anonymous namespace)::IRGenSILFunction::visitFullApplySite(swift::FullApplySite) + 4924
        """

    static let linux = """
        swift-frontend: /home/build-user/swift/lib/IRGen/GenCall.cpp:812: void f(): Assertion `ty && "null"' failed.
        Stack dump:
        2.	While emitting IR SIL function "@main".
        #0 0x000055d5c1 llvm::sys::PrintStackTrace(llvm::raw_ostream&, int) (/usr/bin/swift-frontend+0x7a1)
        #1 0x000055d5c2 __restore_rt (/lib/x86_64-linux-gnu/libc.so.6+0x42520)
        #2 0x000055d5c3 swift::irgen::reemitAsUnsubstituted(swift::irgen::IRGenFunction&, swift::SILType) (/usr/bin/swift-frontend+0x123)
        """

    @Test func `reads phase and frames, dropping handlers and repeats`() {
        let signature = Signature(output: Self.darwin, frameCount: 4)
        #expect(signature.crashed)
        #expect(signature.phase == "While emitting IR SIL function")
        #expect(signature.frames == [
            "llvm::MDAttachments::insert",
            "llvm::Value::setMetadata",
            "swift::irgen::reemitAsUnsubstituted",
            "IRGenSILFunction::visitFullApplySite",
        ])
    }

    @Test func `reads a Linux assertion and frames`() {
        let signature = Signature(output: Self.linux, frameCount: 2)
        #expect(signature.assertion == "(ty && \"null\")")
        #expect(signature.frames == ["swift::irgen::reemitAsUnsubstituted"])
    }

    @Test func `matches the same crash, not a different one or a plain error`() {
        let signature = Signature(output: Self.darwin, frameCount: 3)
        #expect(signature.matches(Self.darwin))
        #expect(!signature.matches(Self.linux))
        #expect(!signature.matches("all.swift:3:5: error: cannot find 'x' in scope"))
    }

    @Test func `round-trips through a report`() {
        let signature = Signature(output: Self.darwin, frameCount: 4)
        let report = Report(body: "### Crash signature\n\n```text\n\(signature)\n```\n")
        #expect(report.signature == signature)
    }
}
