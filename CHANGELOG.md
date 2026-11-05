# Changelog

## [0.2.0] - 2026-11-05

### Added
- Honest component status table in README.
- Explicit LIMITATIONS section (single-user, local-first, limited adapters, no production scheduler).
- Clarified one-sentence unique capability: offline-verifiable authorization evidence for agent side-effects.
- Pinned Python >=3.10 more clearly in install notes.
- Every major README claim now has a corresponding command or test name that a stranger can run in <5 minutes.

### Changed
- README lead sentence focuses on the authorization + evidence plane, not historical iMessage/Hermes remote control.
- Hermes is documented only as one example runtime adapter.

### Fixed
- Install instructions verified on clean clone with `pip install -e .`.

## [0.1.0] - earlier

Initial vertical slice: signed receipts, policy engine, hash-chained audit, Merkle checkpoints, offline verification, tamper matrix, receipt binding tests, NullAgent adapter.
