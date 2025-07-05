# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.0.1]: https://github.com/nshkrdotcom/sinter/releases/tag/v0.0.1