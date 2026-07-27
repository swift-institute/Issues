# SIL evidence — structural equivalence at `-O`

Emitted with the default Xcode toolchain (Apple Swift 6.3.1):

```bash
xcrun -sdk macosx swiftc -O -emit-sil Sources/Benchmark/main.swift -o main.sil
```

The relevant artifacts are the two specialized closure functions corresponding to the benchmark's nested-vector and flat-vector loops. Find them with:

```bash
grep -nE '^sil .*(FlatVector3Read|NestedVector.*InlineVySi).*Tf1nc_n' main.sil
```

## Closure 1 — `FlatVector3Read` benchmark loop

Mangled name: `$s…runBenchmarksyyFyyXEfU0_AA15FlatVector3ReadVTf1nc_n`
Type signature: `@convention(thin) (Int, FlatVector3Read) -> Double`

`bb2` (loop preheader, hoisted out of the loop):

```sil
bb2:
  %16 = integer_literal $Builtin.Int64, 1
  %17 = integer_literal $Builtin.Int1, -1
  %18 = builtin "cmp_sge_Int64"(%6, %7) : $Builtin.Int1
  cond_fail %18, "loop induction variable overflowed"
  %23 = struct_extract %1, #FlatVector3Read._elements      // ← field name
  %24 = struct_extract %23, #InlineArray._storage
  %27 = integer_literal $Builtin.Word, 1
  %28 = integer_literal $Builtin.Int1, 0
  %31 = integer_literal $Builtin.Word, 2
  %32 = function_ref @$s4main9blackHoleyyxlFSi_Tg5 : $@convention(thin) (Int) -> ()
  br bb4(%6)
```

`bb4` (loop body):

```sil
bb4(%44 : $Builtin.Int64):
  %45 = builtin "sadd_with_overflow_Int64"(%44, %16, %17) : $(Builtin.Int64, Builtin.Int1)
  %46 = tuple_extract %45, 0
  %48 = alloc_stack $Builtin.FixedArray<3, Int>
  store %24 to %48
  %50 = vector_base_addr %48
  %51 = struct_element_addr %50, #Int._value
  %52 = load %51
  dealloc_stack %48
  %54 = alloc_stack $Builtin.FixedArray<3, Int>
  store %24 to %54
  %56 = vector_base_addr %54
  %57 = index_addr [stack_protection] %56, %27
  %58 = struct_element_addr %57, #Int._value
  %59 = load %58
  dealloc_stack %54
  %61 = builtin "sadd_with_overflow_Int64"(%52, %59, %28) : $(Builtin.Int64, Builtin.Int1)
  %62 = tuple_extract %61, 0
  %63 = alloc_stack $Builtin.FixedArray<3, Int>
  store %24 to %63
  %65 = vector_base_addr %63
  %66 = index_addr [stack_protection] %65, %31
  %67 = struct_element_addr %66, #Int._value
  %68 = load %67
  dealloc_stack %63
  %70 = builtin "sadd_with_overflow_Int64"(%62, %68, %28) : $(Builtin.Int64, Builtin.Int1)
  %71 = tuple_extract %70, 0
  %72 = struct $Int (%71)
  %73 = apply %32(%72) : $@convention(thin) (Int) -> ()    // ← apply to blackHole
  %74 = builtin "cmp_eq_Int64"(%46, %7) : $Builtin.Int1
  cond_br %74, bb5, bb6
```

## Closure 2 — `NestedVector<Int, 3>.Inline` benchmark loop

Mangled name: `$s…runBenchmarksyyFyyXEfU2_AA12NestedVectorOAARi_zrlE6InlineVySi$2__GTf1nc_n`
Type signature: `@convention(thin) (Int, NestedVector<Int, 3>.Inline) -> Double` — `<Int, 3>` substituted in.

`bb2` (loop preheader):

```sil
bb2:
  %16 = integer_literal $Builtin.Int64, 1
  %17 = integer_literal $Builtin.Int1, -1
  %18 = builtin "cmp_sge_Int64"(%6, %7) : $Builtin.Int1
  cond_fail %18, "loop induction variable overflowed"
  %22 = struct_extract %1, #NestedVector.Inline._elements  // ← only difference vs Flat: field name
  %23 = struct_extract %22, #InlineArray._storage
  %25 = integer_literal $Builtin.Word, 1
  %26 = integer_literal $Builtin.Int1, 0
  %28 = integer_literal $Builtin.Word, 2
  %29 = function_ref @$s4main9blackHoleyyxlFSi_Tg5 : $@convention(thin) (Int) -> ()
  br bb4(%6)
```

