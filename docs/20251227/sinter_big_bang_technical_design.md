# Sinter Big-Bang Refactor Technical Design (2025-12-27)

## Overview
This document defines a full, big-bang refactor of Sinter to make it safe for
untrusted inputs, expressive for nested schemas, aligned with Tinkex wire
formats, and compliant with JSON Schema Draft 7 and 2020-12. It replaces the
current partial validation and ad-hoc schema behavior with a consistent model
and a dual-draft validator using JSV 0.13.1.

Local reference for the JSON Schema validator: `/home/home/p/g/n/sinter/jsv`

## Goals
- Make schema inference safe for untrusted data (no atom leaks by default).
- Support nested object schemas with per-field validation.
- Provide JSON encode/decode helpers and structured serialization features
  needed by Tinkex (aliases, omission rules, tri-state values).
- Validate JSON Schema with full Draft 7 and 2020-12 support.
- Produce accurate JSON Schema outputs for providers (OpenAI/Anthropic) with
  strict nested object handling.
- Preserve a small, explicit API surface with clear defaults and opt-in power.
- Ship as a single cohesive, comprehensive big-bang upgrade targeting 0.1.0.

## Non-goals
- Avoid runtime code generation or compiler plugins.
- Avoid introducing dependencies outside the JSON and JSON Schema domain
  unless required for correctness or ergonomics.
- No partial or incremental migration path; this is a coordinated refactor.

## Decision Summary
- **Field name representation:** Default internal representation is **string
  keys** for universality and safety. This matches JSON wire formats and avoids
  atom table exhaustion. Atom-based schema definitions remain supported for
  ergonomic Elixir DSL usage, but are normalized to strings internally.
  This choice aligns best with Tinkex (string-keyed wire JSON).
- **Nested object modeling:** Introduce a dedicated **object schema type** as
  the primary way to model structured objects. This is more ergonomic and
  elegant than forcing everything into `{:map, key_type, value_type}`, and it
  provides precise JSON Schema output. Typed maps remain available for dynamic
  key/value objects and are more flexible for non-structural use cases.
- **JSON Schema validation:** Replace `ex_json_schema` with **JSV 0.13.1**
  (supports Draft 2020-12 and Draft 7). Use the local clone for code reference:
  `/home/home/p/g/n/sinter/jsv`.
- **Draft support:** Provide **immediate dual-draft support** (Draft 7 and
  2020-12) for generation and validation. Default draft is 2020-12, with
  provider-specific overrides (Draft 7 for OpenAI/Anthropic until verified).

## Current Issues and Gaps (Corrected)
- **Atom leak risk**: `infer_schema/2` and DSPEx failure analysis convert
  untrusted string keys into atoms. Evidence:
  `/home/home/p/g/n/sinter/lib/sinter.ex:468`,
  `/home/home/p/g/n/sinter/lib/sinter/dspex.ex:281`.
- **Structured nested objects**: Maps can validate key/value types but Sinter
  has no nested object schema DSL. This blocks precise validation of nested
  shapes and forces permissive JSON Schema output. Evidence:
  `/home/home/p/g/n/sinter/lib/sinter/types.ex:189`,
  `/home/home/p/g/n/sinter/lib/sinter/schema.ex:386`.
- **`validate_many/3` path ordering bug**: Base paths are reversed due to
  `[index | path]`. Evidence: `/home/home/p/g/n/sinter/lib/sinter/validator.ex:148`.
- **Required-with-default bug**: Required field checks run before defaults are
  applied, so required fields with defaults still error. Evidence:
  `/home/home/p/g/n/sinter/lib/sinter/validator.ex:84`,
  `/home/home/p/g/n/sinter/lib/sinter/validator.ex:167`.
- **Constraint value validation missing**: Option values are not type-validated
  (`min_length: "10"` is accepted), leading to invalid schemas.
  Evidence: `/home/home/p/g/n/sinter/lib/sinter/schema.ex:411`.
- **Flattening no-op**: `flatten: true` returns unchanged schema, which can
  mislead consumers. Evidence: `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex:372`.
- **Provider strictness incomplete**: Only root `additionalProperties` is
  forced to false; nested objects remain permissive. Evidence:
  `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex:253`,
  `/home/home/p/g/n/sinter/lib/sinter/types.ex:399`.
- **Example inaccuracies**: Array constraints use `min_length`/`max_length`
  instead of `min_items`/`max_items`. Evidence:
  `/home/home/p/g/n/sinter/examples/json_schema_generation.exs:26`,
  `/home/home/p/g/n/sinter/examples/advanced_validation.exs:48`.

