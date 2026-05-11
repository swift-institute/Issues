// swiftlang/swift#77558 — standalone executable reproducer.
//
// Companion to Tests/Reproducer.swift. The test harness uses
// `withKnownIssue` to flip-on-fix on Linux release. This executable
// covers the codegen surface that SwiftPM `swift test` masks on macOS:
// the bug DOES fire on macOS when the same source is compiled with
// `swiftc -O` directly. Running the executable and asserting the exit
// code makes that surface a first-class CI signal.
//
// Exit code: 0 if `backed.pointee == 20` (no bug); 1 if not (bug fires).

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(MSVCRT)
import MSVCRT
#endif

struct Vec {
    let raw: Int
    init(_ raw: Int) { self.raw = raw }
}

func + (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    unsafe lhs.advanced(by: rhs.raw)
}

func - (lhs: UnsafeMutablePointer<Int>, rhs: Vec) -> UnsafeMutablePointer<Int> {
    unsafe lhs.advanced(by: -rhs.raw)
}

var values: [Int] = [0, 10, 20, 30, 40]
let observed: Int = unsafe values.withUnsafeMutableBufferPointer { buf in
    let base = buf.baseAddress!
    let advanced = unsafe base + Vec(4)
    let backed = unsafe advanced - Vec(2)
    return unsafe backed.pointee
}

exit(observed == 20 ? 0 : 1)
