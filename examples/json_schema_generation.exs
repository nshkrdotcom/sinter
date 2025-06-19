#!/usr/bin/env elixir

# JSON Schema Generation Examples for Sinter
# Demonstrates comprehensive JSON Schema generation for different providers and use cases

IO.puts("=== Sinter JSON Schema Generation Examples ===")
IO.puts("")

# Add the compiled beam files to the path
Code.append_path("../_build/dev/lib/sinter/ebin")
Code.append_path("../_build/dev/lib/jason/ebin")

# ============================================================================
# 1. BASIC JSON SCHEMA GENERATION
# ============================================================================

IO.puts("1. Basic JSON Schema Generation")
IO.puts("-------------------------------")

# Simple schema for basic JSON Schema generation
user_schema = Sinter.Schema.define([
  {:name, :string, [required: true, min_length: 2, max_length: 50]},
  {:age, :integer, [required: true, gteq: 0, lteq: 120]},
  {:email, :string, [required: true, format: ~r/^[^\s]+@[^\s]+\.[^\s]+$/]},
  {:active, :boolean, [optional: true, default: true]},
  {:tags, {:array, :string}, [optional: true, min_length: 0, max_length: 10]}
], title: "User Schema", description: "Schema for user data validation")

# Generate standard JSON Schema
json_schema = Sinter.JsonSchema.generate(user_schema)

IO.puts("✓ Generated standard JSON Schema:")
IO.puts("  Schema: #{json_schema["$schema"]}")
IO.puts("  Type: #{json_schema["type"]}")
IO.puts("  Title: #{json_schema["title"]}")
IO.puts("  Required fields: #{inspect(json_schema["required"])}")
IO.puts("  Property count: #{map_size(json_schema["properties"])}")

# Pretty print the full schema
IO.puts("\n📋 Complete JSON Schema:")
json_pretty = Jason.encode!(json_schema, pretty: true)
IO.puts(json_pretty)
IO.puts("")

# ============================================================================
# 2. PROVIDER-SPECIFIC OPTIMIZATIONS
# ============================================================================

IO.puts("2. Provider-Specific Optimizations")
IO.puts("----------------------------------")

# OpenAI optimization (for function calling)
openai_schema = Sinter.JsonSchema.for_provider(user_schema, :openai)
IO.puts("✓ OpenAI-optimized schema:")
IO.puts("  Additional properties: #{openai_schema["additionalProperties"]}")
IO.puts("  Schema version: #{openai_schema["$schema"] || "Draft 4 (implied)"}")

# Anthropic optimization (for tool use)
anthropic_schema = Sinter.JsonSchema.for_provider(user_schema, :anthropic)
IO.puts("✓ Anthropic-optimized schema:")
IO.puts("  Type: #{anthropic_schema["type"]}")
IO.puts("  Properties preserved: #{map_size(anthropic_schema["properties"])}")

# Generic schema (standard JSON Schema)
generic_schema = Sinter.JsonSchema.for_provider(user_schema, :generic)
IO.puts("✓ Generic schema:")
IO.puts("  Schema version: #{generic_schema["$schema"]}")
IO.puts("  Full compliance: true")
IO.puts("")

# ============================================================================
# 3. COMPLEX TYPE MAPPINGS
# ============================================================================

IO.puts("3. Complex Type Mappings")
IO.puts("-----------------------")

# Schema with complex types
complex_schema = Sinter.Schema.define([
  {:id, {:union, [:string, :integer]}, [required: true]},
  {:metadata, :map, [optional: true]},
  {:coordinates, {:array, :float}, [required: true, min_length: 2, max_length: 3]},
  {:nested_data, :map, [optional: true]},
  {:any_value, :any, [optional: true]},
  {:category, :string, [required: true, choices: ["A", "B", "C"]]}
], title: "Complex Types Schema")

complex_json = Sinter.JsonSchema.generate(complex_schema)

IO.puts("✓ Complex types mapped to JSON Schema:")
Enum.each(complex_json["properties"], fn {field, props} ->
  type_info = case props do
    %{"type" => type} -> type
    %{"oneOf" => _} -> "union"
    %{"anyOf" => _} -> "anyOf"
    _ -> "complex"
  end
  IO.puts("  #{field}: #{type_info}")
end)

# Show union type mapping
id_property = complex_json["properties"]["id"]
IO.puts("\n📋 Union type (id field) mapping:")
IO.puts(Jason.encode!(id_property, pretty: true))
IO.puts("")

# ============================================================================
# 4. CONSTRAINT MAPPING
# ============================================================================

