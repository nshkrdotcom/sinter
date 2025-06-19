#!/usr/bin/env elixir

# Basic Usage Examples for Sinter
# Demonstrates the core functionality with simple, clear examples

IO.puts("=== Sinter Basic Usage Examples ===")
IO.puts("")

# Add the compiled beam files to the path
Code.append_path("../_build/dev/lib/sinter/ebin")

# ============================================================================
# 1. SCHEMA DEFINITION
# ============================================================================

IO.puts("1. Creating Schemas")
IO.puts("------------------")

# Simple schema
user_schema = Sinter.Schema.define([
  {:name, :string, [required: true]},
  {:age, :integer, [optional: true]},
  {:active, :boolean, [optional: true, default: true]}
])

IO.puts("✓ Created user schema")

# Schema with constraints
product_schema = Sinter.Schema.define([
  {:title, :string, [required: true, min_length: 3, max_length: 100]},
  {:price, :float, [required: true, gt: 0.0]},
  {:tags, {:array, :string}, [optional: true]},
  {:category, :string, [required: true, choices: ["electronics", "books", "clothing"]]}
], title: "Product Schema", strict: true)

IO.puts("✓ Created product schema with constraints")
IO.puts("")

# ============================================================================
# 2. VALIDATION
# ============================================================================

IO.puts("2. Data Validation")
IO.puts("-----------------")

# Valid user data
valid_user = %{name: "John Doe", age: 25}
case Sinter.Validator.validate(user_schema, valid_user) do
  {:ok, validated} -> IO.puts("✓ Valid user: #{inspect(validated)}")
  {:error, errors} -> IO.puts("✗ Validation failed: #{inspect(errors)}")
end

# Invalid user data
invalid_user = %{age: "not a number"}
case Sinter.Validator.validate(user_schema, invalid_user) do
  {:ok, validated} -> IO.puts("✓ Unexpected success: #{inspect(validated)}")
  {:error, errors} ->
    IO.puts("✓ Correctly caught validation errors:")
    Enum.each(errors, fn error ->
      IO.puts("  - Field '#{Enum.join(error.path, ".")}': #{error.message}")
    end)
end

# Valid product with coercion
product_data = %{
  title: "Great Book",
  price: "29.99",  # String that can be coerced to float
  category: "books"
}

case Sinter.Validator.validate(product_schema, product_data, coerce: true) do
  {:ok, validated} ->
    IO.puts("✓ Product validated with coercion: #{inspect(validated)}")
  {:error, errors} ->
    IO.puts("✗ Product validation failed: #{inspect(errors)}")
end
IO.puts("")

# ============================================================================
# 3. TYPE VALIDATION HELPERS
# ============================================================================

IO.puts("3. Type Validation Helpers")
IO.puts("--------------------------")

# Simple type validation
{:ok, number} = Sinter.validate_type(:integer, "42", coerce: true)
IO.puts("✓ Coerced string to integer: #{number}")

# Array validation
{:ok, tags} = Sinter.validate_type({:array, :string}, ["tag1", "tag2", "tag3"])
IO.puts("✓ Validated string array: #{inspect(tags)}")

# Email validation with regex
{:ok, email} = Sinter.validate_value(:email, :string, "user@example.com",
  constraints: [format: ~r/^[^\s]+@[^\s]+\.[^\s]+$/])
IO.puts("✓ Validated email format: #{email}")

# Error handling
case Sinter.validate_type(:integer, "not_a_number", coerce: true) do
  {:ok, result} -> IO.puts("Unexpected success: #{result}")
  {:error, [error]} -> IO.puts("✓ Caught type error: #{error.code}")
end
IO.puts("")

# ============================================================================
# 4. JSON SCHEMA GENERATION
# ============================================================================

IO.puts("4. JSON Schema Generation")
IO.puts("------------------------")

# Generate standard JSON Schema
json_schema = Sinter.JsonSchema.generate(user_schema)
IO.puts("✓ Generated JSON Schema:")
IO.puts("  Type: #{json_schema["type"]}")
IO.puts("  Properties: #{map_size(json_schema["properties"])}")
IO.puts("  Required: #{inspect(json_schema["required"])}")

# Provider-specific schema
openai_schema = Sinter.JsonSchema.for_provider(product_schema, :openai)
IO.puts("✓ Generated OpenAI-optimized schema")
IO.puts("  Additional properties: #{openai_schema["additionalProperties"]}")
IO.puts("")

# ============================================================================
# 5. PRACTICAL EXAMPLES
# ============================================================================

IO.puts("5. Practical Examples")
IO.puts("--------------------")

# API request validation
api_request_schema = Sinter.Schema.define([
  {:endpoint, :string, [required: true]},
  {:method, :string, [required: true, choices: ["GET", "POST", "PUT", "DELETE"]]},
  {:headers, :map, [optional: true]},
  {:body, :any, [optional: true]}
])

api_request = %{
  endpoint: "/api/users",
  method: "POST",
  headers: %{"Content-Type" => "application/json"},
  body: %{name: "New User"}
}

{:ok, validated_request} = Sinter.Validator.validate(api_request_schema, api_request)
IO.puts("✓ API request validated: #{validated_request.method} #{validated_request.endpoint}")

# Configuration validation
config_schema = Sinter.Schema.define([
  {:database_url, :string, [required: true]},
  {:port, :integer, [required: true, gteq: 1, lteq: 65535]},
  {:debug, :boolean, [optional: true, default: false]},
  {:max_connections, :integer, [optional: true, default: 100, gt: 0]}
])

config = %{
  database_url: "postgres://localhost/mydb",
  port: 4000,
  max_connections: 50
}

{:ok, validated_config} = Sinter.Validator.validate(config_schema, config)
IO.puts("✓ Configuration validated")
IO.puts("  Port: #{validated_config.port}")
IO.puts("  Debug mode: #{validated_config[:debug] || "default (false)"}")
IO.puts("  Max connections: #{validated_config.max_connections}")
IO.puts("")

IO.puts("=== Basic Usage Examples Complete ===")
