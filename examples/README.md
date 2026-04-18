# Sinter Examples

This directory contains comprehensive examples demonstrating all functionality of the Sinter validation library. Each example file is executable and covers specific aspects of Sinter's capabilities.

## 🚀 Quick Start

All examples are executable Elixir scripts. To run any example:

```bash
# From the project root
cd examples
elixir basic_usage.exs
```

### Run All Examples at Once

For a comprehensive test of all functionality:

```bash
# From the project root (recommended)
examples/run_all.sh

# Or from the examples directory
cd examples
./run_all.sh
```

`run_all.sh` resolves its own directory, so it can be run from the project root or inside `examples/`.

This will execute all examples in sequence and provide a summary report with:
- ✅ Success/failure status for each example
- ⏱️ Execution timing for performance analysis  
- 📊 Comprehensive summary statistics
- 🔗 Next steps and troubleshooting guidance

## 📁 Example Files

### 1. `readme_comprehensive.exs` 
**Complete README Coverage**

This is the master example file that demonstrates **every single code example** mentioned in the main README. It covers:

- ✅ All unified schema definition patterns (runtime & compile-time)
- ✅ Complete validation pipeline examples
- ✅ Dynamic schema creation for DSPy integration
- ✅ JSON Schema generation with provider optimizations
- ✅ All convenience helper functions
- ✅ Performance benchmarking and metadata inspection

**Run this first** to see all README examples in action:

```bash
elixir readme_comprehensive.exs
```

### 2. `basic_usage.exs`
**Core Functionality Demo**

Demonstrates fundamental Sinter operations with practical, real-world examples:

- Simple schema creation and validation
- Type coercion and constraint validation
- Error handling patterns
- JSON Schema generation
- Common use cases (API validation, configuration validation)

### 3. `dspy_integration.exs`
**DSPy Framework Integration**

Shows how to use Sinter with DSPy-style dynamic programming patterns:

- Program signature creation
- LLM output validation with enhanced error context
- Schema inference from training examples (MIPRO-style)
- Schema optimization based on failure patterns
- Complex program composition (RAG pipelines)
- Provider-specific LLM optimizations

### 4. `advanced_validation.exs`
**Advanced Patterns & Edge Cases**

Covers sophisticated validation scenarios:

- Complex nested type definitions
- Custom business rule validation with post-validation hooks
- Batch and multi-record validation
- Performance optimization patterns
- Detailed error handling and debugging
- Schema composition and inheritance patterns

### 5. `json_schema_generation.exs`
**Comprehensive JSON Schema Examples**

Focuses specifically on JSON Schema generation capabilities:

- Provider-specific optimizations (OpenAI, Anthropic, Generic)
- Complex type mappings (unions, arrays, nested objects)
- Constraint translation to JSON Schema
- Real-world API schema examples
- Schema validation and compatibility checking
- Performance benchmarking

### 6. `discriminated_union_json_schema.exs`
**Focused Discriminated Union JSON Schema Coverage**

Shows the `0.3.0` discriminated-union JSON Schema behavior in a single script:

- Runtime validation for discriminated unions with aliases and nested strict objects
- Generated `oneOf` branches preserving descriptions, examples, defaults, and constraints
- Discriminator mappings resolving to concrete `$defs` / `definitions` targets
- Validation of data against the generated schema with `JSV`
- Provider-optimized output for OpenAI

### 7. `run_all.sh`
**Shell Runner (Recommended)**

Runs the full example suite from any working directory:

```bash
examples/run_all.sh
```

### 8. `run_all.exs`
**Complete Test Suite (Elixir)**

Executes all examples in sequence with detailed reporting:

- Runs all examples in recommended order
- Provides success/failure status for each
- Shows execution times and performance metrics
- Generates comprehensive summary report
- Perfect for testing after changes or setup

## 🎯 Feature Coverage Map

