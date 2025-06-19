defmodule SinterIntegrationTest do
  use ExUnit.Case, async: true

  alias Sinter.{JsonSchema, Schema, Validator}

  describe "end-to-end workflow: Schema -> Validate -> JSON Schema" do
    test "complete user registration workflow" do
      # 1. Define schema for user registration
      user_schema =
        Schema.define(
          [
            {:username, :string,
             [required: true, min_length: 3, max_length: 20, format: ~r/^[a-zA-Z0-9_]+$/]},
            {:email, :string, [required: true, format: ~r/.+@.+\..+/]},
            {:password, :string,
             [required: true, min_length: 8, format: ~r/(?=.*[A-Z])(?=.*[a-z])(?=.*\d)/]},
            {:age, :integer, [optional: true, gteq: 13, lteq: 120]},
            {:interests, {:array, :string}, [optional: true, max_items: 10]},
            {:terms_accepted, :boolean, [required: true, choices: [true]]}
          ],
          title: "User Registration",
          description: "Schema for new user registration"
        )

      # 2. Test valid registration data
      valid_data = %{
        "username" => "alice_123",
        "email" => "alice@example.com",
        "password" => "SecurePass123",
        "age" => 25,
        "interests" => ["programming", "music"],
        "terms_accepted" => true
      }

      assert {:ok, validated} = Validator.validate(user_schema, valid_data)
      assert validated[:username] == "alice_123"
      assert validated[:email] == "alice@example.com"
      assert validated[:age] == 25
      assert validated[:interests] == ["programming", "music"]
      assert validated[:terms_accepted] == true

      # 3. Generate JSON Schema for API documentation
      json_schema = JsonSchema.generate(user_schema)

      assert json_schema["type"] == "object"
      assert json_schema["title"] == "User Registration"
      assert json_schema["description"] == "Schema for new user registration"

      # Check required fields
      required_fields = json_schema["required"]
      assert "username" in required_fields
      assert "email" in required_fields
      assert "password" in required_fields
      assert "terms_accepted" in required_fields
      refute "age" in required_fields
      refute "interests" in required_fields

      # Check field constraints in JSON Schema
      username_schema = json_schema["properties"]["username"]
      assert username_schema["type"] == "string"
      assert username_schema["minLength"] == 3
      assert username_schema["maxLength"] == 20
      assert username_schema["pattern"] == "^[a-zA-Z0-9_]+$"

      password_schema = json_schema["properties"]["password"]
      assert password_schema["minLength"] == 8
      assert password_schema["pattern"] == "(?=.*[A-Z])(?=.*[a-z])(?=.*\\d)"

      age_schema = json_schema["properties"]["age"]
      assert age_schema["type"] == "integer"
      assert age_schema["minimum"] == 13
      assert age_schema["maximum"] == 120

      interests_schema = json_schema["properties"]["interests"]
      assert interests_schema["type"] == "array"
      assert interests_schema["items"]["type"] == "string"
      assert interests_schema["maxItems"] == 10

      terms_schema = json_schema["properties"]["terms_accepted"]
      assert terms_schema["type"] == "boolean"
      assert terms_schema["enum"] == [true]

      # 4. Test validation failures
      invalid_data = %{
        # too short
        "username" => "a",
        # no @ or domain
        "email" => "invalid-email",
        # too short, no uppercase/digit
        "password" => "weak",
        # too young
        "age" => 10,
        # too many
        "interests" => Enum.map(1..15, &"interest_#{&1}"),
        # must be true
        "terms_accepted" => false
      }

      assert {:error, errors} = Validator.validate(user_schema, invalid_data)
      # Should have multiple validation errors
      assert length(errors) >= 6

      # Check specific error types
      error_codes = Enum.map(errors, & &1.code)
      # username too short
      assert :min_length in error_codes
      # email format, password format
      assert :format in error_codes
      # age too low
      assert :gteq in error_codes
      # too many interests
      assert :max_items in error_codes
      # terms not accepted
      assert :choices in error_codes
    end

    test "e-commerce product schema workflow" do
      # Define product schema with complex validation rules
      product_schema =
        Schema.define(
          [
            {:name, :string, [required: true, min_length: 1, max_length: 100]},
            {:sku, :string, [required: true, format: ~r/^[A-Z]{2}-\d{4}-[A-Z]{2}$/]},
            {:price, :float, [required: true, gt: 0, lteq: 10_000.0]},
            {:category, :string,
             [required: true, choices: ["electronics", "clothing", "books", "home"]]},
            {:tags, {:array, :string}, [optional: true, min_items: 1, max_items: 5]},
            {:specifications, :map, [optional: true]},
            {:availability, :boolean, [required: true]},
            {:variants, {:array, :map}, [optional: true, max_items: 10]}
          ],
          title: "Product Schema",
          strict: true
        )

      # Valid product data
      valid_product = %{
        "name" => "Wireless Headphones",
        "sku" => "EL-1234-WH",
        "price" => 199.99,
        "category" => "electronics",
        "tags" => ["wireless", "audio", "bluetooth"],
        "specifications" => %{
          "battery_life" => "20 hours",
          "weight" => "250g",
          "color" => "black"
        },
        "availability" => true,
        "variants" => [
          %{"color" => "black", "stock" => 50},
          %{"color" => "white", "stock" => 30}
        ]
      }

      assert {:ok, validated} = Validator.validate(product_schema, valid_product)
      assert validated[:name] == "Wireless Headphones"
      assert validated[:sku] == "EL-1234-WH"
      assert validated[:price] == 199.99
      assert validated[:category] == "electronics"

      # Generate OpenAI-optimized JSON Schema
      openai_schema = JsonSchema.for_provider(product_schema, :openai)

      assert openai_schema["additionalProperties"] == false
      assert openai_schema["type"] == "object"
      assert is_list(openai_schema["required"])

      # Test strict mode validation (extra fields rejected)
      product_with_extra = Map.put(valid_product, "unauthorized_field", "value")

      assert {:error, [error]} = Validator.validate(product_schema, product_with_extra)
      assert error.code == :strict
      assert error.message =~ "unauthorized_field"

      # Test constraint violations
      invalid_product = %{
        # too short
        "name" => "",
        # wrong format
        "sku" => "INVALID-SKU",
        # negative price
        "price" => -10.0,
        # not in choices
        "category" => "invalid_category",
        # too few items (min_items: 1)
        "tags" => [],
        "availability" => true
      }

      assert {:error, errors} = Validator.validate(product_schema, invalid_product)

      error_codes = Enum.map(errors, & &1.code)
      assert :min_length in error_codes
      assert :format in error_codes
      assert :gt in error_codes
      assert :choices in error_codes
      assert :min_items in error_codes
    end

    test "nested data structure with post-validation" do
      # Custom validation function
      validate_order_business_rules = fn order ->
        # Business rule: Orders over $1000 require billing address
        if order[:total_amount] > 1000.0 and is_nil(order[:billing_address]) do
          {:error, "Orders over $1000 require billing address"}
        else
          # Business rule: Free shipping for orders over $50
          updated_order =
            if order[:total_amount] > 50.0 do
              Map.put(order, :free_shipping, true)
            else
              order
            end

          {:ok, updated_order}
        end
      end

      # Schema for order with custom validation logic
      order_schema =
        Schema.define(
          [
            {:order_id, :string, [required: true, format: ~r/^ORD-\d{8}$/]},
            {:customer_email, :string, [required: true, format: ~r/.+@.+/]},
            {:items, {:array, :map}, [required: true, min_items: 1]},
            {:shipping_address, :map, [required: true]},
            {:billing_address, :map, [optional: true]},
            {:total_amount, :float, [required: true, gt: 0]},
            {:currency, :string, [required: true, choices: ["USD", "EUR", "GBP"]]},
            {:payment_method, :string,
             [required: true, choices: ["credit_card", "paypal", "bank_transfer"]]}
          ],
          post_validate: validate_order_business_rules
        )

      # Valid order under $1000 (no billing address required)
      valid_order = %{
        "order_id" => "ORD-12345678",
        "customer_email" => "customer@example.com",
        "items" => [
          %{"product_id" => "P001", "quantity" => 2, "price" => 25.0}
        ],
        "shipping_address" => %{
          "street" => "123 Main St",
          "city" => "Anytown",
          "zip" => "12345"
        },
        "total_amount" => 50.0,
        "currency" => "USD",
        "payment_method" => "credit_card"
      }

      assert {:ok, validated} = Validator.validate(order_schema, valid_order)
      assert validated[:order_id] == "ORD-12345678"
      assert validated[:total_amount] == 50.0
      # Post-validation should not add free_shipping for exactly $50
      refute Map.has_key?(validated, :free_shipping)

      # Order with free shipping (over $50)
      large_order = Map.put(valid_order, "total_amount", 75.0)

      assert {:ok, validated} = Validator.validate(order_schema, large_order)
      assert validated[:free_shipping] == true

      # Large order without billing address (should fail post-validation)
      expensive_order = %{
        "order_id" => "ORD-87654321",
        "customer_email" => "customer@example.com",
        "items" => [
          %{"product_id" => "P002", "quantity" => 1, "price" => 1500.0}
        ],
        "shipping_address" => %{
          "street" => "456 Oak Ave",
          "city" => "BigCity",
          "zip" => "54321"
        },
        "total_amount" => 1500.0,
        "currency" => "USD",
        "payment_method" => "credit_card"
      }

      assert {:error, [error]} = Validator.validate(order_schema, expensive_order)
      assert error.code == :post_validation
      assert error.message =~ "billing address"

      # Large order WITH billing address (should pass)
      expensive_order_with_billing =
        Map.put(expensive_order, "billing_address", %{
          "street" => "789 Pine St",
          "city" => "BigCity",
          "zip" => "54321"
        })

      assert {:ok, validated} = Validator.validate(order_schema, expensive_order_with_billing)
      assert validated[:total_amount] == 1500.0
      assert validated[:free_shipping] == true
      assert is_map(validated[:billing_address])
    end
  end

  describe "provider-specific JSON Schema generation workflows" do
    test "OpenAI function calling workflow" do
      # Define schema suitable for OpenAI function calling
      function_schema =
        Schema.define(
          [
            {:query, :string, [required: true, description: "Search query"]},
            {:max_results, :integer,
             [
               optional: true,
               default: 10,
               gteq: 1,
               lteq: 100,
               description: "Maximum number of results"
             ]},
            {:include_metadata, :boolean,
             [optional: true, default: false, description: "Include result metadata"]},
            {:filters, {:array, :string}, [optional: true, description: "Search filters to apply"]}
          ],
          title: "Search Function",
          description: "Performs a search with the given parameters"
        )

      # Generate OpenAI-optimized schema
      openai_schema = JsonSchema.for_provider(function_schema, :openai)

      # OpenAI requirements
      assert openai_schema["type"] == "object"
      assert openai_schema["additionalProperties"] == false
      assert is_list(openai_schema["required"])
      assert "query" in openai_schema["required"]

      # Test the schema works for validation
      function_call_data = %{
        "query" => "machine learning tutorials",
        "max_results" => 25,
        "include_metadata" => true,
        "filters" => ["recent", "video"]
      }

      assert {:ok, validated} = Validator.validate(function_schema, function_call_data)
      assert validated[:query] == "machine learning tutorials"
      assert validated[:max_results] == 25
      assert validated[:include_metadata] == true
      assert validated[:filters] == ["recent", "video"]

      # Test with minimal data (using defaults)
      minimal_call = %{"query" => "elixir programming"}

      assert {:ok, validated} = Validator.validate(function_schema, minimal_call)
      assert validated[:query] == "elixir programming"
      # default applied
      assert validated[:max_results] == 10
      # default applied
      assert validated[:include_metadata] == false
    end

    test "Anthropic tool use workflow" do
      # Define schema for Anthropic tool
      tool_schema =
        Schema.define(
          [
            {:action, :string,
             [
               required: true,
               choices: ["create", "update", "delete", "read"],
               description: "Action to perform"
             ]},
            {:resource_type, :string,
             [required: true, choices: ["user", "post", "comment"], description: "Type of resource"]},
            {:resource_id, :string,
             [optional: true, description: "ID of existing resource (for update/delete/read)"]},
            {:data, :map, [optional: true, description: "Data for create/update operations"]},
            {:options, :map, [optional: true, description: "Additional options"]}
          ],
          title: "Database Tool",
          description: "Tool for database operations"
        )

      # Generate Anthropic-optimized schema
      anthropic_schema = JsonSchema.for_provider(tool_schema, :anthropic)

      # Anthropic preferences
      assert anthropic_schema["type"] == "object"
      assert anthropic_schema["additionalProperties"] == false
      assert Map.has_key?(anthropic_schema, "properties")

      # Test CRUD operations
      create_operation = %{
        "action" => "create",
        "resource_type" => "user",
        "data" => %{
          "name" => "John Doe",
          "email" => "john@example.com"
        }
      }

      assert {:ok, validated} = Validator.validate(tool_schema, create_operation)
      assert validated[:action] == "create"
      assert validated[:resource_type] == "user"
      assert is_map(validated[:data])

      read_operation = %{
        "action" => "read",
        "resource_type" => "post",
        "resource_id" => "post_123"
      }

      assert {:ok, validated} = Validator.validate(tool_schema, read_operation)
      assert validated[:action] == "read"
      assert validated[:resource_id] == "post_123"
    end
  end

  describe "complex data type workflows" do
    test "nested array and union type validation" do
      # Schema with complex nested types
      complex_schema =
        Schema.define([
          {:data_points, {:array, {:tuple, [:string, {:union, [:integer, :float]}]}},
           [required: true]},
          {:metadata, {:map, :string, {:union, [:string, :integer, :boolean]}}, [optional: true]},
          {:processing_options, {:union, [:string, :map]}, [optional: true]}
        ])

      # Valid complex data
      complex_data = %{
        "data_points" => [
          {"temperature", 23.5},
          {"humidity", 65},
          {"pressure", 1013.25}
        ],
        "metadata" => %{
          "source" => "sensor_001",
          "calibrated" => true,
          "readings_count" => 100
        },
        "processing_options" => %{
          "algorithm" => "linear_interpolation",
          "smoothing" => true
        }
      }

      assert {:ok, validated} = Validator.validate(complex_schema, complex_data)

      # Check tuple validation
      first_point = List.first(validated[:data_points])
      assert first_point == {"temperature", 23.5}

      # Check map with union values
      assert validated[:metadata]["source"] == "sensor_001"
      assert validated[:metadata]["calibrated"] == true
      assert validated[:metadata]["readings_count"] == 100

      # Test with string processing options (union alternative)
      data_with_string_options = Map.put(complex_data, "processing_options", "default")

      assert {:ok, validated} = Validator.validate(complex_schema, data_with_string_options)
      assert validated[:processing_options] == "default"

      # Generate JSON Schema for complex types
      json_schema = JsonSchema.generate(complex_schema)

      # Check tuple representation
      data_points_schema = json_schema["properties"]["data_points"]
      assert data_points_schema["type"] == "array"
      assert data_points_schema["items"]["type"] == "array"

      assert data_points_schema["items"]["prefixItems"] == [
               %{"type" => "string"},
               %{"oneOf" => [%{"type" => "integer"}, %{"type" => "number"}]}
             ]

      # Check union type representation
      processing_schema = json_schema["properties"]["processing_options"]

      assert processing_schema["oneOf"] == [
               %{"type" => "string"},
               %{"type" => "object", "additionalProperties" => true}
             ]
    end

    test "polymorphic data validation workflow" do
      # Custom validation based on message type
      validate_message_content = fn message ->
        case message[:type] do
          "text" ->
            if is_binary(message[:content]) do
              {:ok, message}
            else
              {:error, "Text messages must have string content"}
            end

          "image" ->
            if is_map(message[:content]) and
                 (Map.has_key?(message[:content], "url") or Map.has_key?(message[:content], :url)) do
              {:ok, message}
            else
              {:error, "Image messages must have content with url"}
            end

          "file" ->
            if is_map(message[:content]) and
                 (Map.has_key?(message[:content], "filename") or
                    Map.has_key?(message[:content], :filename)) do
              {:ok, message}
            else
              {:error, "File messages must have content with filename"}
            end

          "system" ->
            {:ok, Map.put(message, :system_processed, true)}
        end
      end

      # Schema for handling different message types
      message_schema =
        Schema.define(
          [
            {:type, :string, [required: true, choices: ["text", "image", "file", "system"]]},
            {:content, {:union, [:string, :map]}, [required: true]},
            {:timestamp, :integer, [required: true, gt: 0]},
            {:metadata, :map, [optional: true]}
          ],
          post_validate: validate_message_content
        )

      # Test different message types
      text_message = %{
        "type" => "text",
        "content" => "Hello, world!",
        "timestamp" => 1_234_567_890
      }

      assert {:ok, validated} = Validator.validate(message_schema, text_message)
      assert validated[:type] == "text"
      assert validated[:content] == "Hello, world!"

      image_message = %{
        "type" => "image",
        "content" => %{
          "url" => "https://example.com/image.jpg",
          "alt_text" => "A beautiful sunset"
        },
        "timestamp" => 1_234_567_890
      }

      assert {:ok, validated} = Validator.validate(message_schema, image_message)
      assert validated[:type] == "image"
      assert validated[:content]["url"] == "https://example.com/image.jpg"

      system_message = %{
        "type" => "system",
        "content" => "User joined the channel",
        "timestamp" => 1_234_567_890
      }

      assert {:ok, validated} = Validator.validate(message_schema, system_message)
      assert validated[:system_processed] == true

      # Test validation failures
      invalid_text = %{
        "type" => "text",
        # Should be string for text type
        "content" => %{"not" => "string"},
        "timestamp" => 1_234_567_890
      }

      assert {:error, [error]} = Validator.validate(message_schema, invalid_text)
      assert error.code == :post_validation
      assert error.message =~ "string content"

      invalid_image = %{
        "type" => "image",
        # Missing required url field
        "content" => %{"missing" => "url"},
        "timestamp" => 1_234_567_890
      }

      assert {:error, [error]} = Validator.validate(message_schema, invalid_image)
      assert error.code == :post_validation
      assert error.message =~ "url"
    end
  end

  describe "coercion workflows" do
    test "API input normalization with coercion" do
      # Schema for API endpoint that accepts string inputs but needs typed data
      api_schema =
        Schema.define([
          {:user_id, :integer, [required: true, gt: 0]},
          {:limit, :integer, [optional: true, default: 20, gteq: 1, lteq: 100]},
          {:offset, :integer, [optional: true, default: 0, gteq: 0]},
          {:sort_ascending, :boolean, [optional: true, default: true]},
          {:filters, {:array, :string}, [optional: true]},
          {:include_metadata, :boolean, [optional: true, default: false]}
        ])

      # Simulate API input (all strings from query parameters)
      api_input = %{
        "user_id" => "12345",
        "limit" => "50",
        "offset" => "100",
        "sort_ascending" => "false",
        # Already correct type
        "filters" => ["active", "verified"],
        "include_metadata" => "true"
      }

      # Validate with coercion enabled
      assert {:ok, normalized} = Validator.validate(api_schema, api_input, coerce: true)

      # Check types were coerced correctly
      assert normalized[:user_id] == 12_345
      assert normalized[:limit] == 50
      assert normalized[:offset] == 100
      assert normalized[:sort_ascending] == false
      assert normalized[:include_metadata] == true
      assert normalized[:filters] == ["active", "verified"]

      # Test with minimal input (defaults applied)
      minimal_input = %{"user_id" => "999"}

      assert {:ok, normalized} = Validator.validate(api_schema, minimal_input, coerce: true)
      assert normalized[:user_id] == 999
      # default
      assert normalized[:limit] == 20
      # default
      assert normalized[:offset] == 0
      # default
      assert normalized[:sort_ascending] == true
      # default
      assert normalized[:include_metadata] == false

      # Test coercion failures
      invalid_input = %{
        "user_id" => "not_a_number",
        "limit" => "50"
      }

      assert {:error, [error]} = Validator.validate(api_schema, invalid_input, coerce: true)
      assert error.code == :coercion
      assert error.path == [:user_id]

      # Test constraint violations after coercion
      invalid_constraints = %{
        # Will coerce to 0, but violates gt: 0
        "user_id" => "0",
        # Will coerce to 150, but violates lteq: 100
        "limit" => "150"
      }

      assert {:error, errors} = Validator.validate(api_schema, invalid_constraints, coerce: true)
      assert length(errors) == 2

      error_codes = Enum.map(errors, & &1.code)
      assert :gt in error_codes
      assert :lteq in error_codes
    end

    test "CSV import workflow with coercion and validation" do
      # Schema for importing user data from CSV
      import_schema =
        Schema.define([
          {:name, :string, [required: true, min_length: 1]},
          {:email, :string, [required: true, format: ~r/.+@.+/]},
          {:age, :integer, [optional: true, gteq: 0, lteq: 150]},
          {:is_active, :boolean, [optional: true, default: true]},
          # YYYY-MM-DD
          {:join_date, :string, [optional: true, format: ~r/^\d{4}-\d{2}-\d{2}$/]}
        ])

      # Simulate CSV row data (all strings)
      csv_rows = [
        %{
          "name" => "Alice Johnson",
          "email" => "alice@example.com",
          "age" => "28",
          "is_active" => "true",
          "join_date" => "2023-01-15"
        },
        %{
          "name" => "Bob Smith",
          "email" => "bob@example.com",
          "age" => "35",
          "is_active" => "false",
          "join_date" => "2023-02-20"
        },
        %{
          "name" => "Charlie Brown",
          "email" => "charlie@example.com"
          # Missing optional fields - should get defaults
        }
      ]

      # Process all rows with coercion
      results =
        Enum.map(csv_rows, fn row ->
          Validator.validate(import_schema, row, coerce: true)
        end)

      # All should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Check specific results
      {:ok, alice} = Enum.at(results, 0)
      assert alice[:name] == "Alice Johnson"
      # coerced from string
      assert alice[:age] == 28
      # coerced from string
      assert alice[:is_active] == true

      {:ok, bob} = Enum.at(results, 1)
      # coerced from string
      assert bob[:is_active] == false

      {:ok, charlie} = Enum.at(results, 2)
      # default value
      assert charlie[:is_active] == true
      # optional field not provided
      refute Map.has_key?(charlie, :age)

      # Test batch validation for import
      assert {:ok, all_validated} = Validator.validate_many(import_schema, csv_rows, coerce: true)
      assert length(all_validated) == 3

      # Test with invalid data
      invalid_rows = [
        %{
          # too short
          "name" => "",
          "email" => "alice@example.com",
          "age" => "28"
        },
        %{
          "name" => "Valid Name",
          # no domain
          "email" => "invalid-email",
          # too old
          "age" => "200"
        }
      ]

      assert {:error, error_map} =
               Validator.validate_many(import_schema, invalid_rows, coerce: true)

      # First row has error
      assert Map.has_key?(error_map, 0)
      # Second row has error
      assert Map.has_key?(error_map, 1)

      # Check specific error types
      first_row_errors = error_map[0]
      assert Enum.any?(first_row_errors, &(&1.code == :min_length))

      second_row_errors = error_map[1]
      error_codes = Enum.map(second_row_errors, & &1.code)
      # email format
      assert :format in error_codes
      # age too high
      assert :lteq in error_codes
    end
  end

  describe "performance benchmarks" do
    @tag :benchmark
    test "schema compilation performance" do
      # Measure time to create complex schemas
      large_field_count = 100

      start_time = System.monotonic_time(:microsecond)

      large_schema =
        Schema.define(
          Enum.map(1..large_field_count, fn i ->
            {String.to_atom("field_#{i}"), :string, [optional: true, min_length: 1]}
          end)
        )

      compile_time = System.monotonic_time(:microsecond) - start_time

      # Should compile reasonably fast (less than 100ms for 100 fields)
      assert compile_time < 100_000
      assert %Schema{} = large_schema
      assert map_size(large_schema.fields) == large_field_count
    end

    @tag :benchmark
    test "validation performance on large datasets" do
      # Create schema for performance testing
      perf_schema =
        Schema.define([
          {:id, :integer, [required: true, gt: 0]},
          {:name, :string, [required: true, min_length: 1, max_length: 100]},
          {:email, :string, [required: true, format: ~r/.+@.+/]},
          {:tags, {:array, :string}, [optional: true, max_items: 10]}
        ])

      # Generate large dataset
      dataset_size = 1000

      large_dataset =
        Enum.map(1..dataset_size, fn i ->
          %{
            "id" => i,
            "name" => "User #{i}",
            "email" => "user#{i}@example.com",
            "tags" => ["tag1", "tag2"]
          }
        end)

      # Measure validation time
      start_time = System.monotonic_time(:microsecond)

      results =
        Enum.map(large_dataset, fn item ->
          Validator.validate(perf_schema, item)
        end)

      validation_time = System.monotonic_time(:microsecond) - start_time

      # All validations should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Should validate reasonably fast (less than 1ms per item on average)
      avg_time_per_item = validation_time / dataset_size
      # microseconds
      assert avg_time_per_item < 1000

      IO.puts(
        "Validated #{dataset_size} items in #{validation_time / 1000}ms (#{Float.round(avg_time_per_item, 2)}μs per item)"
      )
    end

    @tag :benchmark
    test "JSON Schema generation performance" do
      # Create complex schema
      complex_schema =
        Schema.define([
          {:simple_field, :string, [required: true]},
          {:array_field, {:array, :string}, [optional: true]},
          {:union_field, {:union, [:string, :integer, :boolean]}, [optional: true]},
          {:tuple_field, {:tuple, [:string, :integer, :float]}, [optional: true]},
          {:map_field, {:map, :string, :integer}, [optional: true]},
          {:nested_array, {:array, {:array, :string}}, [optional: true]},
          {:complex_union, {:union, [:string, {:array, :integer}, :map]}, [optional: true]}
        ])

      # Measure JSON Schema generation
      iterations = 100

      start_time = System.monotonic_time(:microsecond)

      Enum.each(1..iterations, fn _ ->
        JsonSchema.generate(complex_schema)
      end)

      generation_time = System.monotonic_time(:microsecond) - start_time
      avg_time = generation_time / iterations

      # Should generate quickly (less than 1ms per generation)
      # microseconds
      assert avg_time < 1000

      IO.puts(
        "Generated JSON Schema #{iterations} times in #{generation_time / 1000}ms (#{Float.round(avg_time, 2)}μs per generation)"
      )
    end

    @tag :benchmark
    test "batch validation vs individual validation performance" do
      schema =
        Schema.define([
          {:name, :string, [required: true]},
          {:value, :integer, [required: true, gt: 0]}
        ])

      dataset =
        Enum.map(1..1000, fn i ->
          %{"name" => "item_#{i}", "value" => i}
        end)

      # Individual validations
      start_time = System.monotonic_time(:microsecond)

      individual_results =
        Enum.map(dataset, fn item ->
          Validator.validate(schema, item)
        end)

      individual_time = System.monotonic_time(:microsecond) - start_time

      # Batch validation
      start_time = System.monotonic_time(:microsecond)

      {:ok, batch_results} = Validator.validate_many(schema, dataset)

      batch_time = System.monotonic_time(:microsecond) - start_time

      # Both should produce same results
      individual_values = Enum.map(individual_results, fn {:ok, val} -> val end)
      assert individual_values == batch_results

      # Batch should be faster or comparable
      speedup = individual_time / batch_time
      # At least 80% as fast, ideally faster
      assert speedup >= 0.8

      IO.puts(
        "Individual: #{individual_time / 1000}ms, Batch: #{batch_time / 1000}ms, Speedup: #{Float.round(speedup, 2)}x"
      )
    end
  end

  describe "memory usage and garbage collection" do
    @tag :memory
    test "schema creation doesn't leak memory" do
      # Get initial memory usage
      :erlang.garbage_collect()
      {_, initial_memory} = :erlang.process_info(self(), :memory)

      # Create and discard many schemas
      Enum.each(1..1000, fn i ->
        Schema.define([
          {String.to_atom("field_#{i}"), :string, [required: true]}
        ])
      end)

      # Force garbage collection
      :erlang.garbage_collect()
      {_, final_memory} = :erlang.process_info(self(), :memory)

      # Memory should not grow significantly
      memory_growth = final_memory - initial_memory
      memory_growth_mb = memory_growth / (1024 * 1024)

      # Should not grow by more than 10MB
      assert memory_growth_mb < 10

      IO.puts("Memory growth: #{Float.round(memory_growth_mb, 2)}MB")
    end

    @tag :memory
    test "validation doesn't accumulate memory" do
      schema =
        Schema.define([
          {:data, {:array, :string}, [required: true]}
        ])

      # Get initial memory
      :erlang.garbage_collect()
      {_, initial_memory} = :erlang.process_info(self(), :memory)

      # Perform many validations
      Enum.each(1..1000, fn i ->
        data = %{"data" => Enum.map(1..10, &"item_#{&1}_#{i}")}
        Validator.validate(schema, data)
      end)

      # Force garbage collection
      :erlang.garbage_collect()
      {_, final_memory} = :erlang.process_info(self(), :memory)

      # Memory should remain relatively stable
      memory_growth = final_memory - initial_memory
      memory_growth_mb = memory_growth / (1024 * 1024)

      assert memory_growth_mb < 5

      IO.puts("Validation memory growth: #{Float.round(memory_growth_mb, 2)}MB")
    end
  end
end
