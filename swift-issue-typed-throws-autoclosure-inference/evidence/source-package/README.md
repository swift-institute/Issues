# Type Inference Fails for `@autoclosure` with Typed Throws

Swift cannot infer `E = Never` for `@autoclosure () throws(E) -> T` when the expression doesn't throw.

## Minimal Reproduction

```swift
func f<E: Error, T>(_ value: @autoclosure () throws(E) -> T) throws(E) -> T {
    try value()
}

let result: Bool = f(true)  // error: generic parameter 'E' could not be inferred
```

## To Reproduce

```bash
git clone https://github.com/coenttb/swift-issue-typed-throws-autoclosure-inference
cd swift-issue-typed-throws-autoclosure-inference
swift build
```

## Expected

`E = Never` should be inferred because:
1. `true` is non-throwing
2. Non-throwing closures have error type `Never`
3. `Never` conforms to `Error`

## Evidence: Non-@autoclosure Works

```swift
func g<E: Error, T>(_ value: () throws(E) -> T) throws(E) -> T {
    try value()
}

let result: Bool = g({ true })  // Compiles - E = Never inferred
```

The only difference is `@autoclosure` vs explicit closure.

## Environment

- Swift 6.2 (swiftlang-6.2.3.3.21)
- All platforms
