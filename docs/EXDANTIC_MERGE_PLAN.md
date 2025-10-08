# Exdantic → Sinter Merge Plan

## Executive Summary

This document outlines the plan to merge Exdantic's advanced features into Sinter, creating a unified validation library that combines Sinter's clean architecture with Exdantic's rich feature set.

**Timeline:** 3 weeks
**Breaking Changes:** Minimal (Sinter v0.1.0 → v0.2.0)
**User Impact:** Low (Exdantic has ~574 downloads, Sinter is new)
**Result:** One production-ready library with both simplicity AND power

---

## 1. Strategic Rationale

### Why Merge?

**Current State:**
- **Sinter:** 3,500 LOC, clean architecture, focused, production-ready
- **Exdantic:** 7,758 LOC, feature-rich, cruft-heavy, complex

**The Problem:**
- Maintaining two similar libraries = 2x effort
- Exdantic has useful features but architectural debt
- Sinter has clean architecture but limited features
- Overlap in core functionality = wasted effort

**The Solution:**
- Port Exdantic's **unique** features to Sinter's **clean** architecture
- Deprecate Exdantic
- Focus all effort on one excellent library

### What We're Merging

**From Exdantic (keep):**
- ✅ Struct generation (`define_struct: true`)
- ✅ Computed fields (derived fields after validation)
- ✅ Model validators (enhanced cross-field validation)
- ✅ Enhanced JSON Schema features (better LLM optimization)
- ✅ RootSchema pattern (non-dictionary validation)
- ✅ Advanced configuration options

**From Exdantic (discard):**
- ❌ Multiple overlapping validators (Validator, EnhancedValidator, StructValidator)
- ❌ Wrapper module (fold into convenience helpers)
- ❌ Config.builder pattern (just use keyword opts)
- ❌ Phase references and cruft
- ❌ 752KB of docJune/ planning docs

---

## 2. Feature Analysis & Porting Strategy

### Feature 1: Struct Generation (Priority: HIGH)

**Exdantic Implementation:**
- File: `lib/exdantic/struct_validator.ex` (682 lines)
- Usage: `use Exdantic, define_struct: true`
- Returns: `%UserSchema{}` struct instances

**Sinter Integration Plan:**

```elixir
# New module: lib/sinter/struct.ex (~300 lines)
defmodule Sinter.Struct do
  @moduledoc """
  Optional struct generation for Sinter schemas.

  When enabled, validation returns struct instances instead of maps,
  providing compile-time field access and better type safety.
  """

  defmacro __using__(opts) do
    # Generate struct and validation functions
  end
end

# Usage in Sinter
defmodule UserSchema do
  use Sinter.Schema
  use Sinter.Struct  # Opt-in struct generation

  define_schema do
    field :name, :string, required: true
    field :age, :integer, optional: true
  end
end

# Returns struct
{:ok, %UserSchema{name: "John", age: 30}} = UserSchema.validate(data)
```

**Porting Effort:**
- Extract core logic from Exdantic's struct_validator.ex
- Simplify by removing redundant validation paths
- Reuse Sinter's validation engine
- **Estimated:** 2 days

**Lines of Code:** ~300 (vs 682 in Exdantic)

---

### Feature 2: Computed Fields (Priority: HIGH)

**Exdantic Implementation:**
- File: `lib/exdantic/computed_field_meta.ex` (225 lines)
- Usage: `computed_field :display_name, :string, :generate_display`
- Executes after field validation

**Sinter Integration Plan:**

```elixir
# New module: lib/sinter/computed_fields.ex (~200 lines)
defmodule Sinter.ComputedFields do
  @moduledoc """
  Computed fields derive values from validated data.

  Computed fields are calculated after field validation succeeds
  and before the final result is returned.
  """
end

# Usage in Sinter
defmodule UserSchema do
  use Sinter.Schema
  use Sinter.Struct
  use Sinter.ComputedFields  # Opt-in computed fields

  define_schema do
    field :first_name, :string, required: true
    field :last_name, :string, required: true

    # New: computed field macro
    computed :full_name, :string, &generate_full_name/1
    computed :display, :string, fn input ->
      "#{input.first_name} #{input.last_name}"
    end
  end

  def generate_full_name(input) do
    "#{input.first_name} #{input.last_name}"
  end
end
```