IO.puts("4. Constraint Mapping")
IO.puts("--------------------")

# Schema focused on constraints
constraint_schema = Sinter.Schema.define([
  {:username, :string, [required: true, min_length: 3, max_length: 20,
                       format: ~r/^[a-zA-Z0-9_]+$/]},
  {:score, :integer, [required: true, gteq: 0, lteq: 100]},
  {:rating, :float, [required: true, gt: 0.0, lt: 5.0]},
  {:description, :string, [optional: true, max_length: 500]},
  {:items, {:array, :string}, [required: true, min_length: 1, max_length: 20]}
])

constraint_json = Sinter.JsonSchema.generate(constraint_schema)

IO.puts("✓ Constraints mapped to JSON Schema:")

# Show specific constraint mappings
username_props = constraint_json["properties"]["username"]
IO.puts("  Username constraints:")
IO.puts("    minLength: #{username_props["minLength"]}")
IO.puts("    maxLength: #{username_props["maxLength"]}")
IO.puts("    pattern: #{username_props["pattern"]}")

score_props = constraint_json["properties"]["score"]
IO.puts("  Score constraints:")
IO.puts("    minimum: #{score_props["minimum"]}")
IO.puts("    maximum: #{score_props["maximum"]}")

rating_props = constraint_json["properties"]["rating"]
IO.puts("  Rating constraints:")
IO.puts("    exclusiveMinimum: #{rating_props["exclusiveMinimum"]}")
IO.puts("    exclusiveMaximum: #{rating_props["exclusiveMaximum"]}")

items_props = constraint_json["properties"]["items"]
IO.puts("  Items array constraints:")
IO.puts("    minItems: #{items_props["minItems"]}")
IO.puts("    maxItems: #{items_props["maxItems"]}")
IO.puts("")

# ============================================================================
# 5. REAL-WORLD API SCHEMAS
# ============================================================================

IO.puts("5. Real-World API Schemas")
IO.puts("------------------------")

# E-commerce API schema
product_api_schema = Sinter.Schema.define([
  {:sku, :string, [required: true, format: ~r/^[A-Z0-9-]+$/]},
  {:name, :string, [required: true, min_length: 1, max_length: 200]},
  {:description, :string, [optional: true, max_length: 2000]},
  {:price, :float, [required: true, gt: 0.0]},
  {:currency, :string, [required: true, choices: ["USD", "EUR", "GBP"]]},
  {:categories, {:array, :string}, [required: true, min_length: 1]},
  {:attributes, :map, [optional: true]},
  {:in_stock, :boolean, [required: true]},
  {:stock_quantity, :integer, [optional: true, gteq: 0]}
], title: "Product API", description: "Schema for e-commerce product API")

# Generate for different providers
product_openai = Sinter.JsonSchema.for_provider(product_api_schema, :openai)
_product_generic = Sinter.JsonSchema.for_provider(product_api_schema, :generic)

IO.puts("✓ E-commerce API schema generated")
IO.puts("  Fields: #{map_size(product_openai["properties"])}")
IO.puts("  Required: #{length(product_openai["required"])}")

# User registration API schema
registration_schema = Sinter.Schema.define([
  {:email, :string, [required: true, format: ~r/^[^\s]+@[^\s]+\.[^\s]+$/]},
  {:password, :string, [required: true, min_length: 8, max_length: 128]},
  {:confirm_password, :string, [required: true]},
  {:first_name, :string, [required: true, min_length: 1, max_length: 50]},
  {:last_name, :string, [required: true, min_length: 1, max_length: 50]},
  {:phone, :string, [optional: true, format: ~r/^\+?[\d\s\-\(\)]+$/]},
  {:terms_accepted, :boolean, [required: true]},
  {:marketing_opt_in, :boolean, [optional: true, default: false]}
], title: "User Registration", strict: true)

registration_json = Sinter.JsonSchema.generate(registration_schema)
IO.puts("✓ User registration schema generated")
IO.puts("  Strict mode: #{not registration_json["additionalProperties"]}")
IO.puts("")

# ============================================================================
# 6. NESTED AND HIERARCHICAL SCHEMAS
# ============================================================================

IO.puts("6. Nested and Hierarchical Schemas")
IO.puts("----------------------------------")

