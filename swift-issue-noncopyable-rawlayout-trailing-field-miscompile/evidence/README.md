# Evidence

Forensic artifacts captured during the investigation (2026-05-28), all on the
canonical minimum reproducer `../Sources/Reproducer/Crash.swift.txt`.

| File | What it shows |
|------|---------------|
| [`demangle.txt`](demangle.txt) | `swift demangle` of the broken symbols. The functions carrying the invalid IR are the **`destroy`** and **`assignWithTake`** value witnesses for `Box` — confirming the bug is in compiler-synthesized value-witness functions, not user code, a specialized method, or metadata instantiation. |
| [`pass-identification.log`](pass-identification.log) | Full `-Xllvm -print-after-all` run. There are **zero** `IR Dump After`/`IR Dump Before` lines before the abort — the crash happens at `Running pass "verify" on module`, the LLVM module `VerifierPass` that runs first in `performLLVMOptimizations`. No transform pass (LICM/GVN/SimplifyCFG/etc.) is involved; the invalid IR is emitted directly by Swift IRGen and the verifier merely detects it. |
| [`destroy-witness.cfg.ll`](destroy-witness.cfg.ll) | Trimmed, annotated CFG of the `destroy` value witness from `-emit-irgen` (pre-LLVM-opt). Shows `%stride` defined in the `loop` block but used by `mul i64 %stride, 8` in the `exit` block, which is also reachable from `cond` (zero-trip path) — the dominance violation, present as emitted. |

## Reproduce the evidence

```bash
cd ../Sources/Reproducer

# The crash itself (any toolchain >= 6.3.1, macOS or Linux):
swiftc -O -enable-experimental-feature RawLayout \
  -enable-experimental-feature ValueGenerics Crash.swift.txt -o /tmp/crash

# Demangle the broken value witnesses:
swiftc -O -enable-experimental-feature RawLayout \
  -enable-experimental-feature ValueGenerics -emit-irgen Crash.swift.txt -o crash.ll
grep -oE '\$s4main3BoxVw[A-Za-z0-9_]*' crash.ll | sort -u | while read s; do
  printf '%s -> ' "$s"; swift demangle "$s"
done

# Confirm the verifier is the only pass that runs (no transform precedes it):
swiftc -O -Xllvm -print-after-all -enable-experimental-feature RawLayout \
  -enable-experimental-feature ValueGenerics Crash.swift.txt -o /dev/null 2>&1 \
  | grep -E "IR Dump|Running pass|dominate"
```