| Feature | README Example | Basic | DSPy | Advanced | JSON Schema |
|---------|---------------|-------|------|----------|-------------|
| **Core Schema Definition** | ✅ | ✅ | ✅ | ✅ | ✅ |
| Runtime `Schema.define/2` | ✅ | ✅ | ✅ | ✅ | ✅ |
| Compile-time `use_schema` macro | ✅ | - | - | - | - |
| **Validation Pipeline** | ✅ | ✅ | ✅ | ✅ | - |
| Basic validation | ✅ | ✅ | ✅ | ✅ | - |
| Type coercion | ✅ | ✅ | - | ✅ | - |
| Error handling | ✅ | ✅ | ✅ | ✅ | - |
| **Convenience Helpers** | ✅ | ✅ | - | ✅ | - |
| `validate_type/3` | ✅ | ✅ | - | ✅ | - |
| `validate_value/4` | ✅ | ✅ | - | ✅ | - |
| `validate_many/2` | ✅ | - | - | ✅ | - |
| `validator_for/2` | ✅ | - | - | ✅ | - |
| **Dynamic Schema Creation** | ✅ | - | ✅ | - | - |
| `infer_schema/2` | ✅ | - | ✅ | - | - |
| `merge_schemas/2` | ✅ | - | ✅ | ✅ | - |
| **DSPy Integration** | ✅ | - | ✅ | - | - |
| `DSPEx.create_signature/3` | ✅ | - | ✅ | - | - |
| `DSPEx.validate_llm_output/4` | ✅ | - | ✅ | - | - |
| `DSPEx.optimize_schema_from_failures/3` | - | - | ✅ | - | - |
| **JSON Schema Generation** | ✅ | ✅ | ✅ | - | ✅ |
| `JsonSchema.generate/2` | ✅ | ✅ | ✅ | - | ✅ |
| `JsonSchema.for_provider/3` | ✅ | ✅ | ✅ | - | ✅ |
| Provider optimizations | ✅ | ✅ | ✅ | - | ✅ |
| Discriminated unions and mappings | ✅ | - | - | - | ✅ |
| **Advanced Features** | - | - | - | ✅ | - |
| Post-validation hooks | ✅ | - | - | ✅ | - |
| Batch validation | - | - | - | ✅ | - |
| Complex nested types | - | - | - | ✅ | ✅ |
| Union types | - | - | - | ✅ | ✅ |
| Performance patterns | ✅ | - | - | ✅ | ✅ |

## 🧪 Running Specific Examples

### Run All Examples
```bash
# Execute all examples in sequence
for file in *.exs; do
  echo "=== Running $file ==="
  elixir "$file"
  echo ""
done
```

### Focus on Specific Areas

**New to Sinter? Start here:**
```bash
elixir basic_usage.exs
```

**Want to verify README examples work?**
```bash
elixir readme_comprehensive.exs
```

**Using Sinter with DSPy?**
```bash
elixir dspy_integration.exs
```

**Need advanced validation patterns?**
```bash
elixir advanced_validation.exs
```

**Working with JSON Schema generation?**
```bash
elixir json_schema_generation.exs
```

**Working with discriminated unions or branch fidelity?**
```bash
elixir discriminated_union_json_schema.exs
```

## 🔧 Customizing Examples

All examples are designed to be easily modified. Common patterns:

### Adding Your Own Schema
```elixir
# Add this to any example file
my_schema = Sinter.Schema.define([
  {:my_field, :string, [required: true]},
  # ... more fields
])

{:ok, result} = Sinter.Validator.validate(my_schema, %{my_field: "test"})
IO.puts("My validation result: #{inspect(result)}")
```

### Testing Different Constraints
```elixir
# Modify constraint examples
test_constraints = [
  {:score, :integer, [required: true, gteq: 0, lteq: 100]},
  {:email, :string, [required: true, format: ~r/YOUR_PATTERN/]}
]
```

### Performance Testing
```elixir
# Add performance tests to any example
start_time = System.monotonic_time(:microsecond)
# ... your operations ...
end_time = System.monotonic_time(:microsecond)
IO.puts("Operation took: #{end_time - start_time}μs")
```

## 🚨 Troubleshooting

### Missing Dependencies
If you see module loading errors:
```bash
# Make sure you're in the project root and deps are installed
mix deps.get
cd examples
elixir your_example.exs
```

### Path Issues
Examples use `Code.append_path("../_build/dev/lib/sinter/ebin")` to load compiled Sinter modules. If this fails:
```bash
# Compile the project first, then run from examples directory
cd examples
mix compile
elixir your_example.exs
```

### Module Not Found
If you get `** (UndefinedFunctionError)`:
```bash
# Compile the project first
mix compile
cd examples
elixir your_example.exs
```

## 📚 Learning Path

**Recommended order for learning Sinter:**

1. **`basic_usage.exs`** - Get familiar with core concepts
2. **`readme_comprehensive.exs`** - See all documented features working
3. **`json_schema_generation.exs`** - Understand JSON Schema integration
4. **`advanced_validation.exs`** - Learn sophisticated patterns
5. **`dspy_integration.exs`** - Explore dynamic programming integration

## 🤝 Contributing Examples

Found a use case not covered? Add an example!

1. Create a new `.exs` file following the existing pattern
2. Use the same header format with `#!/usr/bin/env elixir`
3. Add `Code.append_path("lib")` for module loading
4. Structure with clear sections using comments
5. Include both success and error cases
6. Add performance timing where relevant
7. Update this README with your new example

## 💡 Tips for Best Results

- **Run examples in order** - later examples build on concepts from earlier ones
- **Modify and experiment** - all examples are designed to be tweaked
- **Check the output** - examples include detailed logging to show what's happening
- **Time operations** - several examples include performance measurements
- **Compare approaches** - see how different patterns solve similar problems

---

*These examples cover 100% of the functionality described in the main README plus additional advanced patterns. They serve as both learning tools and integration tests for the library.* 
