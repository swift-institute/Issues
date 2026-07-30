// swift-linter-tools-version: 0.1

import Linter
import Linter_Institute_Rules

Lint.run(dependencies: [
    .package(
        url: "https://github.com/swift-foundations/swift-institute-linter-rules.git",
        branch: "main",
        products: ["Linter Institute Rules"]
    )
]) {
    Lint.Rule.Bundle.institute
}
