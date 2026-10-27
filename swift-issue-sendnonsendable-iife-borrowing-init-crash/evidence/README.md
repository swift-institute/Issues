# Evidence

Copied from `swift-institute/Experiments/sendnonsendable-iife-borrowing-init-crash`
at commit `f1c4db4d390c12af5ec454dfb506feaa4ec5e841`, plus the 6.4.2 recheck.

| File | What it is |
|------|------------|
| `original-main.swift` | The experiment's caller, with its full header: ingredients, non-ingredients and the workaround, as recorded on 6.3.1. |
| `original-ReproLib.swift` | The experiment's library module (same as `../Sources/Reproducer/ReproLib.swift.txt`). |
| `original-Package.swift.txt` | The experiment's SwiftPM manifest: two targets, `Lifetimes`, Swift 6 mode. |
| `build-6.3.1.txt` | `swift build` output on Swift 6.3.1 (Xcode 26.4.1): signal 6 in `SendNonSendable`, `Partition::merge`. |
| `crash-6.4.2.txt` | The two bare `swiftc` commands and the stack dump on Swift 6.4.2 (Xcode 27.2), exit 134. |