**Integration with Sinter:**
- Hook into Sinter.Validator pipeline after field validation
- Validate computed field output types
- Include in JSON Schema with `"readOnly": true`

**Porting Effort:**
- Extract core logic from Exdantic
- Integrate with Sinter's post_validate hook
- Add to schema DSL
- **Estimated:** 2 days

**Lines of Code:** ~200 (vs 225 in Exdantic)

---

### Feature 3: Enhanced Model Validators (Priority: MEDIUM)

**Exdantic Implementation:**
- Built into schema DSL: `model_validator :function_name`
- Supports both named and anonymous functions
- Runs after field validation, before computed fields

**Sinter Current State:**
- Has `post_validate` option taking single function
- Simpler but less flexible

**Sinter Integration Plan:**

```elixir
# Enhance existing Sinter.Schema
defmodule Sinter.Schema do
  # Extend define_schema macro to support multiple validators

  define_schema do
    field :password, :string, required: true
    field :password_confirm, :string, required: true

    # NEW: Support multiple validators (backward compatible)
    validate &check_passwords_match/1
    validate &ensure_strong_password/1

    # OLD: Still supported
    post_validate &legacy_validator/1
  end
end

# Validators run in order
def check_passwords_match(data) do
  if data.password == data.password_confirm do
    {:ok, Map.delete(data, :password_confirm)}
  else
    {:error, "Passwords must match"}
  end
end
```

**Porting Effort:**
- Extend Sinter.Schema macro to accumulate validators
- Modify Sinter.Validator to run validator chain
- Support both named functions and anonymous functions
- Maintain backward compatibility with `post_validate`
- **Estimated:** 1 day

**Lines of Code:** ~100 additional (enhancement to existing modules)

---

### Feature 4: RootSchema Pattern (Priority: MEDIUM)

**Exdantic Implementation:**
- File: `lib/exdantic/root_schema.ex` (267 lines)
- Usage: `use Exdantic.RootSchema, root: {:array, :integer}`
- Validates non-dictionary types at root

**Sinter Integration Plan:**

```elixir
# New module: lib/sinter/root.ex (~150 lines)
defmodule Sinter.Root do
  @moduledoc """
  Root-level validation for non-map types.

  Validates arrays, primitives, unions at the root level
  instead of object schemas.
  """

  defmacro __using__(opts) do
    # Generate validation for root type
  end
end

# Usage
defmodule IntegerList do
  use Sinter.Root, type: {:array, :integer}
end

{:ok, [1,2,3]} = IntegerList.validate([1,2,3])

# Alternative: Just use existing helpers
{:ok, [1,2,3]} = Sinter.validate_type({:array, :integer}, [1,2,3])
```

**Question:** Do we even need this? Sinter already has `validate_type/3` which does this.

**Decision:**
- **Option A:** Don't port, just document `validate_type` as the solution
- **Option B:** Port as syntactic sugar for module-based approach

**Recommendation:** **Skip this** - `Sinter.validate_type` already handles this use case. Add example to docs instead.

**Porting Effort:** 0 (use existing)

---

### Feature 5: Enhanced JSON Schema Features (Priority: HIGH)

**Exdantic Implementation:**
- Enhanced resolver with LLM provider optimizations
- Computed field metadata in JSON Schema
- Field classification for DSPy

**Current State:**
- Exdantic: 936 lines (`enhanced_resolver.ex`)
- Sinter: 505 lines (`json_schema.ex`)

**Sinter Integration Plan:**

```elixir
# Enhance existing lib/sinter/json_schema.ex
defmodule Sinter.JsonSchema do
  # Add support for computed fields metadata
  # Add x-computed-field markers
  # Add readOnly for computed fields
  # Enhance provider optimizations
end
```

**Features to Port:**
- ✅ Computed field handling in JSON Schema
- ✅ Enhanced provider optimization
- ✅ Field classification metadata
- ✅ DSPy signature mode optimizations

**Porting Effort:**
- Extract relevant optimizations from Exdantic
- Integrate into Sinter's generator
- Add tests
- **Estimated:** 2 days

**Additional Lines:** ~200 (enhancement to existing module)

---

### Feature 6: Advanced Configuration (Priority: LOW)

