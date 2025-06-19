# Sinter

**Unified schema definition, validation, and JSON generation for Elixir**

[![CI](https://github.com/nshkrdotcom/sinter/actions/workflows/ci.yml/badge.svg)](https://github.com/nshkrdotcom/sinter/actions/workflows/ci.yml)

Sinter is a focused, high-performance schema validation library for Elixir, designed specifically to power dynamic frameworks like DSPy. Born from the refactoring of Elixact, Sinter embodies the principle of **distillation** - transforming complex, overlapping APIs into a single, unified, and powerful validation engine.

## Why "Sinter"?

**Sintering** is the process of fusing particles into a solid mass, mirroring how the library coalesces raw data into validated structures. It's a modern, technical term with an alchemical vibe that suggests strength and unification - ideal for a library that unifies compile-time and runtime schemas for dynamic frameworks.

## Philosophy

Sinter follows the **"One True Way"** principle:
- **One way** to define schemas (unified core engine)
- **One way** to validate data (single validation pipeline)  
- **One way** to generate JSON Schema (unified generator)
- **Clear separation** of concerns (validation vs. transformation)

This architectural simplicity makes Sinter perfect for dynamic frameworks that need to create and modify schemas at runtime.

## Features

### 🎯 **Unified Schema Definition**
```elixir
# Runtime schema creation
fields = [
  {:name, :string, [required: true, min_length: 2]},
  {:age, :integer, [optional: true, gt: 0]},
  {:email, :string, [required: true, format: ~r/@/]}
]
schema = Sinter.Schema.define(fields, title: "User Schema")

# Compile-time macro (uses same engine internally)
defmodule UserSchema do
  import Sinter.Schema
  
  use_schema do
    option :title, "User Schema"
    option :strict, true
    
    field :name, :string, [required: true, min_length: 2]
    field :age, :integer, [optional: true, gt: 0]  
    field :email, :string, [required: true, format: ~r/@/]
  end
end
```

### ⚡ **Single Validation Pipeline**
```elixir
# Works with any schema type
{:ok, validated} = Sinter.Validator.validate(schema, data)

# Optional post-validation hook for cross-field checks
schema_with_hook = Sinter.Schema.define(fields, 
  post_validate: &check_business_rules/1
)
```

### 🔄 **Dynamic Schema Creation (Perfect for DSPy)**
```elixir
# Create schemas on the fly - ideal for DSPy teleprompters
def create_program_signature(input_fields, output_fields) do
  all_fields = input_fields ++ output_fields
  Sinter.Schema.define(all_fields, title: "DSPy Program Signature")
end

# MIPRO-style dynamic optimization
optimized_schema = create_program_signature.(
  [{:question, :string, [required: true]}],
  [{:answer, :string, [required: true]}, 
   {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]}]
)

# Infer schemas from examples
examples = [
  %{"name" => "Alice", "age" => 30},
  %{"name" => "Bob", "age" => 25}
]
inferred_schema = Sinter.infer_schema(examples)

# Merge schemas for composition
input_schema = Sinter.Schema.define([{:query, :string, [required: true]}])
output_schema = Sinter.Schema.define([{:answer, :string, [required: true]}])
program_schema = Sinter.merge_schemas([input_schema, output_schema])
```

### 📋 **Unified JSON Schema Generation**
```elixir
# Single function handles all schema types
json_schema = Sinter.JsonSchema.generate(schema)

# Provider-specific optimizations
openai_schema = Sinter.JsonSchema.for_provider(schema, :openai)
anthropic_schema = Sinter.JsonSchema.for_provider(schema, :anthropic)
```

### 🛠 **Convenience Helpers**
```elixir
# One-off type validation
{:ok, 42} = Sinter.validate_type(:integer, "42", coerce: true)

# Single field validation
{:ok, "john@example.com"} = Sinter.validate_value(:email, :string, 
  "john@example.com", [format: ~r/@/])

# Multiple value validation
{:ok, results} = Sinter.validate_many([
  {:string, "hello"},
  {:integer, 42},
  {:email, :string, "test@example.com", [format: ~r/@/]}
])
```

## Architecture

Sinter's architecture follows the **distillation principle** - extracting the essential, powerful core from complex systems:

```
┌─────────────────────────────────────────────┐
│              Sinter Core Engine             │
├─────────────────────────────────────────────┤
│  Sinter.Schema.define/2 (The Single Source) │
├─────────────────────────────────────────────┤
│         Sinter.Validator.validate/3         │
├─────────────────────────────────────────────┤
│         Sinter.JsonSchema.generate/2        │
└─────────────────────────────────────────────┘
           ▲                    ▲
           │                    │
    ┌──────────────┐    ┌──────────────┐
    │  Built-in    │    │   Built-in   │
    │ Compile-time │    │   Runtime    │
    │  use_schema  │    │   Helpers    │
    │   (macro)    │    │              │
    └──────────────┘    └──────────────┘
                               │
                        ┌──────────────┐
                        │validate_type │
                        │validate_value│
                        │validate_many │
                        └──────────────┘
```

**All components shown are part of Sinter** - there are no external dependencies or systems required. The architecture shows:

- **Core Engine**: The unified validation pipeline that all features use internally
- **Compile-time macro**: `use_schema` - A convenience for defining schemas at compile time
- **Runtime helpers**: `validate_type`, `validate_value`, `validate_many` - Convenience functions for quick validation tasks

Everything flows through the same core engine, ensuring consistency and reliability across all usage patterns.

## Architectural Benefits

### ✅ **From Elixact's Complexity**
- 5 different ways to define schemas → **1 unified way**
- 4 validation modules → **1 validation engine**  
- 3 JSON Schema modules → **1 generator**
- Complex transformation pipeline → **Simple validation + explicit app logic**

### ✅ **Perfect for DSPy/Dynamic Frameworks**
- Runtime schema creation without architectural friction
- Clean separation: validation (Sinter) vs. transformation (your app)
- No "magic" - every step in your program is explicit and optimizable
- Unified API means less cognitive overhead

### ✅ **Performance Benefits**
- Fewer abstraction layers = less overhead
- Single validation path = easier optimization
- No complex transformation pipeline = cleaner performance profile

## Installation

Add `sinter` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sinter, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# 1. Define a schema
fields = [
  {:name, :string, [required: true]},
  {:age, :integer, [optional: true, gt: 0]}
]
schema = Sinter.Schema.define(fields)

# 2. Validate data  
{:ok, validated} = Sinter.Validator.validate(schema, %{
  name: "Alice",
  age: 30
})

# 3. Generate JSON Schema
json_schema = Sinter.JsonSchema.generate(schema)
```

### 🚀 Try the Examples

Explore comprehensive examples covering all functionality:

```bash
# Run all examples with detailed reporting
cd examples && elixir run_all.exs

# Or run individual examples
cd examples
elixir basic_usage.exs           # Core functionality
elixir readme_comprehensive.exs  # All README examples  
elixir dspy_integration.exs      # DSPy framework patterns
```

See [`examples/README.md`](examples/README.md) for detailed documentation.

## Migration from Elixact

Sinter provides a clean migration path from Elixact's complex APIs:

| Elixact (Before) | Sinter (After) |
|------------------|----------------|
| `Elixact.Runtime.create_schema` | `Sinter.Schema.define` |
| `EnhancedValidator.validate` | `Sinter.Validator.validate` |  
| `TypeAdapter.validate` | `Sinter.validate_type` |
| `Wrapper.wrap_and_validate` | `Sinter.validate_value` |
| Multiple JSON Schema modules | `Sinter.JsonSchema.generate` |

## Key Design Decisions

### **Validation ≠ Transformation**
Sinter validates data structure and constraints. Data transformation is your application's responsibility, keeping your program logic explicit and optimizable.

### **Runtime-First Design**  
While compile-time macros are supported, the core engine is built for runtime schema creation - perfect for dynamic frameworks.

### **Proven Foundation**
Sinter leverages battle-tested Elixir libraries:
- **Jason** - Fast, reliable JSON parsing
- **ExUnit** - Comprehensive testing framework
- **Dialyzer** - Static type analysis

## Documentation

- [API Reference](https://hexdocs.pm/sinter)
- [Examples Directory](examples/) - Comprehensive working examples

## Contributing

We welcome contributions! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes with tests
4. Run the full test suite (`mix test`)
5. Submit a pull request

## License

MIT

## Acknowledgments

Sinter is the distilled essence of [Elixact](https://github.com/your-org/elixact), refactored specifically for dynamic framework needs. Special thanks to the Elixact contributors and the broader Elixir validation ecosystem.

---

*"In the furnace of simplicity, complexity becomes strength."*
