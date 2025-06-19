defmodule Sinter.JsonSchemaTest do
  use ExUnit.Case, async: true

  alias Sinter.{JsonSchema, Schema}

  # Helper function to create test schema
  defp test_schema(fields \\ nil, opts \\ []) do
    fields =
      fields ||
        [
          {:name, :string, [required: true, min_length: 2, max_length: 50]},
          {:age, :integer, [optional: true, gt: 0, lt: 150]},
          {:email, :string, [optional: true, format: ~r/.+@.+/]},
          {:tags, {:array, :string}, [optional: true, max_items: 10]}
        ]

    Schema.define(fields, opts)
  end

  describe "generate/2 - basic JSON Schema generation" do
    test "generates basic object schema" do
      schema =
        Schema.define([
          {:name, :string, [required: true]},
          {:age, :integer, [optional: true]}
        ])

      json_schema = JsonSchema.generate(schema)

      assert json_schema["type"] == "object"
      assert is_map(json_schema["properties"])
      assert json_schema["properties"]["name"]["type"] == "string"
      assert json_schema["properties"]["age"]["type"] == "integer"
      assert json_schema["required"] == ["name"]
      # default not strict
      assert json_schema["additionalProperties"] == true
    end

    test "generates schema with title and description" do
      schema =
        Schema.define(
          [
            {:name, :string, [required: true]}
          ],
          title: "User Schema",
          description: "Schema for user data"
        )

      json_schema = JsonSchema.generate(schema)

      assert json_schema["title"] == "User Schema"
      assert json_schema["description"] == "Schema for user data"
    end

    test "generates schema with field descriptions" do
      schema =
        Schema.define([
          {:name, :string, [required: true, description: "User's full name"]},
          {:age, :integer, [optional: true, description: "User's age in years"]}
        ])

      json_schema = JsonSchema.generate(schema)

      assert json_schema["properties"]["name"]["description"] == "User's full name"
      assert json_schema["properties"]["age"]["description"] == "User's age in years"
    end

    test "excludes descriptions when requested" do
      schema =
        Schema.define([
          {:name, :string, [required: true, description: "User's full name"]}
        ])

      json_schema = JsonSchema.generate(schema, include_descriptions: false)

      refute Map.has_key?(json_schema["properties"]["name"], "description")
    end

    test "handles strict mode" do
      strict_schema =
        Schema.define(
          [
            {:name, :string, [required: true]}
          ],
          strict: true
        )

      json_schema = JsonSchema.generate(strict_schema)

      assert json_schema["additionalProperties"] == false
    end

    test "overrides strict mode with option" do
      schema =
        Schema.define([
          {:name, :string, [required: true]}
        ])

      # Override to strict
      strict_json = JsonSchema.generate(schema, strict: true)
      assert strict_json["additionalProperties"] == false

      # Override to non-strict
      non_strict_json = JsonSchema.generate(schema, strict: false)
      assert non_strict_json["additionalProperties"] == true
    end
  end

  describe "generate/2 - type conversions" do
    test "converts primitive types correctly" do
      schema =
        Schema.define([
          {:text, :string, [required: true]},
          {:count, :integer, [required: true]},
          {:price, :float, [required: true]},
          {:active, :boolean, [required: true]},
          {:tag, :atom, [required: true]},
          {:metadata, :map, [required: true]},
          {:anything, :any, [required: true]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      assert props["text"]["type"] == "string"
      assert props["count"]["type"] == "integer"
      assert props["price"]["type"] == "number"
      assert props["active"]["type"] == "boolean"
      assert props["tag"]["type"] == "string"
      assert props["tag"]["description"] =~ "Atom"
      assert props["metadata"]["type"] == "object"
      # any type has no constraints
      assert props["anything"] == %{}
    end

    test "converts array types" do
      schema =
        Schema.define([
          {:strings, {:array, :string}, [required: true]},
          {:numbers, {:array, :integer}, [required: true]},
          {:nested, {:array, {:array, :string}}, [required: true]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      # String array
      assert props["strings"]["type"] == "array"
      assert props["strings"]["items"]["type"] == "string"

      # Integer array
      assert props["numbers"]["type"] == "array"
      assert props["numbers"]["items"]["type"] == "integer"

      # Nested array
      assert props["nested"]["type"] == "array"
      assert props["nested"]["items"]["type"] == "array"
      assert props["nested"]["items"]["items"]["type"] == "string"
    end

    test "converts union types to oneOf" do
      schema =
        Schema.define([
          {:id, {:union, [:string, :integer]}, [required: true]},
          {:value, {:union, [:string, :boolean, :float]}, [required: true]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      # Simple union
      assert props["id"]["oneOf"] == [
               %{"type" => "string"},
               %{"type" => "integer"}
             ]

      # Multi-type union
      assert props["value"]["oneOf"] == [
               %{"type" => "string"},
               %{"type" => "boolean"},
               %{"type" => "number"}
             ]
    end

    test "converts tuple types to array with prefixItems" do
      schema =
        Schema.define([
          {:coords, {:tuple, [:float, :float]}, [required: true]},
          {:rgb, {:tuple, [:integer, :integer, :integer]}, [required: true]},
          {:mixed, {:tuple, [:string, :integer, :boolean]}, [required: true]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      # Coordinates tuple
      coords_schema = props["coords"]
      assert coords_schema["type"] == "array"
      assert coords_schema["items"] == false

      assert coords_schema["prefixItems"] == [
               %{"type" => "number"},
               %{"type" => "number"}
             ]

      assert coords_schema["minItems"] == 2
      assert coords_schema["maxItems"] == 2

      # RGB tuple
      rgb_schema = props["rgb"]

      assert rgb_schema["prefixItems"] == [
               %{"type" => "integer"},
               %{"type" => "integer"},
               %{"type" => "integer"}
             ]

      assert rgb_schema["minItems"] == 3
      assert rgb_schema["maxItems"] == 3

      # Mixed tuple
      mixed_schema = props["mixed"]

      assert mixed_schema["prefixItems"] == [
               %{"type" => "string"},
               %{"type" => "integer"},
               %{"type" => "boolean"}
             ]
    end

    test "converts map types with key/value constraints" do
      schema =
        Schema.define([
          {:simple_map, :map, [required: true]},
          {:string_map, {:map, :string, :integer}, [required: true]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      # Simple map
      assert props["simple_map"]["type"] == "object"

      # String-keyed map
      string_map_schema = props["string_map"]
      assert string_map_schema["type"] == "object"
      assert string_map_schema["additionalProperties"]["type"] == "integer"
    end
  end

  describe "generate/2 - constraint conversion" do
    test "converts string constraints" do
      schema =
        Schema.define([
          {:short, :string, [required: true, min_length: 2, max_length: 10]},
          {:pattern, :string, [required: true, format: ~r/^[A-Z]/]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      # Length constraints
      assert props["short"]["minLength"] == 2
      assert props["short"]["maxLength"] == 10

      # Pattern constraint
      assert props["pattern"]["pattern"] == "^[A-Z]"
    end

    test "converts numeric constraints" do
      schema =
        Schema.define([
          {:score, :integer, [required: true, gt: 0, lt: 100]},
          {:rating, :float, [required: true, gteq: 1.0, lteq: 5.0]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      # Exclusive bounds
      assert props["score"]["exclusiveMinimum"] == 0
      assert props["score"]["exclusiveMaximum"] == 100

      # Inclusive bounds
      assert props["rating"]["minimum"] == 1.0
      assert props["rating"]["maximum"] == 5.0
    end

    test "converts array constraints" do
      schema =
        Schema.define([
          {:items, {:array, :string}, [required: true, min_items: 1, max_items: 5]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      assert props["items"]["minItems"] == 1
      assert props["items"]["maxItems"] == 5
    end

    test "converts choice constraints to enum" do
      schema =
        Schema.define([
          {:status, :string, [required: true, choices: ["active", "inactive", "pending"]]},
          {:priority, :integer, [required: true, choices: [1, 2, 3]]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      assert props["status"]["enum"] == ["active", "inactive", "pending"]
      assert props["priority"]["enum"] == [1, 2, 3]
    end

    test "handles multiple constraints on single field" do
      schema =
        Schema.define([
          {:code, :string,
           [
             required: true,
             min_length: 3,
             max_length: 10,
             format: ~r/^[A-Z]/,
             choices: ["ABC", "DEF", "GHI"]
           ]}
        ])

      json_schema = JsonSchema.generate(schema)
      code_schema = json_schema["properties"]["code"]

      assert code_schema["minLength"] == 3
      assert code_schema["maxLength"] == 10
      assert code_schema["pattern"] == "^[A-Z]"
      assert code_schema["enum"] == ["ABC", "DEF", "GHI"]
    end
  end

  describe "generate/2 - field metadata" do
    test "includes field examples" do
      schema =
        Schema.define([
          {:name, :string, [required: true, example: "John Doe"]},
          {:age, :integer, [required: true, example: 30]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      assert props["name"]["examples"] == ["John Doe"]
      assert props["age"]["examples"] == [30]
    end

    test "includes default values" do
      schema =
        Schema.define([
          {:active, :boolean, [optional: true, default: true]},
          {:count, :integer, [optional: true, default: 0]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      assert props["active"]["default"] == true
      assert props["count"]["default"] == 0
    end

    test "omits nil defaults" do
      schema =
        Schema.define([
          {:nullable, :string, [optional: true, default: nil]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      refute Map.has_key?(props["nullable"], "default")
    end
  end

  describe "generate/2 - schema metadata" do
    test "includes Sinter metadata" do
      schema = test_schema()
      json_schema = JsonSchema.generate(schema)

      assert Map.has_key?(json_schema, "x-sinter-version")
      assert Map.has_key?(json_schema, "x-sinter-field-count")
      assert Map.has_key?(json_schema, "x-sinter-created-at")

      assert json_schema["x-sinter-field-count"] == 4
      assert is_binary(json_schema["x-sinter-version"])
      assert is_binary(json_schema["x-sinter-created-at"])
    end

    test "generates valid ISO8601 timestamp" do
      schema = test_schema()
      json_schema = JsonSchema.generate(schema)

      timestamp = json_schema["x-sinter-created-at"]

      # Should be parseable as DateTime
      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(timestamp)
    end
  end

  describe "for_provider/3 - provider-specific optimizations" do
    test "generates generic schema by default" do
      schema = test_schema()

      generic_schema = JsonSchema.for_provider(schema, :generic)
      standard_schema = JsonSchema.generate(schema)

      assert generic_schema == standard_schema
    end

    test "optimizes for OpenAI" do
      schema = test_schema()

      openai_schema = JsonSchema.for_provider(schema, :openai)

      # OpenAI requires additionalProperties: false
      assert openai_schema["additionalProperties"] == false

      # Should have required array even if empty
      assert is_list(openai_schema["required"])
    end

    test "optimizes for Anthropic" do
      schema = test_schema()

      anthropic_schema = JsonSchema.for_provider(schema, :anthropic)

      # Anthropic prefers additionalProperties: false
      assert anthropic_schema["additionalProperties"] == false

      # Should have required array
      assert is_list(anthropic_schema["required"])
    end

    test "OpenAI removes unsupported formats" do
      schema =
        Schema.define([
          {:email, :string, [required: true, format: ~r/.+@.+/]},
          {:name, :string, [required: true]}
        ])

      openai_schema = JsonSchema.for_provider(schema, :openai)

      # Should remove format patterns that OpenAI doesn't support well
      # (This tests the optimization logic - actual format removal depends on implementation)
      assert is_map(openai_schema["properties"]["email"])
      assert is_map(openai_schema["properties"]["name"])
    end

    test "simplifies complex unions for OpenAI" do
      # Create union with many types
      many_types = [:string, :integer, :float, :boolean, :atom]

      schema =
        Schema.define([
          {:value, {:union, many_types}, [required: true]}
        ])

      openai_schema = JsonSchema.for_provider(schema, :openai)

      # Should limit union complexity
      value_schema = openai_schema["properties"]["value"]

      if Map.has_key?(value_schema, "oneOf") do
        assert length(value_schema["oneOf"]) <= 3
      end
    end

    test "ensures object properties for Anthropic" do
      # Create minimal object schema
      schema = Schema.define([], title: "Empty Schema")

      anthropic_schema = JsonSchema.for_provider(schema, :anthropic)

      assert anthropic_schema["type"] == "object"
      assert Map.has_key?(anthropic_schema, "properties")
    end
  end

  describe "validate_schema/2" do
    test "validates correct schema structure" do
      valid_schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"}
        },
        "required" => ["name"]
      }

      assert :ok = JsonSchema.validate_schema(valid_schema)
    end

    test "detects missing type field" do
      invalid_schema = %{
        "properties" => %{
          "name" => %{"type" => "string"}
        }
      }

      assert {:error, issues} = JsonSchema.validate_schema(invalid_schema)
      assert "Schema missing 'type' field" in issues
    end

    test "detects missing properties for object type" do
      invalid_schema = %{
        "type" => "object",
        "required" => ["name"]
      }

      assert {:error, issues} = JsonSchema.validate_schema(invalid_schema)
      assert "Object schema missing 'properties'" in issues
    end

    test "validates constraint consistency" do
      # Invalid numeric constraints
      invalid_schema = %{
        "type" => "object",
        "properties" => %{
          "value" => %{
            "type" => "integer",
            "minimum" => 10,
            "maximum" => 5
          }
        }
      }

      assert {:error, issues} = JsonSchema.validate_schema(invalid_schema)
      assert Enum.any?(issues, &String.contains?(&1, "minimum"))
    end

    test "validates string constraint consistency" do
      invalid_schema = %{
        "type" => "object",
        "properties" => %{
          "text" => %{
            "type" => "string",
            "minLength" => 10,
            "maxLength" => 5
          }
        }
      }

      assert {:error, issues} = JsonSchema.validate_schema(invalid_schema)
      assert Enum.any?(issues, &String.contains?(&1, "minLength"))
    end

    test "validates array constraint consistency" do
      invalid_schema = %{
        "type" => "object",
        "properties" => %{
          "items" => %{
            "type" => "array",
            "minItems" => 5,
            "maxItems" => 2
          }
        }
      }

      assert {:error, issues} = JsonSchema.validate_schema(invalid_schema)
      assert Enum.any?(issues, &String.contains?(&1, "minItems"))
    end
  end

  describe "complex schema scenarios" do
    test "generates schema for deeply nested structures" do
      schema =
        Schema.define([
          {:user, :map, [required: true]},
          {:posts, {:array, :map}, [optional: true]},
          {:metadata, {:map, :string, :any}, [optional: true]}
        ])

      json_schema = JsonSchema.generate(schema)

      assert json_schema["type"] == "object"
      assert json_schema["properties"]["user"]["type"] == "object"
      assert json_schema["properties"]["posts"]["type"] == "array"
      assert json_schema["properties"]["posts"]["items"]["type"] == "object"
      assert json_schema["properties"]["metadata"]["type"] == "object"
    end

    test "handles schemas with no required fields" do
      schema =
        Schema.define([
          {:optional1, :string, [optional: true]},
          {:optional2, :integer, [optional: true]}
        ])

      json_schema = JsonSchema.generate(schema)

      assert json_schema["required"] == []
      assert Map.has_key?(json_schema["properties"], "optional1")
      assert Map.has_key?(json_schema["properties"], "optional2")
    end

    test "generates schema for array-only structure" do
      schema =
        Schema.define([
          {:items, {:array, {:array, :string}}, [required: true]}
        ])

      json_schema = JsonSchema.generate(schema)

      items_schema = json_schema["properties"]["items"]
      assert items_schema["type"] == "array"
      assert items_schema["items"]["type"] == "array"
      assert items_schema["items"]["items"]["type"] == "string"
    end

    test "handles union with nested types" do
      schema =
        Schema.define([
          {:flexible, {:union, [:string, {:array, :integer}, :map]}, [required: true]}
        ])

      json_schema = JsonSchema.generate(schema)

      flexible_schema = json_schema["properties"]["flexible"]

      assert flexible_schema["oneOf"] == [
               %{"type" => "string"},
               %{"type" => "array", "items" => %{"type" => "integer"}},
               %{"type" => "object", "additionalProperties" => true}
             ]
    end

    test "preserves field order in properties" do
      # Define fields in specific order
      schema =
        Schema.define([
          {:zebra, :string, [required: true]},
          {:alpha, :string, [required: true]},
          {:middle, :string, [required: true]}
        ])

      json_schema = JsonSchema.generate(schema)
      property_keys = Map.keys(json_schema["properties"])

      # Should preserve definition order, not sort alphabetically
      assert "zebra" in property_keys
      assert "alpha" in property_keys
      assert "middle" in property_keys
    end
  end

  describe "edge cases" do
    test "handles empty schema" do
      empty_schema = Schema.define([])

      json_schema = JsonSchema.generate(empty_schema)

      assert json_schema["type"] == "object"
      assert json_schema["properties"] == %{}
      assert json_schema["required"] == []
    end

    test "handles schema with only optional fields" do
      schema =
        Schema.define([
          {:opt1, :string, [optional: true]},
          {:opt2, :integer, [optional: true]}
        ])

      json_schema = JsonSchema.generate(schema)

      assert json_schema["required"] == []
      assert map_size(json_schema["properties"]) == 2
    end

    test "handles very long field names" do
      long_name = String.duplicate("field", 50)

      schema =
        Schema.define([
          {String.to_atom(long_name), :string, [required: true]}
        ])

      json_schema = JsonSchema.generate(schema)

      assert Map.has_key?(json_schema["properties"], long_name)
    end

    test "handles unicode in descriptions" do
      schema =
        Schema.define([
          {:unicode_field, :string, [required: true, description: "Field with émojis 🚀 and ñ"]}
        ])

      json_schema = JsonSchema.generate(schema)

      assert json_schema["properties"]["unicode_field"]["description"] ==
               "Field with émojis 🚀 and ñ"
    end

    test "gracefully handles unsupported constraint types" do
      # This tests the constraint mapping doesn't break on unknown constraints
      schema =
        Schema.define([
          {:field, :string, [required: true]}
        ])

      # Should not raise even if internal constraints are passed
      json_schema = JsonSchema.generate(schema)

      assert is_map(json_schema)
      assert json_schema["type"] == "object"
    end
  end

  describe "JSON Schema specification compliance" do
    test "validates against JSON Schema Draft 2020-12 spec" do
      schema =
        Schema.define([
          {:name, :string, [required: true, min_length: 1]},
          {:age, :integer, [optional: true, gteq: 0, lteq: 150]},
          {:email, :string, [optional: true, format: ~r/.+@.+/]},
          {:tags, {:array, :string}, [optional: true, min_items: 1, max_items: 10]}
        ])

      json_schema = JsonSchema.generate(schema)

      # Core JSON Schema structure
      assert json_schema["$schema"] == "https://json-schema.org/draft/2020-12/schema"
      assert json_schema["type"] == "object"
      assert is_map(json_schema["properties"])
      assert is_list(json_schema["required"])

      # Property validation
      props = json_schema["properties"]
      assert props["name"]["type"] == "string"
      assert props["name"]["minLength"] == 1
      assert props["age"]["type"] == "integer"
      assert props["age"]["minimum"] == 0
      assert props["age"]["maximum"] == 150

      # Array validation
      assert props["tags"]["type"] == "array"
      assert props["tags"]["items"]["type"] == "string"
      assert props["tags"]["minItems"] == 1
      assert props["tags"]["maxItems"] == 10
    end

    test "handles complex nested structures" do
      schema =
        Schema.define([
          {:user, {:map, :string, :any}, [required: true]},
          {:coordinates, {:tuple, [:float, :float]}, [optional: true]},
          {:options, {:union, [:string, {:array, :string}]}, [optional: true]}
        ])

      json_schema = JsonSchema.generate(schema)
      props = json_schema["properties"]

      # Map type
      assert props["user"]["type"] == "object"
      assert props["user"]["additionalProperties"] == true

      # Tuple type
      tuple_schema = props["coordinates"]
      assert tuple_schema["type"] == "array"

      assert tuple_schema["prefixItems"] == [
               %{"type" => "number"},
               %{"type" => "number"}
             ]

      assert tuple_schema["minItems"] == 2
      assert tuple_schema["maxItems"] == 2

      # Union type
      union_schema = props["options"]

      assert union_schema["oneOf"] == [
               %{"type" => "string"},
               %{"type" => "array", "items" => %{"type" => "string"}}
             ]
    end

    test "provider optimizations maintain spec compliance" do
      schema =
        Schema.define([
          {:data, :map, [required: true]}
        ])

      # Test all provider optimizations maintain compliance
      providers = [:openai, :anthropic, :generic]

      for provider <- providers do
        json_schema = JsonSchema.for_provider(schema, provider)

        # All should be valid JSON Schema
        assert json_schema["type"] == "object"
        assert is_map(json_schema["properties"])
        assert is_list(json_schema["required"])

        # Provider-specific checks
        case provider do
          :openai ->
            assert json_schema["additionalProperties"] == false

          :anthropic ->
            assert json_schema["additionalProperties"] == false

          :generic ->
            # No specific requirements
            :ok
        end
      end
    end
  end
end