**Exdantic Implementation:**
- `Config.create(opts)` - 846 lines
- `Config.builder()` pattern - 735 lines
- **Total: 1,581 lines**

**Sinter Approach:**
- Just use keyword opts passed to validate functions
- No separate Config module needed

**Decision:** **DON'T PORT**

**Rationale:**
- Elixir convention: keyword opts, not config objects
- Sinter's approach is cleaner
- 1,581 lines of unnecessary abstraction
- Configuration is just options

**If advanced config needed:**
```elixir
# Instead of Exdantic's way
config = Exdantic.Config.builder()
         |> strict(true)
         |> safe_coercion()
         |> build()
Exdantic.validate(schema, data, config: config)

# Sinter's way (cleaner)
Sinter.Validator.validate(schema, data,
  strict: true,
  coerce: :safe
)
```

**Porting Effort:** 0 (don't port)

---

## 3. New Sinter Architecture (Post-Merge)

### File Structure

```
lib/sinter/
├── sinter.ex                 (~600 lines) - Main API, unchanged
├── schema.ex                 (~650 lines) - Schema DSL, enhanced
├── validator.ex              (~600 lines) - Core validation, enhanced
├── types.ex                  (~530 lines) - Type system, unchanged
├── json_schema.ex            (~700 lines) - JSON Schema, enhanced
├── error.ex                  (~400 lines) - Error handling, unchanged
├── dspex.ex                  (~450 lines) - DSPy helpers, enhanced
├── performance.ex            (~230 lines) - Performance utils, unchanged
├── struct.ex                 (~300 lines) - NEW: Struct generation
├── computed_fields.ex        (~200 lines) - NEW: Computed fields
└── root.ex                   (~100 lines) - OPTIONAL: Root validation
```

**Total Estimated LOC:** ~4,800 lines (vs 3,500 current, 7,758 Exdantic)

**New Module Count:** 11 (vs 8 current, 26 Exdantic)

---

## 4. API Design: Backward Compatible Extension

### Core API (Unchanged)

```elixir
# Existing Sinter API - 100% backward compatible
schema = Sinter.Schema.define(fields, opts)
{:ok, validated} = Sinter.Validator.validate(schema, data)
json_schema = Sinter.JsonSchema.generate(schema)

# Convenience helpers - unchanged
Sinter.validate_type(type, value, opts)
Sinter.validate_value(name, type, value, opts)
Sinter.infer_schema(examples)
Sinter.merge_schemas(schemas)
```

### New Features (Opt-in)

```elixir
# Feature 1: Struct Generation
defmodule UserSchema do
  use Sinter.Schema
  use Sinter.Struct  # NEW: Opt-in

  define_schema do
    field :name, :string, required: true
    field :age, :integer, optional: true
  end
end

{:ok, %UserSchema{}} = UserSchema.validate(data)

# Feature 2: Computed Fields
defmodule UserSchema do
  use Sinter.Schema
  use Sinter.Struct
  use Sinter.ComputedFields  # NEW: Opt-in

  define_schema do
    field :first_name, :string, required: true
    field :last_name, :string, required: true

    computed :full_name, :string, fn input ->
      "#{input.first_name} #{input.last_name}"
    end
  end
end

# Feature 3: Multiple Validators (Enhancement to existing)
define_schema do
  field :password, :string, required: true
  field :confirm, :string, required: true

  validate &check_passwords/1  # NEW: multiple validators
  validate &ensure_strength/1

  # OLD: still works
  post_validate &legacy_validator/1
end

# Feature 4: Enhanced JSON Schema (automatic)
json_schema = Sinter.JsonSchema.generate(schema)
# Automatically includes computed fields with readOnly: true
# Enhanced LLM provider optimizations
```

### Backward Compatibility

**100% of existing Sinter code continues to work:**
- All existing functions unchanged
- New features are opt-in via `use` directives
- No breaking changes to core API

---

## 5. Detailed Implementation Plan

### Week 1: Core Feature Porting

#### Day 1-2: Struct Generation

**Tasks:**
1. Create `lib/sinter/struct.ex`
2. Extract clean struct generation logic from Exdantic
3. Integrate with Sinter.Schema macro system
4. Write tests (target: 90%+ coverage)

**Key Code to Port:**
- Struct definition generation
- `defstruct` macro integration
- `dump/1` function for serialization
- `__struct_fields__` introspection

**Estimated LOC:** ~300 lines

**Tests:**
- Basic struct generation
- Struct validation returns correct type
- Dump functionality
- Integration with regular fields
- Integration with computed fields

#### Day 3-4: Computed Fields

**Tasks:**
1. Create `lib/sinter/computed_fields.ex`
2. Port computed field logic from Exdantic
3. Integrate into Sinter.Validator pipeline
4. Add JSON Schema support
5. Write tests (target: 90%+ coverage)

**Key Code to Port:**
- Computed field macro
- Field computation execution
- Type validation of computed values
- Error handling for computation failures

**Integration Points:**
- Add `computed` macro to schema DSL
- Hook into validator after field validation
- Add to JSON Schema generator with `readOnly: true`
- Support in struct generation

**Estimated LOC:** ~200 lines

**Tests:**
- Basic computed field execution
- Type validation of computed results
- Error handling
- Anonymous functions
- Named functions
- Integration with structs
- JSON Schema generation

#### Day 5: Model Validators Enhancement

**Tasks:**
1. Enhance existing `Sinter.Schema` to support multiple validators
2. Add `validate` macro alongside existing `post_validate`
3. Support anonymous functions
4. Maintain backward compatibility
5. Write tests

**Implementation:**

```elixir
# lib/sinter/schema.ex - enhance existing
defmacro define_schema(do: block) do
  quote do
    @sinter_validators []  # NEW: accumulate validators

    unquote(block)

    validators = Enum.reverse(@sinter_validators)
    # Chain validators with existing post_validate
  end
end

defmacro validate(validator) do
  quote do
    @sinter_validators [unquote(validator) | @sinter_validators]
  end
end
```

**Estimated LOC:** ~100 additional lines in existing files

**Tests:**
- Multiple validators
- Validator order execution
- Anonymous functions
- Named functions
- Backward compatibility with post_validate

---

### Week 2: Enhanced Features & Polish

#### Day 6-7: Enhanced JSON Schema Features

**Tasks:**
1. Enhance `lib/sinter/json_schema.ex`
2. Add computed field metadata
3. Improve provider optimizations
4. Add DSPy signature mode
5. Write tests

**New Features:**
```elixir
# Enhanced provider optimization
Sinter.JsonSchema.generate(schema,
  provider: :openai,
  include_computed_fields: true,
  dspy_signature_mode: true
)

# Computed fields marked as readOnly
{
  "properties": {
    "full_name": {
      "type": "string",
      "readOnly": true,
      "x-computed": true
    }
  }
}
```

**Estimated LOC:** ~200 additional lines

#### Day 8-9: Documentation & Examples

**Tasks:**
1. Update main README.md with new features
2. Create migration guide from Exdantic
3. Add examples for each new feature
4. Update API documentation

**New Examples:**
- `examples/struct_generation.exs`
- `examples/computed_fields.exs`
- `examples/advanced_validation.exs` (update)
- `examples/dspy_integration.exs` (update)

**New Docs:**
- `docs/STRUCT_GENERATION.md`
- `docs/COMPUTED_FIELDS.md`
- `docs/EXDANTIC_MIGRATION.md`

#### Day 10: Integration Testing

**Tasks:**
1. Test all features together
2. Performance benchmarking
3. Fix edge cases
4. Update tests for 80%+ coverage

---

### Week 3: Release & Deprecation

#### Day 11-12: Final Testing & Polish

**Tasks:**
1. Run full test suite (target: >95% pass rate)
2. Run coverage report (target: >75% overall, >90% core)
3. Run Credo (target: 0 issues)
4. Run Dialyzer (fix critical issues)
5. Performance benchmarks
6. Code review

**Quality Gates:**
- ✅ >95% test pass rate
- ✅ >75% test coverage
- ✅ 0 Credo issues
- ✅ All examples pass
- ✅ Documentation complete

#### Day 13-14: Release Sinter v0.2.0

**Tasks:**
1. Update CHANGELOG.md
2. Tag v0.2.0 release
3. Publish to Hex.pm
4. Update documentation on HexDocs
5. Create release notes

**Release Notes:**
```markdown
# Sinter v0.2.0 - Feature Expansion

## New Features

### Struct Generation
Generate typed structs from schemas for compile-time safety.

### Computed Fields
Derive fields automatically after validation.

### Enhanced Model Validators
Support multiple validation functions with both named and anonymous functions.

### Enhanced JSON Schema
Improved LLM provider optimizations and computed field metadata.

## Backward Compatibility
100% backward compatible with v0.1.0. All new features are opt-in.

## Migration from Exdantic
See docs/EXDANTIC_MIGRATION.md for migration guide.
```

#### Day 15: Deprecate Exdantic

**Tasks:**
1. Update Exdantic README with deprecation notice
2. Update Hex.pm description
3. Create final Exdantic release (v0.0.3) with deprecation
4. Archive Exdantic repository (read-only)

**Exdantic Deprecation Notice:**

```markdown
# ⚠️ DEPRECATED - Use Sinter Instead

Exdantic has been merged into [Sinter](https://hex.pm/packages/sinter).

All Exdantic features are now available in Sinter v0.2.0 with:
- Cleaner architecture
- Better performance
- Unified API
- Continued maintenance

## Migration Guide

See [Sinter Migration Guide](https://hexdocs.pm/sinter/EXDANTIC_MIGRATION.html)

## Why Deprecated?

Exdantic and Sinter had significant overlap. Rather than maintain two
similar libraries, we've consolidated the best features into Sinter.

Last Exdantic version: 0.0.3 (maintenance mode only)
```

---

## 6. Migration Guide for Exdantic Users

### Basic Schema Definition

**Exdantic (old):**
```elixir
defmodule UserSchema do
  use Exdantic, define_struct: true

  schema "User info" do
    field :name, :string do
      required()
      min_length(2)
    end
  end
end
```

**Sinter (new):**
```elixir
defmodule UserSchema do
  use Sinter.Schema
  use Sinter.Struct

  define_schema title: "User info" do
    field :name, :string, required: true, min_length: 2
  end
end
```

### Runtime Schemas

**Exdantic (old):**
```elixir
schema = Exdantic.Runtime.create_schema(fields, opts)
Exdantic.Runtime.validate(data, schema)
```

**Sinter (new):**
```elixir
schema = Sinter.Schema.define(fields, opts)
Sinter.Validator.validate(schema, data)
```

### TypeAdapter

**Exdantic (old):**
```elixir
Exdantic.TypeAdapter.validate(:integer, "42", coerce: true)
```

**Sinter (new):**
```elixir
Sinter.validate_type(:integer, "42", coerce: true)
```

### Computed Fields

**Exdantic (old):**
```elixir
computed_field :display, :string, :generate_display
```

**Sinter (new):**
```elixir
computed :display, :string, &generate_display/1
```

### Model Validators

**Exdantic (old):**
```elixir
model_validator :validate_data
```

**Sinter (new):**
```elixir
validate &validate_data/1
```

---

## 7. Code Volume Analysis

### Current State

```
Sinter v0.1.0:  ~3,500 LOC (8 modules)
Exdantic v0.0.2: 7,758 LOC (26 modules)
```

### After Merge (Sinter v0.2.0)

```
Core modules (unchanged):     ~2,800 LOC
Enhanced modules:             ~  500 LOC
New struct module:            ~  300 LOC
New computed fields module:   ~  200 LOC
Enhanced JSON Schema:         ~  200 LOC
Optional root module:         ~  100 LOC (if included)
-----------------------------------------
Total:                        ~4,900 LOC (11 modules)
```

**Efficiency Gain:**
- Combined functionality: Sinter + Exdantic features
- Total LOC: 4,900 (vs 11,258 if kept separate)
- **56% reduction** from combined total
- **40% increase** from Sinter alone (for 2x features)

---

## 8. Testing Strategy

### Coverage Targets

**Post-merge coverage goals:**

| Module | Current | Target | Strategy |
|--------|---------|--------|----------|
| sinter.ex | 91.5% | 92% | Maintain |
| schema.ex | 92.5% | 90% | Enhanced with new features |
| validator.ex | 94.1% | 92% | Enhanced validator chain |
| types.ex | 88.4% | 88% | Maintain |
| json_schema.ex | 88.2% | 85% | Enhanced features |
| struct.ex | - | 90% | NEW |
| computed_fields.ex | - | 90% | NEW |
| **Overall** | 69.1% | **80%** | Comprehensive |

### Test Organization

```
test/sinter/
├── schema_test.exs           (enhanced with validator tests)
├── validator_test.exs        (enhanced with chaining)
├── struct_test.exs           (NEW)
├── computed_fields_test.exs  (NEW)
├── json_schema_test.exs      (enhanced)
└── integration/
    ├── struct_integration_test.exs     (NEW)
    ├── computed_fields_integration.exs (NEW)
    └── full_pipeline_test.exs          (NEW)
```

**Test Count Estimate:**
- Current: 270 tests
- New: +120 tests for new features
- **Total: ~390 tests**

---

## 9. Breaking Changes Assessment

### For Sinter Users (Minimal)

**Breaking Changes:** None planned

**New Features (opt-in):**
- `use Sinter.Struct` - optional
- `use Sinter.ComputedFields` - optional
- Multiple validators - backward compatible
- Enhanced JSON Schema - automatic improvement

**Migration Effort:** **0 minutes** (100% backward compatible)

### For Exdantic Users (Moderate)

**Breaking Changes:**
- Module names change (`Exdantic.*` → `Sinter.*`)
- Some API simplification
- `Config.builder()` removed (use keyword opts)
- `Wrapper` module removed (use `validate_type`)

**Migration Effort:** **1-2 hours** for typical project

**Estimated Exdantic Users Affected:** ~5-10 projects max (based on 574 downloads)

---

## 10. Risk Analysis

### Technical Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Feature port introduces bugs | Medium | Comprehensive testing, code review |
| Increased Sinter complexity | Medium | Keep opt-in, maintain simplicity of core |
| Test coverage drops | Low | Set 80% minimum gate |
| Performance regression | Low | Benchmark before/after |
| API confusion | Low | Clear documentation of when to use features |

### Business Risks

| Risk | Severity | Mitigation |
|------|----------|------------|
| Sinter users unhappy with complexity | Low | Features are opt-in only |
| Exdantic users can't migrate | Very Low | Migration guide + simple API changes |
| Maintaining two libraries | N/A | Deprecating Exdantic solves this |
| Community backlash | Very Low | Minimal community (574 downloads) |

### Overall Risk: **LOW** ✅

---

## 11. Success Metrics

### Quantitative Goals

**Code Metrics:**
- ✅ Sinter LOC: 3,500 → 4,900 (40% increase for 100% feature increase)
- ✅ Module count: 8 → 11 (vs 26 in Exdantic)
- ✅ Test coverage: 69% → 80%+
- ✅ Test pass rate: >95%
- ✅ Credo issues: 0

**Performance Goals:**
- ✅ Validation performance: Maintain <3μs per item
- ✅ Schema creation: <1ms
- ✅ JSON Schema generation: <10ms
- ✅ Struct overhead: <10% vs map validation

**Quality Goals:**
- ✅ All examples pass
- ✅ Documentation complete
- ✅ Migration guide clear
- ✅ API intuitive

### Qualitative Goals

**User Experience:**
- Clear decision tree: when to use which feature
- Opt-in complexity (simple by default, powerful when needed)
- Familiar Pydantic-like features for Python devs
- Maintained Sinter's "one true way" philosophy for core

**Developer Experience:**
- Maintainable codebase (~5k LOC vs 11k combined)
- Clear module boundaries
- Good test coverage
- Easy to extend

---

## 12. Implementation Checklist

### Pre-Work (Before Week 1)

- [ ] Create feature branch: `feat/exdantic-merge`
- [ ] Set up tracking project/issues
- [ ] Review Exdantic features one more time
- [ ] Confirm no external Exdantic dependencies (check Hex.pm again)

### Week 1: Porting

- [ ] Day 1: Create `lib/sinter/struct.ex` skeleton
- [ ] Day 1: Port struct generation logic
- [ ] Day 2: Write struct tests (target 90% coverage)
- [ ] Day 2: Verify struct integration
- [ ] Day 3: Create `lib/sinter/computed_fields.ex` skeleton
- [ ] Day 3: Port computed field logic
- [ ] Day 4: Write computed field tests
- [ ] Day 4: Integrate with JSON Schema generator
- [ ] Day 5: Enhance validator with multiple validators
- [ ] Day 5: Write validator enhancement tests

### Week 2: Enhancement & Documentation

- [ ] Day 6: Enhance `lib/sinter/json_schema.ex`
- [ ] Day 6: Add computed field JSON Schema support
- [ ] Day 7: Improve provider optimizations
- [ ] Day 7: Write JSON Schema enhancement tests
- [ ] Day 8: Create `examples/struct_generation.exs`
- [ ] Day 8: Create `examples/computed_fields.exs`
- [ ] Day 9: Update main README.md
- [ ] Day 9: Write migration guide
- [ ] Day 10: Integration testing
- [ ] Day 10: Performance benchmarking

### Week 3: Release & Deprecation

- [ ] Day 11: Final test sweep (>95% pass, >80% coverage)
- [ ] Day 11: Run Credo (0 issues)
- [ ] Day 12: Code review all changes
- [ ] Day 12: Update CHANGELOG.md
- [ ] Day 13: Release Sinter v0.2.0
- [ ] Day 13: Publish to Hex.pm
- [ ] Day 14: Update Exdantic README (deprecation)
- [ ] Day 14: Release Exdantic v0.0.3 (final)
- [ ] Day 15: Archive Exdantic repo
- [ ] Day 15: Announce on Elixir Forum

---

## 13. File-by-File Porting Guide

### Files to Port (From Exdantic)

#### High Priority (Core Features)

| Exdantic File | Lines | Port To | New Lines | Notes |
|---------------|-------|---------|-----------|-------|
| `struct_validator.ex` | 682 | `sinter/struct.ex` | ~300 | Extract core, remove duplication |
| `computed_field_meta.ex` | 225 | `sinter/computed_fields.ex` | ~200 | Clean implementation |
| `json_schema/enhanced_resolver.ex` | 936 | Merge into `sinter/json_schema.ex` | +200 | Extract enhancements only |

#### Medium Priority (Enhancements)

| Exdantic File | Lines | Port To | New Lines | Notes |
|---------------|-------|---------|-----------|-------|
| Schema validator chaining | - | Enhance `sinter/schema.ex` | +100 | Multiple validators |
| DSPy optimizations | Parts of 936 | Enhance `sinter/dspex.ex` | +100 | LLM features |

#### Low Priority (Maybe)

| Exdantic File | Lines | Port To | Decision |
|---------------|-------|---------|----------|
| `root_schema.ex` | 267 | `sinter/root.ex` or skip | Document `validate_type` instead |
| `config.ex` | 846 | Skip | Use keyword opts |
| `config/builder.ex` | 735 | Skip | Unnecessary abstraction |

#### Don't Port (Cruft/Duplication)

- `enhanced_validator.ex` (944 lines) - Fold into main Validator
- `wrapper.ex` (588 lines) - Fold into convenience helpers
- `runtime/validator.ex` (153 lines) - Already have Validator
- `runtime/dynamic_schema.ex` (275 lines) - Already have Runtime
- All `docJune/` content
- All phase test runners

---

## 14. Post-Merge Sinter Feature Matrix

### Core Features (Existing)

✅ Unified schema definition
✅ Single validation pipeline
✅ Type system with coercion
✅ Constraint validation
✅ JSON Schema generation
✅ Provider optimizations
✅ Dynamic schema creation
✅ Schema inference
✅ Schema merging
✅ Convenience helpers

### New Features (From Exdantic)

🆕 **Struct generation** (`use Sinter.Struct`)
🆕 **Computed fields** (`computed` macro)
🆕 **Multiple validators** (`validate` macro)
🆕 **Enhanced JSON Schema** (computed field metadata)
🆕 **DSPy field classification** (enhanced provider opts)

### Removed Complexity

❌ No Config.builder pattern
❌ No Wrapper module
❌ No Enhanced vs Basic split
❌ No multiple validator implementations
❌ No phase cruft

---

## 15. Competitive Position After Merge

### Sinter v0.2.0 vs Alternatives

**vs Ecto.Changeset:**
- ✅ Simpler API
- ✅ Better JSON Schema generation
- ✅ LLM/DSPy optimization
- ❌ Not database-focused (intentional)

**vs ExJsonSchema:**
- ✅ Validation + generation in one
- ✅ Elixir-native schemas (not JSON)
- ✅ Struct generation
- ✅ Computed fields

**vs Vex:**
- ✅ Richer type system
- ✅ JSON Schema generation
- ✅ Modern, maintained
- ✅ DSPy integration

**vs Exdantic (deprecated):**
- ✅ Simpler architecture (4,900 vs 7,758 LOC)
- ✅ Cleaner API (no overlapping validators)
- ✅ No cruft
- ✅ Better maintained
- ✅ All the same features

**Unique Value Proposition:**
> "The only Elixir validation library with first-class DSPy/LLM support,
> struct generation, and Pydantic-inspired patterns in a clean, unified API."

---

## 16. Communication Plan

### Announcement Strategy

#### For Elixir Forum

**Title:** "Sinter v0.2.0: Pydantic-Inspired Validation with Struct Generation & Computed Fields"

**Content:**
```markdown
Hi Elixir community!

I'm excited to announce Sinter v0.2.0, which brings Pydantic-inspired
features to Elixir validation:

🆕 Struct generation from schemas
🆕 Computed fields (derived data)
🆕 Enhanced model validators
🆕 LLM/DSPy optimizations

These features come from merging Exdantic into Sinter, giving you
the best of both worlds: Sinter's clean architecture + Exdantic's
rich features.

100% backward compatible with Sinter v0.1.0.

Exdantic is now deprecated in favor of this unified library.

Check it out: https://hex.pm/packages/sinter
```

#### For GitHub

**Sinter Release Notes:**
- Detailed changelog
- Migration guide link
- Feature showcase
- Performance benchmarks

**Exdantic Deprecation:**
- Clear notice in README
- Link to Sinter
- Migration guide
- Archive repository (read-only)

---

## 17. Rollback Plan

**If merge fails or problems arise:**

### Rollback Triggers

- Test coverage drops below 65%
- Test pass rate drops below 90%
- Performance degrades >20%
- Critical bugs discovered
- API becomes too complex

### Rollback Procedure

1. Revert feature branch
2. Release Sinter v0.1.1 (bug fixes only)
3. Keep Exdantic active
4. Reassess strategy

**Rollback Effort:** <1 day (git revert)

---

## 18. Decision Matrix

### Should You Merge? Decision Tree

```
Q: Do you want to maintain two similar libraries?
└─ NO → Merge

Q: Are Exdantic's features worth keeping?
└─ YES → Merge

Q: Can you afford breaking changes?
└─ YES (574 downloads, v0.0.2) → Merge

Q: Is Exdantic's architecture better than Sinter's?
└─ NO (Sinter is cleaner) → Merge

Q: Do you have time for 3-week project?
└─ YES → Merge
└─ NO → Conservative cleanup (Path 3)
```

**Result: MERGE** ✅

---

## 19. Final Recommendation

### ✅ PROCEED WITH MERGER

**Confidence Level: HIGH (90%)**

**Why I'm confident:**
1. **User impact is minimal** (574 downloads, likely <10 real users)
2. **You control both libraries** (single maintainer)
3. **Pre-1.0 versions** (breaking changes expected)
4. **Clear technical benefits** (cleaner code, less maintenance)
5. **You've done this before** (Elixact → Sinter, now Exdantic → Sinter)

**Why this is the right move:**
1. **Sinter's architecture is proven** (94% test pass in core, 0 cruft)
2. **Exdantic has valuable features** (structs, computed fields)
3. **Combined is stronger** (best of both)
4. **Maintenance burden halves** (1 library instead of 2)
5. **Professional result** (no cruft, clear API)

**The timing is perfect:**
- Exdantic: v0.0.2 (pre-release, low adoption)
- Sinter: v0.0.1 (fresh, clean)
- Your workload: Manageable (3-week project)
- User impact: Minimal (basically zero)

**Next step:** Review this plan, ask questions, then I'll create the detailed implementation spec for Week 1.

---

**Document Version:** 1.0
**Created:** 2025-10-08
**Author:** Claude (Sonnet 4.5)
**Status:** Awaiting approval to proceed
