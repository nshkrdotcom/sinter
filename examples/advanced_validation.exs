#!/usr/bin/env elixir

# Advanced Validation Examples for Sinter
# Demonstrates complex validation patterns, custom constraints, and edge cases

IO.puts("=== Sinter Advanced Validation Examples ===")
IO.puts("")

# Add the compiled beam files to the path
Code.append_path("../_build/dev/lib/sinter/ebin")

# ============================================================================
# 1. COMPLEX TYPE DEFINITIONS
# ============================================================================

IO.puts("1. Complex Type Definitions")
IO.puts("---------------------------")

# Nested object schema
_address_schema = Sinter.Schema.define([
  {:street, :string, [required: true, min_length: 5]},
  {:city, :string, [required: true, min_length: 2]},
  {:state, :string, [required: true, min_length: 2, max_length: 2]},
  {:zip_code, :string, [required: true, format: ~r/^\d{5}(-\d{4})?$/]}
])

user_with_address_schema = Sinter.Schema.define([
  {:name, :string, [required: true]},
  {:email, :string, [required: true, format: ~r/@/]},
  {:addresses, {:array, :map}, [optional: true]},
  {:primary_address, :map, [optional: true]},
  {:age, :integer, [required: true, gteq: 0, lteq: 120]},
  {:preferences, :map, [optional: true]}
])

IO.puts("✓ Created nested object schemas")

# Union types for flexible inputs
_flexible_id_schema = Sinter.Schema.define([
  {:id, {:union, [:string, :integer]}, [required: true]},
  {:metadata, :any, [optional: true]}
])

IO.puts("✓ Created union type schema")

# Array with constraints
_tags_schema = Sinter.Schema.define([
  {:tags, {:array, :string}, [required: true, min_length: 1, max_length: 10]},
  {:categories, {:array, :string}, [optional: true]}
])

IO.puts("✓ Created array constraint schema")
IO.puts("")

# ============================================================================
# 2. CUSTOM VALIDATION PATTERNS
# ============================================================================

IO.puts("2. Custom Validation Patterns")
IO.puts("-----------------------------")

# Post-validation for business rules
user_business_rules = fn validated_data ->
  cond do
    validated_data.age < 13 and Map.has_key?(validated_data, :email) ->
      {:error, "Users under 13 cannot have email addresses"}

    validated_data.age >= 65 and not Map.get(validated_data, :senior_discount, false) ->
      # Auto-apply senior discount
      {:ok, Map.put(validated_data, :senior_discount, true)}

    true ->
      {:ok, validated_data}
  end
end

business_schema = Sinter.Schema.define([
  {:name, :string, [required: true]},
  {:age, :integer, [required: true, gteq: 0]},
  {:email, :string, [optional: true, format: ~r/@/]},
  {:senior_discount, :boolean, [optional: true, default: false]}
], post_validate: user_business_rules)

# Test business rules
child_data = %{name: "Tommy", age: 10, email: "tommy@example.com"}
case Sinter.Validator.validate(business_schema, child_data) do
  {:ok, _} -> IO.puts("✗ Should have failed for child with email")
  {:error, [error]} -> IO.puts("✓ Business rule caught: #{error.message}")
end

senior_data = %{name: "Margaret", age: 70}
{:ok, validated_senior} = Sinter.Validator.validate(business_schema, senior_data)
IO.puts("✓ Senior discount auto-applied: #{validated_senior.senior_discount}")
IO.puts("")

# ============================================================================
# 3. BATCH AND MULTI-VALIDATION
# ============================================================================

IO.puts("3. Batch and Multi-Validation")
IO.puts("-----------------------------")

# Validate multiple records efficiently
user_records = [
  %{name: "Alice", age: 30, email: "alice@example.com"},
  %{name: "Bob", age: 25, email: "bob@example.com"},
  %{name: "Charlie", age: 35, email: "charlie@example.com"}
]

{:ok, validated_batch} = Sinter.Validator.validate_many(user_with_address_schema, user_records)
IO.puts("✓ Batch validated #{length(validated_batch)} records")

# Mixed validation with errors
mixed_records = [
  %{name: "Valid User", age: 30, email: "valid@example.com"},
  %{name: "Invalid", age: "not_a_number", email: "bad_email"},
  %{name: "Another Valid", age: 25, email: "another@example.com"}
]

case Sinter.Validator.validate_many(user_with_address_schema, mixed_records) do
  {:ok, _} -> IO.puts("✗ Should have failed")
  {:error, error_map} ->
    IO.puts("✓ Batch validation correctly identified errors at indices: #{inspect(Map.keys(error_map))}")
    Enum.each(error_map, fn {index, errors} ->
      IO.puts("  Index #{index}: #{length(errors)} errors")
    end)
end

# Multi-type validation
heterogeneous_data = [
  {:email, :string, "user@example.com", [format: ~r/@/]},
  {:age, :integer, "25", [gteq: 0]},  # Will be coerced
  {:active, :boolean, true},
  {:tags, {:array, :string}, ["admin", "premium"]}
]

{:ok, multi_results} = Sinter.validate_many(heterogeneous_data, coerce: true)
IO.puts("✓ Multi-type validation: #{inspect(multi_results)}")
IO.puts("")

# ============================================================================
# 4. PERFORMANCE PATTERNS
# ============================================================================

IO.puts("4. Performance Patterns")
IO.puts("----------------------")

# Reusable validators for hot paths
email_validator = Sinter.validator_for(:string, constraints: [format: ~r/@/])
phone_validator = Sinter.validator_for(:string, constraints: [format: ~r/^\d{3}-\d{3}-\d{4}$/])
age_validator = Sinter.validator_for(:integer, constraints: [gteq: 0, lteq: 120])

