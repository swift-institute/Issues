---
title: Swift Bug Report — mark_dependence CopyPropagation Interaction
status: SUPERSEDED
superseded_by: noncopyable-ecosystem-state.md
date: 2026-03-22
tier: 2
packages:
  - swift-property-primitives
provenance: 2026-03-22-copypropagation-nonescapable-root-cause-and-fix.md
---

> **SUPERSEDED** (2026-04-02) by [noncopyable-ecosystem-state.md](noncopyable-ecosystem-state.md).
> All findings consolidated into the topic-based document. This file retained as historical rationale.

# Swift Bug Report: mark_dependence CopyPropagation Interaction

## Context

CopyPropagation (OSSACanonicalizeOwned) bails out on `OperandOwnership::PointerEscape`. When `~Escapable` types use `@_lifetime(borrow)`, the generated `mark_dependence` instructions are classified as `PointerEscape`, causing partial canonicalization that leads to double `end_lifetime` on `~Copyable ~Escapable` values across control flow joins. The compiler team has a TODO comment at `OSSACanonicalizeOwned.cpp:40-46` acknowledging this interaction.

## Question

File a bug report with the standalone reproducer from `copypropagation-nonescapable-mark-dependence` experiment. The reproducer requires: 3 modules, `~Copyable ~Escapable` type with `@_lifetime(borrow)` init, `_read` coroutine yielding the type, and control flow (if/else) after the yield.

## Analysis

Root cause chain: `~Escapable` + `@_lifetime(borrow base)` → `mark_dependence [unresolved/escaping]` → `PointerEscape` classification → partial canonicalization bailout → double `end_lifetime` generation.

The fix applied in the ecosystem: remove `~Escapable` from Property.View (the coroutine scope already prevents escape).

## Outcome

_Bug report pending filing._