`bb4` (loop body):

```sil
bb4(%41 : $Builtin.Int64):
  %42 = builtin "sadd_with_overflow_Int64"(%41, %16, %17) : $(Builtin.Int64, Builtin.Int1)
  %43 = tuple_extract %42, 0
  %45 = alloc_stack $Builtin.FixedArray<3, Int>
  store %23 to %45
  %48 = vector_base_addr %45
  %49 = struct_element_addr %48, #Int._value
  %50 = load %49
  dealloc_stack %45
  %52 = alloc_stack $Builtin.FixedArray<3, Int>
  store %23 to %52
  %55 = vector_base_addr %52
  %56 = index_addr [stack_protection] %55, %25
  %57 = struct_element_addr %56, #Int._value
  %58 = load %57
  dealloc_stack %52
  %60 = builtin "sadd_with_overflow_Int64"(%50, %58, %26) : $(Builtin.Int64, Builtin.Int1)
  %61 = tuple_extract %60, 0
  %62 = alloc_stack $Builtin.FixedArray<3, Int>
  store %23 to %62
  %65 = vector_base_addr %62
  %66 = index_addr [stack_protection] %65, %28
  %67 = struct_element_addr %66, #Int._value
  %68 = load %67
  dealloc_stack %62
  %70 = builtin "sadd_with_overflow_Int64"(%61, %68, %26) : $(Builtin.Int64, Builtin.Int1)
  %71 = tuple_extract %70, 0
  %72 = struct $Int (%71)
  %73 = apply %29(%72) : $@convention(thin) (Int) -> ()    // ← same apply to blackHole
  %74 = builtin "cmp_eq_Int64"(%43, %7) : $Builtin.Int1
  cond_br %74, bb5, bb6
```

(`debug_value` annotations have been omitted from both excerpts above for readability — see "Differences" below.)

## Differences

Operationally, the two closures are identical:

| Operation | FlatVector3Read closure | NestedVector.Inline closure |
|---|---:|---:|
| `alloc_stack $Builtin.FixedArray<3, Int>` | 3× | 3× |
| `store` | 3× | 3× |
| `vector_base_addr` | 3× | 3× |
| `index_addr` | 2× | 2× |
| `struct_element_addr` | 3× | 3× |
| `load` | 3× | 3× |
| `dealloc_stack` | 3× | 3× |
| `sadd_with_overflow_Int64` | 2× | 2× |
| `tuple_extract` | 3× | 3× |
| `apply` to a read accessor | **0** | **0** |
| `apply` to `blackHole` | 1× | 1× |

The only differences are:

1. **Field name on the leading `struct_extract`**: `#FlatVector3Read._elements` (Flat) vs `#NestedVector.Inline._elements` (Nested). A SIL label, no codegen difference.

2. **Placement of `debug_value` annotations.** In the Flat closure, the per-call `debug_value` for `self` is emitted in `bb2` (loop preheader, hoisted). In the Nested closure, the per-call `debug_value` is emitted inside `bb4` (loop body). Both include the same number of debug-info entries; their placement just differs. `debug_value` is metadata for debuggers — no instructions are emitted to the binary.

## What this shows

At `-O` on Swift 6.3.1, the optimizer:

- Fully specializes `NestedVector<Int, 3>.Inline` at the benchmark call site (visible in the closure's SIL type signature).
- Fully inlines the `subscript._read` accessor — there is no `apply` to any read-accessor function in the loop body of either closure.
- Produces operationally equivalent code for the nested-generic case and the flat-struct case.

The 1.6× gap reported in the original issue is therefore not visible at `-O`. Confirmed by timing: at `-O` both closures run at ~1.0 ns per iteration on the same hardware (see `README.md` for the cross-toolchain table).

## On Swift 6.2.3

Same structural equivalence. The 6.2.3 toolchain emits the older `unchecked_addr_cast` / `address_to_pointer` / `pointer_to_address` chain in place of the `vector_base_addr` primitive introduced later, but applies it identically to both Flat and Nested. The conclusion is the same: at `-O`, no operational difference between the two closures.
