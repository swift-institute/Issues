// This file triggers the bug when built.
// The error demonstrates that Swift cannot infer E = Never for @autoclosure
// with typed throws when the expression doesn't throw.

// Minimal triggering case:
func typedThrowsAutoclosure<E: Error, T>(
    _ value: @autoclosure () throws(E) -> T
) throws(E) -> T {
    try value()
}

// For comparison, the non-@autoclosure version works:
func typedThrowsExplicitClosure<E: Error, T>(
    _ value: () throws(E) -> T
) throws(E) -> T {
    try value()
}

func triggerBug() {
    // BUG: The following line fails to compile:
    // Error: Generic parameter 'E' could not be inferred
    let bugResult: Bool = typedThrowsAutoclosure(true)
    _ = bugResult

    // This compiles - E = Never is correctly inferred with explicit closure:
    let worksResult: Bool = typedThrowsExplicitClosure({ true })
    _ = worksResult
}