# Order with nested items schema
order_schema = Sinter.Schema.define([
  {:order_id, :string, [required: true]},
  {:customer, :map, [required: true]},  # Will be nested
  {:items, {:array, :map}, [required: true, min_length: 1]},  # Array of objects
  {:shipping_address, :map, [required: true]},
  {:billing_address, :map, [optional: true]},
  {:payment_method, :string, [required: true, choices: ["credit_card", "paypal", "bank_transfer"]]},
  {:total_amount, :float, [required: true, gt: 0.0]},
  {:currency, :string, [required: true, choices: ["USD", "EUR", "GBP"]]},
  {:status, :string, [required: true, choices: ["pending", "confirmed", "shipped", "delivered", "cancelled"]]}
], title: "Order Schema", description: "Complete order with nested customer and items")

order_json = Sinter.JsonSchema.generate(order_schema)

IO.puts("✓ Hierarchical order schema generated")
IO.puts("  Top-level properties: #{map_size(order_json["properties"])}")

# Show nested structure
customer_def = order_json["properties"]["customer"]
items_def = order_json["properties"]["items"]
IO.puts("  Customer field type: #{customer_def["type"]}")
IO.puts("  Items field type: #{items_def["type"]}")
IO.puts("  Items array items: #{items_def["items"]["type"]}")
IO.puts("")

# ============================================================================
# 7. VALIDATION AND COMPATIBILITY
# ============================================================================

IO.puts("7. Schema Validation and Compatibility")
IO.puts("-------------------------------------")

# Validate generated schemas
schemas_to_validate = [
  {"User Schema", json_schema},
  {"Product API", product_openai},
  {"Registration", registration_json},
  {"Order Schema", order_json}
]

Enum.each(schemas_to_validate, fn {name, schema} ->
  case Sinter.JsonSchema.validate_schema(schema) do
    :ok ->
      IO.puts("✓ #{name}: Valid JSON Schema")
    {:error, issues} ->
      IO.puts("✗ #{name}: Issues found:")
      Enum.each(issues, fn issue ->
        IO.puts("    - #{issue}")
      end)
  end
end)
IO.puts("")

# ============================================================================
# 8. GENERATION OPTIONS AND CUSTOMIZATION
# ============================================================================

IO.puts("8. Generation Options and Customization")
IO.puts("--------------------------------------")

# Test different generation options
base_schema = Sinter.Schema.define([
  {:name, :string, [required: true, description: "User's full name"]},
  {:age, :integer, [optional: true, description: "User's age in years"]},
  {:email, :string, [required: true, description: "User's email address"]}
], title: "Customization Test Schema", description: "Testing various generation options")

# With descriptions
with_descriptions = Sinter.JsonSchema.generate(base_schema, include_descriptions: true)
IO.puts("✓ Schema with descriptions:")
IO.puts("  Name description: #{with_descriptions["properties"]["name"]["description"]}")

# Without descriptions
without_descriptions = Sinter.JsonSchema.generate(base_schema, include_descriptions: false)
has_description = Map.has_key?(without_descriptions["properties"]["name"], "description")
IO.puts("✓ Schema without descriptions:")
IO.puts("  Name has description: #{has_description}")

# Flattened schema
_flattened = Sinter.JsonSchema.generate(base_schema, flatten: true)
IO.puts("✓ Flattened schema generated")

# Strict override
strict_override = Sinter.JsonSchema.generate(base_schema, strict: true)
IO.puts("✓ Strict mode override:")
IO.puts("  Additional properties: #{strict_override["additionalProperties"]}")
IO.puts("")

# ============================================================================
# 9. PERFORMANCE COMPARISON
# ============================================================================

IO.puts("9. Performance Comparison")
IO.puts("------------------------")

# Test generation performance
large_schema = Sinter.Schema.define(
  Enum.map(1..50, fn i ->
    {String.to_atom("field_#{i}"), :string, [required: rem(i, 3) == 0, min_length: 1]}
  end),
  title: "Large Schema Test"
)

# Time standard generation
start_time = System.monotonic_time(:microsecond)
for _ <- 1..100 do
  Sinter.JsonSchema.generate(large_schema)
end
standard_time = System.monotonic_time(:microsecond) - start_time

# Time OpenAI generation
start_time = System.monotonic_time(:microsecond)
for _ <- 1..100 do
  Sinter.JsonSchema.for_provider(large_schema, :openai)
end
openai_time = System.monotonic_time(:microsecond) - start_time

IO.puts("✓ Performance test (100 iterations, #{map_size(large_schema.fields)} fields):")
IO.puts("  Standard generation: #{Float.round(standard_time / 100, 2)}μs avg")
IO.puts("  OpenAI generation: #{Float.round(openai_time / 100, 2)}μs avg")
IO.puts("  Overhead: #{Float.round((openai_time - standard_time) / standard_time * 100, 1)}%")
IO.puts("")

IO.puts("=== JSON Schema Generation Examples Complete ===")
