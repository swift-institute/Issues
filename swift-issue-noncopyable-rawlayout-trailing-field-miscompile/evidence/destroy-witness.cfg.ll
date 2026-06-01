; Trimmed, annotated LLVM IR for the `destroy value witness for main.Box`
; (`$s4main3BoxVwxx`), as emitted by Swift IRGen at -O (PRE LLVM optimization).
;
; Captured: xcrun swiftc -O -enable-experimental-feature RawLayout \
;   -enable-experimental-feature ValueGenerics -emit-irgen Crash.swift.txt
; Toolchain: Apple Swift 6.3.2 (swiftlang-6.3.2.1.108), arm64-apple-macosx26.0.
;
; This IR is ALREADY invalid as emitted — no LLVM transform pass runs before
; the failure. `%stride` is DEFINED in `loop` (the element-destroy loop body)
; but USED in `exit` (the post-loop trailing-field offset), and `exit` is also
; reachable from `cond` on the zero-trip path, so the def does not dominate the
; use. The module verifier (`VerifierPass`, the first pass in
; performLLVMOptimizations) calls report_fatal_error: "Instruction does not
; dominate all uses!".

define internal void @"$s4main3BoxVwxx"(ptr noalias %object, ptr %"Box<Element>") {
entry:
  %0 = alloca i64, align 8
  store i64 0, ptr %0, align 8
  br label %cond

cond:                                             ; preds = %loop, %entry
  %1 = load i64, ptr %0, align 8
  br i1 true, label %loop, label %exit            ; <-- edge cond -> exit (zero-trip path)

loop:                                             ; preds = %cond
  %2 = add i64 %1, 1
  store i64 %2, ptr %0, align 8
  %3 = getelementptr inbounds ptr, ptr %"Box<Element>", i64 2
  %Element = load ptr, ptr %3, align 8, !invariant.load !17
  %4 = getelementptr inbounds ptr, ptr %Element, i64 -1
  %Element.valueWitnesses = load ptr, ptr %4, align 8, !invariant.load !17
  %5 = getelementptr inbounds nuw %swift.vwtable, ptr %Element.valueWitnesses, i32 0, i32 9
  %stride = load i64, ptr %5, align 8, !invariant.load !17   ; <== DEF of %stride (in `loop` only)
  %6 = mul i64 %1, %stride                                   ;     per-element offset (OK: same block)
  %7 = getelementptr inbounds i8, ptr %object, i64 %6
  %8 = getelementptr inbounds ptr, ptr %Element.valueWitnesses, i32 1
  %Destroy = load ptr, ptr %8, align 8, !invariant.load !17
  call void %Destroy(ptr noalias %7, ptr %Element)
  %9 = icmp eq i64 %2, 8
  br i1 %9, label %exit, label %cond

exit:                                             ; preds = %loop, %cond   <== reachable WITHOUT `loop`
  %10 = mul i64 %stride, 8                          ; <== USE of %stride (trailing-field offset = stride*capacity)
  %11 = ptrtoint ptr %object to i64                ;     NOT DOMINATED: `loop` is not on every path to `exit`
  %12 = add i64 %11, %10
  %13 = inttoptr i64 %12 to ptr
  ret void
}

; The `assignWithTake value witness for main.Box` (`$s4main3BoxVwta`) has the
; identical shape and the identical violation; both are reported by the verifier.
