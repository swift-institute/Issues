# Provenance

This entry consolidates two independently reduced manifestations of the same compiler defect.

- `evidence/constrained-extension/` retains exact source blobs from the public repository recorded in `source-provenance.json`. The `.txt` suffix changes only the retained filename, not its bytes.
- `evidence/direct-initialization/` retains the second reduction, the assertions-build crash capture, and the original package-context capture. Machine-local roots in those text captures are normalized to descriptive placeholders; compiler versions, flags, signatures, frames, and source locations are otherwise retained. Those files are supplemental discovery evidence; their domain names are not part of the core reproducer.

The runnable sources under `Sources/Reproducer/` use neutral Swift concepts and preserve the two distinct conversion contexts.
