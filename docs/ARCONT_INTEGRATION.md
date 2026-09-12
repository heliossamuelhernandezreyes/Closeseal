# ARCONT Integration Contract

Closeseal consumes ARCONT as an external technical authority, not as a code dependency.

## Roles

- `heliossamuelhernandezreyes/Closeseal`: production game.
- `heliossamuelhernandezreyes/Arcont`: knowledge bank, evidence ledger, maturity model and decision support.
- `heliossamuelhernandezreyes/Nia-Tech`: ARCONT Runtime Lab for controlled experiments.

## Decision flow

1. Closeseal records a concrete technical question.
2. Existing ARCONT evidence is checked first.
3. If evidence is insufficient, Runtime Lab runs the smallest reproducible experiment needed.
4. ARCONT ingests and validates the resulting evidence.
5. Closeseal records the chosen decision and the evidence scope that supports it.

## Non-goals

- Do not copy ARCONT experiments into production gameplay.
- Do not make Closeseal depend at runtime on ARCONT or Runtime Lab.
- Do not treat L3 observations as universal rules.
- Do not silently reinterpret metrics from different profilers as equivalent.

## Decision record format

Every material architecture decision should record:

- decision id;
- product requirement;
- alternatives considered;
- ARCONT claim/observation/rule ids used;
- maturity level and known limits;
- benchmark/profiler evidence if applicable;
- selected option;
- rollback trigger.

See `docs/decisions/ADR-0000-template.md`.