## Target Architecture
### Core Types
- **Schema fields stored with string keys**.
- **Object schema type**: `{:object, schema}` where `schema` is a
  `Sinter.Schema.t()` or a list of field specs. This is the canonical way to
  express nested structured objects.
- **Typed map**: `{:map, key_type, value_type}` retained for dynamic objects.
- **Nullable**: `{:nullable, type}` or `{:union, [:null, type]}`.
- **Built-in formats**: `:datetime`, `:date`, `:uuid` with ISO8601 checks.

### Modules
- `Sinter.Schema`:
  - Accept atom or string field names; normalize to strings.
  - Provide `object` DSL for nested schemas.
  - Validate option **values** using `NimbleOptions`.
- `Sinter.Types`:
  - Support nested object schema type.
  - Provide format validators for datetime/uuid.
- `Sinter.Validator`:
  - Apply defaults before required checks.
  - Fix `validate_many/3` path ordering.
- `Sinter.JsonSchema`:
  - Emit Draft 2020-12 or Draft 7 based on opts.
  - Enforce `additionalProperties: false` recursively when strict.
  - Use JSV for validation, mapping to draft dialect.
- **New** `Sinter.JSON`:
  - `decode/2` (Jason decode + validate + optional struct).
  - `encode/2` (transform + Jason encode).
- **New** `Sinter.Transform`:
  - Apply aliases, omit rules, tri-state handling (NotGiven-like behavior).
- **New** `Sinter.Struct` (optional):
  - Generate structs from schemas for typed outputs.

## JSON Schema Strategy (JSV)
- **Validator**: JSV 0.13.1, dual draft support.
- **Draft control**:
  - `draft: :draft2020_12 | :draft7` option on generation and validation.
  - Default: Draft 2020-12.
  - `provider: :openai | :anthropic` overrides to Draft 7 until verified.
- **Validation**:
  - `Sinter.JsonSchema.validate_schema/2` uses `JSV.build!/1` + `JSV.validate/2`.
  - Schema normalization into JSV dialect format (string-keyed JSON Schema to
    JSV-compatible maps if required).
- **Compatibility**:
  - Where Draft 2020-12 features are used, ensure Draft 7 output has safe
    fallbacks or explicit incompatibility errors.

## Tinkex Alignment
- **Wire format**: JSON payloads are string-keyed; Sinter should default to
  string keys internally and support JSON aliasing.
- **Tri-state semantics**: Implement omit-vs-nil vs default (NotGiven behavior)
  for request payloads.
- **Union/discriminator**: Provide discriminator support for object unions to
  model `ModelInput` and chunk types.
- **JSON encode/decode**: Provide helpers that mirror Tinkex request/response
  patterns and error handling.

## Migration Plan (Big Bang)
### Phase 0: Baseline and TDD
- Add failing tests for all listed gaps.
- Create `examples/run_all.sh` and make it the canonical example runner.

### Phase 1: Data Model + Validation Pipeline
- Normalize schema field keys to strings; update all call sites.
- Apply defaults before required checks.
- Fix `validate_many/3` path ordering.
- Add `NimbleOptions` validation for option values.

### Phase 2: Nested Object Schemas
- Add object schema type and nested DSL.
- Update `Types.validate/3` and JSON Schema generation.
- Add recursive `additionalProperties: false` for strict and provider modes.

### Phase 3: JSON Schema (JSV)
- Remove `ex_json_schema` usage.
- Integrate JSV 0.13.1 for Draft 7 + 2020-12 validation.
- Add draft selection and provider override logic.

### Phase 4: Serialization + Structs
- Implement `Sinter.Transform` for alias/omit/tri-state.
- Add JSON decode/encode helpers.
- Optional struct generation to support typed models.

### Phase 5: Docs and Examples
- Fix all example constraints for arrays.
- Revamp `README.md` with updated examples and draft support.
- Update `examples/README.md` and ensure `examples/run_all.sh` exists.

## Testing and Verification
- TDD for each feature (tests must fail first).
- Full test suite: `mix test`, `mix credo --strict`, `mix dialyzer`.
- `mix format --check-formatted` enforced in CI.
- Example validation via `examples/run_all.sh`.

## Risks and Mitigations
- **Breaking changes**: Big-bang refactor may break existing callers.
  Mitigation: detailed migration notes, clear defaults, and aggressive tests.
- **Draft mismatches**: Provider support for 2020-12 may lag.
  Mitigation: default to Draft 7 for provider schemas.
- **Performance regression**: Added recursion and transformation layers.
  Mitigation: add benchmarking tests and keep hot paths simple.

## Open Questions
- Should Draft 7 remain the default for provider-specific schemas long-term, or
  should Draft 2020-12 become the universal default once providers catch up?
- How much struct generation should be built in vs exposed as opt-in helpers?

