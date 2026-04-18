# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] - 2026-04-17

### Added
- Validator-driven and structural regression suites covering discriminated-union JSON Schema generation, branch invariants, discriminator mappings, and compile-time variant validation.
- Compile-time validation for discriminated unions so every variant must define the discriminator field as a matching `:literal`.
- A focused discriminated-union JSON Schema example plus refreshed example runners and examples documentation.

### Changed
- Upgraded direct dependencies to their latest available releases, including `jsv` `0.18.1`, `credo` `1.7.18`, and `castore` `1.0.18`.
- Bumped the package and documentation version references to `0.3.0`.

### Fixed
- Discriminated union JSON Schema generation now preserves full branch fidelity instead of collapsing variant fields to bare types.
- Nested object properties, descriptions, aliases, examples, defaults, numeric/string constraints, and strict `additionalProperties` settings are now retained inside discriminated-union branches.
- Generated discriminator mappings now resolve to concrete definition targets in the emitted schema.
- Generated discriminated-union schemas now require the discriminator field consistently with Sinter's runtime validator.

## [0.2.0] - 2026-03-12

### Added
- **Discriminated unions** — new `:discriminated_union` type selects a schema variant based on a discriminator field value, for polymorphic JSON APIs.
- **Literal type** — new `:literal` type for exact value matching.
- **Field aliases** — `:alias` option on field definitions maps canonical Elixir keys to different external string keys; the validator checks both names and the transform module can output aliased keys.
- **Pre-validate hook** — schema-level `:pre_validate` function transforms raw input before standard validation begins.
- **Per-field validators** — `:validate` option runs custom functions after type checks for field-level logic and transformation.
- JSON Schema generation now emits `oneOf` with discriminator mappings and supports property name overrides for aliases.
- New test suites for discriminated unions, field aliases, field validators, and pre-validate hooks.

### Changed
- Added comprehensive documentation guides (getting started, schema definition, validation, JSON schema, JSON serialization, DSPEx integration).
- Enhanced ExDoc configuration with grouped extras, module categories, and additional output formatters.
- Upgraded `jsv` dependency from `~> 0.13.1` to `~> 0.16.0`.
- Upgraded `nimble_options` from `~> 1.0` to `~> 1.1`.
- Upgraded `ex_doc` from `~> 0.34` to `~> 0.40.1`.
- Upgraded `stream_data` from `~> 1.1` to `~> 1.3`, `mix_test_watch` to `~> 1.4`, `excoveralls` to `~> 0.18.5`, `benchee` to `~> 1.5`.
- Updated `credo`, `dialyxir`, and supporting libraries to latest stable releases.
- Added `castore` as a test-only dependency for certificate handling.
- Replaced `length(list) > 0` with `list != []` for O(1) emptiness checks in `dspex.ex` and `performance.ex`.
- Moved `preferred_cli_env` settings into a dedicated `cli/0` function in `mix.exs` following current Elixir best practices.

## [0.1.0] - 2025-12-27

### Added
- String-keyed schema fields and nested object schema DSL (`Schema.object/1`).
- Built-in format types (`:date`, `:datetime`, `:uuid`, `:null`, `{:nullable, type}`).
- JSON encode/decode helpers with transform pipeline (`Sinter.JSON`, `Sinter.Transform`, `Sinter.NotGiven`).
- Example runner `examples/run_all.sh` and refreshed example suite.

### Changed
- Big-bang refactor of core schema/validation architecture per technical design.
- JSON Schema validation now uses `jsv` 0.13.1 with Draft 2020-12 default and Draft 7 provider support.
- Provider JSON Schema generation applies strictness recursively for nested objects.
- Schema inference avoids atom leaks by defaulting to string keys.

### Fixed
- Required/default ordering so defaults apply before required checks.
- `validate_many/3` base path ordering.

## [0.0.2] - 2025-12-27

### Changed
- Switched JSON Schema validation to `ex_json_schema` v0.11.2.
- Updated generated `$schema` to JSON Schema Draft 7 for validator compatibility.
- Removed custom JSON Schema structural validation helpers in favor of meta-schema validation.

## [0.0.1] - 2025-07-05

### Added
- Initial release of Sinter
- Unified schema definition, validation, and JSON generation for Elixir
- Core features:
  - Unified schema definition with `Sinter.Schema.define/2`
  - Single validation pipeline with `Sinter.Validator.validate/3`
  - JSON Schema generation with `Sinter.JsonSchema.generate/2`
  - Dynamic schema creation for frameworks like DSPy
  - Schema inference from examples
  - Schema merging for composition
  - Provider-specific JSON Schema optimizations
- Convenience helpers:
  - `validate_type/3` for one-off type validation
  - `validate_value/4` for single field validation
  - `validate_many/1` for multiple value validation
- Compile-time macro support with `use_schema`
- Comprehensive example suite
- Full test coverage
- Documentation and API reference

[0.3.0]: https://github.com/nshkrdotcom/sinter/releases/tag/v0.3.0
[0.2.0]: https://github.com/nshkrdotcom/sinter/releases/tag/v0.2.0
[0.1.0]: https://github.com/nshkrdotcom/sinter/releases/tag/v0.1.0
[0.0.2]: https://github.com/nshkrdotcom/sinter/releases/tag/v0.0.2
[0.0.1]: https://github.com/nshkrdotcom/sinter/releases/tag/v0.0.1
