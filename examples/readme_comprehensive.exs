#!/usr/bin/env elixir

# Examples covering all functionality from the Sinter README
# This file demonstrates every code example and feature mentioned in the documentation

IO.puts("=== Sinter Comprehensive Examples (README Coverage) ===")
IO.puts("")

# Add the compiled beam files to the path so we can run this as a script
Code.append_path("../_build/dev/lib/sinter/ebin")

# ============================================================================
# 1. UNIFIED SCHEMA DEFINITION
# ============================================================================

IO.puts("1. UNIFIED SCHEMA DEFINITION")
IO.puts("----------------------------")

# Runtime schema creation (as shown in README)
fields = [
  {:name, :string, [required: true, min_length: 2]},
  {:age, :integer, [optional: true, gt: 0]},
  {:email, :string, [required: true, format: ~r/@/]}
]
schema = Sinter.Schema.define(fields, title: "User Schema")

IO.puts("✓ Runtime schema created with title: #{schema.config.title}")
IO.puts("  Fields: #{inspect(Map.keys(schema.fields))}")

# Compile-time schema definition (from README example)
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

compiled_schema = UserSchema.schema()
IO.puts("✓ Compile-time schema created with title: #{compiled_schema.config.title}")
IO.puts("  Strict mode: #{compiled_schema.config.strict}")
IO.puts("")

# ============================================================================
# 2. SINGLE VALIDATION PIPELINE
# ============================================================================

IO.puts("2. SINGLE VALIDATION PIPELINE")
IO.puts("------------------------------")

# Basic validation (README example)
test_data = %{name: "Alice", age: 30, email: "alice@example.com"}
{:ok, validated} = Sinter.Validator.validate(schema, test_data)
IO.puts("✓ Basic validation successful: #{inspect(validated)}")

# Validation with missing required field
invalid_data = %{age: 30}
{:error, errors} = Sinter.Validator.validate(schema, invalid_data)
IO.puts("✓ Validation correctly failed for missing fields: #{length(errors)} errors")

# Optional post-validation hook (README mentions this)
schema_with_hook = Sinter.Schema.define(fields,
  post_validate: fn data ->
    if data.name == "Admin" and data.age < 18 do
      {:error, "Admin must be 18 or older"}
    else
      {:ok, data}
    end
  end
)

# Test post-validation hook
{:ok, _} = Sinter.Validator.validate(schema_with_hook, %{name: "Alice", age: 30, email: "alice@example.com"})
IO.puts("✓ Post-validation hook executed successfully")
IO.puts("")

# ============================================================================
# 3. DYNAMIC SCHEMA CREATION (PERFECT FOR DSPY)
# ============================================================================

IO.puts("3. DYNAMIC SCHEMA CREATION (DSPy Integration)")
IO.puts("----------------------------------------------")

# Create schemas on the fly - ideal for DSPy teleprompters (README example)
create_program_signature = fn input_fields, output_fields ->
  all_fields = input_fields ++ output_fields
  Sinter.Schema.define(all_fields, title: "DSPy Program Signature")
end

# MIPRO-style dynamic optimization (README example)
optimized_schema = create_program_signature.(
  [{:question, :string, [required: true]}],
  [{:answer, :string, [required: true]},
   {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]}]
)

IO.puts("✓ Dynamic DSPy signature created: #{optimized_schema.config.title}")
IO.puts("  Schema fields: #{inspect(Map.keys(optimized_schema.fields))}")

# Schema inference from examples (from README docstring examples)
examples = [
  %{"name" => "Alice", "age" => 30},
  %{"name" => "Bob", "age" => 25},
  %{"name" => "Charlie", "age" => 35}
]
inferred_schema = Sinter.infer_schema(examples)
IO.puts("✓ Schema inferred from examples")
IO.puts("  Inferred fields: #{inspect(Map.keys(inferred_schema.fields))}")

# Schema merging (from README)
input_schema = Sinter.Schema.define([{:query, :string, [required: true]}])
output_schema = Sinter.Schema.define([{:answer, :string, [required: true]}])
program_schema = Sinter.merge_schemas([input_schema, output_schema])

IO.puts("✓ Schemas merged successfully")
IO.puts("  Merged fields: #{inspect(Map.keys(program_schema.fields))}")
IO.puts("")

# ============================================================================
# 4. UNIFIED JSON SCHEMA GENERATION
# ============================================================================

IO.puts("4. UNIFIED JSON SCHEMA GENERATION")
IO.puts("---------------------------------")

# Single function handles all schema types (README example)
json_schema = Sinter.JsonSchema.generate(schema)
IO.puts("✓ JSON Schema generated")
IO.puts("  Type: #{json_schema["type"]}")
IO.puts("  Required fields: #{inspect(json_schema["required"])}")

