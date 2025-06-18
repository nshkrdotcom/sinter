# Sinter

**Unified schema definition, validation, and JSON generation for Elixir**

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen.svg)]()
[![Hex Version](https://img.shields.io/badge/hex-0.1.0-blue.svg)]()
[![Documentation](https://img.shields.io/badge/docs-hexdocs-purple.svg)]()

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
optimized_schema = create_program_signature(
  [{:question, :string, [required: true]}],
  [{:answer, :string, [required: true]}, 
   {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]}]
)
```

### 📋 **Unified JSON Schema Generation**
```elixir
# Single function handles all schema types
json_schema = Sinter.JsonSchema.generate(schema)

# Provider-specific optimizations
openai_schema = Sinter.JsonSchema.generate(schema, 
  optimize_for_provider: :openai,
  flatten: true
)
```

### 🛠 **Convenience Helpers**
```elixir
# One-off type validation (replaces TypeAdapter)
{:ok, 42} = Sinter.validate_type(:integer, "42", coerce: true)

# Single field validation (replaces Wrapper)  
{:ok, "john@example.com"} = Sinter.validate_value(:email, :string, 
  "john@example.com", [format: ~r/@/])
```

## Architecture

Sinter's architecture follows the **distillation principle** - extracting the essential, powerful core from complex systems:

```
┌─────────────────────────────────────────────┐
│              Sinter Core Engine             │
├─────────────────────────────────────────────┤
│  Sinter.Schema.define/2 (The Single Source) │
├─────────────────────────────────────────────┤
│     Sinter.Validator.validate/3             │
├─────────────────────────────────────────────┤
│   Sinter.JsonSchema.generate/2              │
└─────────────────────────────────────────────┘
           ▲                    ▲
           │                    │
    ┌──────────────┐    ┌──────────────┐
    │ Compile-time │    │   Runtime    │
    │   use_schema │    │    Helpers   │
    │    macro     │    │validate_type │
    └──────────────┘    │validate_value│
                        └──────────────┘
```

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

## Migration from Elixact

Sinter provides a clean migration path from Elixact's complex APIs:

| Elixact (Before) | Sinter (After) |
|------------------|----------------|
| `Elixact.Runtime.create_schema` | `Sinter.Schema.define` |
| `EnhancedValidator.validate` | `Sinter.Validator.validate` |  
| `TypeAdapter.validate` | `Sinter.validate_type` |
| `Wrapper.wrap_and_validate` | `Sinter.validate_value` |
| Multiple JSON Schema modules | `Sinter.JsonSchema.generate` |

See the [Migration Guide](docs/migration.md) for detailed migration instructions.

## Key Design Decisions

### **Validation ≠ Transformation**
Sinter validates data structure and constraints. Data transformation is your application's responsibility, keeping your program logic explicit and optimizable.

### **Runtime-First Design**  
While compile-time macros are supported, the core engine is built for runtime schema creation - perfect for dynamic frameworks.

### **"Gift" Libraries Integration**
Sinter leverages proven libraries:
- **simdjsone** - Ultra-fast JSON parsing (2.5x faster than jiffy)
- **ExJsonSchema** - Robust JSON Schema validation
- **Estructura** - Advanced nested structure patterns (if needed)

## Documentation

- [Getting Started Guide](docs/getting_started.md)
- [API Reference](https://hexdocs.pm/sinter)
- [DSPy Integration Guide](docs/dspy_integration.md)
- [Performance Guide](docs/performance.md)
- [Migration from Elixact](docs/migration.md)

## Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for details.

## License

Copyright (c) 2024

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at [http://www.apache.org/licenses/LICENSE-2.0](http://www.apache.org/licenses/LICENSE-2.0)

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Acknowledgments

Sinter is the distilled essence of [Elixact](https://github.com/your-org/elixact), refactored specifically for dynamic framework needs. Special thanks to the Elixact contributors and the broader Elixir validation ecosystem.

---

*"In the furnace of simplicity, complexity becomes strength."*
