# Sinter JSON Schema Swapout Plan (ex_json_schema v0.11.2)

> Status: Superseded. Sinter now validates JSON Schemas with JSV 0.13.1 and dual-draft
> support (Draft 2020-12 + Draft 7). This plan is retained for historical context.

## Overview
This document describes the refactor required to replace Sinter's hand-rolled JSON
Schema validation with `ex_json_schema` v0.11.2, reduce custom validation code,
and align generated schemas to a draft that the validator supports.

## Current State (Key Files)
- `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex`:
  - Generates JSON Schema with `$schema` set to Draft 2020-12.
  - Implements `validate_schema/2` using custom structural checks
    (`check_basic_structure/2`, `check_type_consistency/2`,
    `check_constraint_validity/2`, etc.).
- `/home/home/p/g/n/sinter/test/sinter/json_schema_test.exs`:
  - Asserts Draft 2020-12 `$schema`.
  - Asserts exact custom validation error strings.
- `/home/home/p/g/n/sinter/mix.exs`:
  - `ex_json_schema` is commented out; `mix.lock` references 0.10.2.

## Motivation / Problems
- The custom validator is partial and will diverge from JSON Schema spec behavior.
- Manual checks are a maintenance burden and block feature growth.
- `ex_json_schema` already validates schemas against their meta-schema and resolves
  `$ref` safely, so custom checks are redundant.
- Draft 2020-12 is not supported by `ex_json_schema` (supports 4/6/7).

## Refactor Strategy
1. **Adopt `ex_json_schema`** for schema validation and reference resolution.
2. **Align `$schema` to Draft 7** so `ExJsonSchema.Schema.resolve/1` can validate.
3. **Remove manual validation helpers** in `Sinter.JsonSchema` and collapse
   `validate_schema/2` into a thin wrapper around `ExJsonSchema.Schema.resolve/1`.
4. **Update tests** to match Draft 7 and new error formats.
5. **Document behavior changes** (draft change + error message changes).

## Detailed Implementation Plan
### Phase 1: Dependency + Schema Draft Alignment
- Add `{:ex_json_schema, "~> 0.11.2"}` to `/home/home/p/g/n/sinter/mix.exs`.
- Run `mix deps.get` to update `/home/home/p/g/n/sinter/mix.lock` to 0.11.2.
- Change JSON Schema generator in `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex`
  to emit `$schema` = `http://json-schema.org/draft-07/schema#`.

### Phase 2: Validation Swap + Code Reduction
- Replace `validate_schema/2` implementation to:
  - Call `ExJsonSchema.Schema.resolve/1`.
  - Return `:ok` on success.
  - Rescue `ExJsonSchema.Schema.InvalidSchemaError`,
    `ExJsonSchema.Schema.UnsupportedSchemaVersionError`,
    and `ExJsonSchema.Schema.InvalidReferenceError`, returning
    `{:error, [Exception.message(e)]}`.
- Delete manual validation helpers:
  - `check_basic_structure/2`
  - `check_type_consistency/2`
  - `check_constraint_validity/2`
  - `check_numeric_constraints/2`
  - `check_string_constraints/2`
  - `check_array_constraints/2`

### Phase 3: Tests + Docs
- Update `/home/home/p/g/n/sinter/test/sinter/json_schema_test.exs`:
  - `$schema` assertions to Draft 7.
  - `validate_schema/2` assertions to check the new error message pattern
    (from `ExJsonSchema.Schema.InvalidSchemaError`) rather than exact strings.
- Update `/home/home/p/g/n/sinter/README.md` dependency snippet to new version.
- Add changelog entry for 2025-12-27 describing:
  - ex_json_schema integration
  - Draft 7 `$schema` change
  - removal of custom validation checks

## Code Reduction Summary
- Remove ~100 lines of bespoke structural/constraint validation code from
  `/home/home/p/g/n/sinter/lib/sinter/json_schema.ex`.
- Consolidate schema validation into one call:
  `ExJsonSchema.Schema.resolve/1`.

## Compatibility Notes
- JSON Schema draft changes from **2020-12** to **draft-07**.
  - If Draft 2020-12 features are required, they must be avoided or translated.
- `validate_schema/2` error strings will change.
  - Consumers should treat errors as opaque strings, not parse them.

## Test and Verification Plan
- Run `mix format --check-formatted`
- Run `mix compile --warnings-as-errors`
- Run `mix credo --strict`
- Run `mix test`
- Run `mix dialyzer` and ensure no warnings

## Rollback Plan
- Revert `$schema` to Draft 2020-12 and restore manual validation helpers.
- Remove `ex_json_schema` dependency and reset `mix.lock`.
