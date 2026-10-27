# Evidence

| Path | What it is |
|---|---|
| `nested-type-generic-escape/` | The experiment `swift-ownership-primitives--nested-type-generic-escape` from `swift-institute/Experiments` at commit `f1c4db4d390c12af5ec454dfb506feaa4ec5e841`: `EXPERIMENT.md`, `Package.swift.txt`, `main.swift.txt` and its `Outputs/`. `.swift` files carry a `.txt` suffix so the Issues package does not compile them. `Outputs/build-short-forms.txt` is the 6.3.1 crash (signal 11, `ResolveTypeRequest`, `applyUnboundGenericArguments`). |
| `h5-shape.swift.txt` | H5's short form as one standalone file: `H5_Foo<V> { typealias Bar<U: ~Copyable> = __H5FooBar<U> }`, used as `H5_Foo.Bar<Handle>`. Crashes the same way on 6.4.2. |
| `runs-6.4.2-macos.log` | Apple Swift 6.4.2, macOS 27.2 arm64, 2026-10-27: the reduced reproducer (exit 139), three controls (exit 0), and the H5 shape (crash). |