# Batch validator for common patterns
contact_validator = Sinter.batch_validator_for([
  {:name, :string},
  {:email, :string},
  {:phone, :string},
  {:age, :integer}
])

# Performance test
test_contact = %{
  name: "Performance Test",
  email: "test@example.com",
  phone: "555-123-4567",
  age: 30
}

# Time individual validators
start_time = System.monotonic_time(:microsecond)
for _ <- 1..1000 do
  email_validator.(test_contact.email)
  phone_validator.(test_contact.phone)
  age_validator.(test_contact.age)
end
individual_time = System.monotonic_time(:microsecond) - start_time

# Time batch validator
start_time = System.monotonic_time(:microsecond)
for _ <- 1..1000 do
  contact_validator.(test_contact)
end
batch_time = System.monotonic_time(:microsecond) - start_time

IO.puts("✓ Performance comparison (1000 iterations):")
IO.puts("  Individual validators: #{Float.round(individual_time / 1000, 2)}μs avg")
IO.puts("  Batch validator: #{Float.round(batch_time / 1000, 2)}μs avg")
IO.puts("")

# ============================================================================
# 5. ERROR HANDLING AND DEBUGGING
# ============================================================================

IO.puts("5. Error Handling and Debugging")
IO.puts("-------------------------------")

# Complex nested validation with detailed errors
complex_data = %{
  user: %{
    name: "",  # Too short
    age: -5,   # Invalid
    email: "not_an_email"  # Invalid format
  },
  orders: [
    %{id: "order1", amount: "not_a_number"},  # Invalid type
    %{id: 123, amount: 50.0},  # Valid
    %{amount: 25.0}  # Missing id
  ]
}

complex_schema = Sinter.Schema.define([
  {:user, :map, [required: true]},
  {:orders, {:array, :map}, [required: true]}
])

# This will pass the top-level validation but we can see the structure
{:ok, _validated_complex} = Sinter.Validator.validate(complex_schema, complex_data)
IO.puts("✓ Complex structure validated at top level")

# Detailed validation of nested structures
user_schema = Sinter.Schema.define([
  {:name, :string, [required: true, min_length: 1]},
  {:age, :integer, [required: true, gteq: 0]},
  {:email, :string, [required: true, format: ~r/@/]}
])

case Sinter.Validator.validate(user_schema, complex_data.user) do
  {:ok, _} -> IO.puts("✗ Should have failed")
  {:error, errors} ->
    IO.puts("✓ Detailed user validation errors:")
    Enum.each(errors, fn error ->
      IO.puts("  - #{Enum.join(error.path, ".")}: #{error.message} (#{error.code})")
    end)
end

# Custom error context for debugging
debug_validator = fn data, schema ->
  case Sinter.Validator.validate(schema, data) do
    {:ok, validated} ->
      {:ok, validated}
    {:error, errors} ->
      enhanced_errors = Enum.map(errors, fn error ->
        Map.put(error, :debug_context, %{
          input_data: data,
          timestamp: DateTime.utc_now(),
          validation_attempt: :custom_debug
        })
      end)
      {:error, enhanced_errors}
  end
end

{:error, debug_errors} = debug_validator.(complex_data.user, user_schema)
IO.puts("✓ Enhanced error with debug context")
first_error = List.first(debug_errors)
IO.puts("  Debug timestamp: #{first_error.debug_context.timestamp}")
IO.puts("")

# ============================================================================
# 6. SCHEMA COMPOSITION AND INHERITANCE
# ============================================================================

IO.puts("6. Schema Composition and Inheritance")
IO.puts("------------------------------------")

# Base entity schema
base_entity = Sinter.Schema.define([
  {:id, :string, [required: true]},
  {:created_at, :string, [optional: true]},
  {:updated_at, :string, [optional: true]}
], title: "Base Entity")

# User-specific fields
user_fields = Sinter.Schema.define([
  {:name, :string, [required: true]},
  {:email, :string, [required: true, format: ~r/@/]},
  {:role, :string, [required: true, choices: ["admin", "user", "guest"]]}
], title: "User Fields")

# Product-specific fields
product_fields = Sinter.Schema.define([
  {:title, :string, [required: true]},
  {:price, :float, [required: true, gt: 0.0]},
  {:category, :string, [required: true]}
], title: "Product Fields")

# Compose complete schemas
complete_user_schema = Sinter.merge_schemas([base_entity, user_fields],
  title: "Complete User Schema")

complete_product_schema = Sinter.merge_schemas([base_entity, product_fields],
  title: "Complete Product Schema")

IO.puts("✓ Composed user schema with #{map_size(complete_user_schema.fields)} fields")
IO.puts("✓ Composed product schema with #{map_size(complete_product_schema.fields)} fields")

# Test composed schemas
user_data = %{
  id: "user123",
  name: "John Doe",
  email: "john@example.com",
  role: "user",
  created_at: "2024-01-01T00:00:00Z"
}

{:ok, validated_user} = Sinter.Validator.validate(complete_user_schema, user_data)
IO.puts("✓ Composed user validated: #{validated_user.name} (#{validated_user.role})")

product_data = %{
  id: "prod456",
  title: "Amazing Widget",
  price: 29.99,
  category: "widgets"
}

{:ok, validated_product} = Sinter.Validator.validate(complete_product_schema, product_data)
IO.puts("✓ Composed product validated: #{validated_product.title} ($#{validated_product.price})")
IO.puts("")

IO.puts("=== Advanced Validation Examples Complete ===")