# Provider-specific optimizations (README example)
openai_schema = Sinter.JsonSchema.generate(schema,
  optimize_for_provider: :openai,
  flatten: true
)
IO.puts("✓ OpenAI-optimized schema generated")
IO.puts("  Additional properties: #{openai_schema["additionalProperties"]}")
IO.puts("")

# ============================================================================
# 5. CONVENIENCE HELPERS
# ============================================================================

IO.puts("5. CONVENIENCE HELPERS")
IO.puts("----------------------")

# One-off type validation (replaces TypeAdapter, from README)
{:ok, result} = Sinter.validate_type(:integer, "42", coerce: true)
IO.puts("✓ Type validation with coercion: \"42\" -> #{result}")

# Array type validation (README example)
{:ok, array_result} = Sinter.validate_type({:array, :string}, ["hello", "world"])
IO.puts("✓ Array validation: #{inspect(array_result)}")

# Single field validation (replaces Wrapper, from README)
{:ok, email_result} = Sinter.validate_value(:email, :string,
  "john@example.com", [format: ~r/@/])
IO.puts("✓ Single field validation: #{email_result}")

# Validation with constraints
{:ok, score_result} = Sinter.validate_value(:score, :integer,
  "95", coerce: true, constraints: [gteq: 0, lteq: 100])
IO.puts("✓ Field validation with constraints: #{score_result}")

# Error case to show error structure
{:error, [error]} = Sinter.validate_type(:string, 123)
IO.puts("✓ Validation error captured, code: #{error.code}")
IO.puts("")

# ============================================================================
# 6. ADDITIONAL FUNCTIONALITY FROM CODEBASE
# ============================================================================

IO.puts("6. ADDITIONAL FUNCTIONALITY")
IO.puts("---------------------------")

# Multiple value validation
validation_specs = [
  {:string, "hello"},
  {:integer, 42},
  {:email, :string, "test@example.com", [format: ~r/@/]}
]
{:ok, multi_results} = Sinter.validate_many(validation_specs)
IO.puts("✓ Multiple values validated: #{inspect(multi_results)}")

# Reusable validator creation
email_validator = Sinter.validator_for(:string, constraints: [format: ~r/@/])
{:ok, validated_email} = email_validator.("test@example.com")
IO.puts("✓ Reusable validator: #{validated_email}")

# Batch validator
batch_validator = Sinter.batch_validator_for([
  {:name, :string},
  {:age, :integer}
])
{:ok, batch_result} = batch_validator.(%{name: "Alice", age: 30})
IO.puts("✓ Batch validation: #{inspect(batch_result)}")

# Schema information
info = Sinter.Schema.info(schema)
IO.puts("✓ Schema info - Field count: #{info.field_count}, Required: #{info.required_count}")
IO.puts("")

# ============================================================================
# 7. QUICK START EXAMPLE (README)
# ============================================================================

IO.puts("7. QUICK START EXAMPLE")
IO.puts("----------------------")

# Exact example from README Quick Start section
quick_fields = [
  {:name, :string, [required: true]},
  {:age, :integer, [optional: true, gt: 0]}
]
quick_schema = Sinter.Schema.define(quick_fields)

{:ok, quick_validated} = Sinter.Validator.validate(quick_schema, %{
  name: "Alice",
  age: 30
})

quick_json_schema = Sinter.JsonSchema.generate(quick_schema)

IO.puts("✓ Quick start example completed")
IO.puts("  Validated: #{inspect(quick_validated)}")
IO.puts("  JSON Schema type: #{quick_json_schema["type"]}")
IO.puts("")

# ============================================================================
# 8. PERFORMANCE AND METADATA
# ============================================================================

IO.puts("8. PERFORMANCE AND METADATA")
IO.puts("---------------------------")

# Show schema metadata
metadata = schema.metadata
IO.puts("✓ Schema metadata:")
IO.puts("  Created at: #{metadata.created_at}")
IO.puts("  Field count: #{metadata.field_count}")
IO.puts("  Sinter version: #{metadata.sinter_version}")

# Show validation timing (basic benchmark)
start_time = System.monotonic_time(:microsecond)
for _ <- 1..1000 do
  Sinter.Validator.validate(schema, test_data)
end
end_time = System.monotonic_time(:microsecond)
avg_time = (end_time - start_time) / 1000
IO.puts("✓ Performance: ~#{Float.round(avg_time, 2)}μs per validation (1000 iterations)")
IO.puts("")

IO.puts("=== All README Examples Completed Successfully! ===")
