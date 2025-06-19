defmodule Sinter.SchemaTest do
  use ExUnit.Case, async: true

  alias Sinter.{Schema, Validator}

  # Helper function for simple schemas
  defp simple_schema(fields \\ nil, opts \\ []) do
    fields =
      fields ||
        [
          {:name, :string, [required: true, min_length: 2]},
          {:age, :integer, [optional: true, gt: 0]}
        ]

    Schema.define(fields, opts)
  end

  describe "define/2" do
    test "creates basic schema with simple fields" do
      fields = [
        {:name, :string, [required: true]},
        {:age, :integer, [optional: true]}
      ]

      schema = Schema.define(fields)

      assert %Schema{} = schema
      assert is_map(schema.definition)
      assert is_map(schema.config)
    end

    test "handles field types and constraints" do
      fields = [
        {:name, :string, [required: true, min_length: 2, max_length: 50]},
        {:email, :string, [required: true, format: ~r/@/]},
        {:age, :integer, [optional: true, gt: 0, lt: 150]},
        {:tags, {:array, :string}, [optional: true, max_items: 10]}
      ]

      schema = Schema.define(fields)

      # Verify schema can be used for validation
      valid_data = %{
        "name" => "Alice",
        "email" => "alice@example.com",
        "age" => 30,
        "tags" => ["developer", "elixir"]
      }

      assert {:ok, _} = Validator.validate(schema, valid_data)
    end

    test "handles required vs optional fields" do
      fields = [
        {:required_field, :string, [required: true]},
        {:optional_field, :string, [optional: true]},
        # should default to required
        {:default_required, :string, []},
        {:explicit_optional, :string, [required: false]}
      ]

      schema = Schema.define(fields)

      # Test with only required fields
      minimal_data = %{"required_field" => "test", "default_required" => "test"}
      assert {:ok, _} = Validator.validate(schema, minimal_data)

      # Test missing required field
      invalid_data = %{"optional_field" => "test"}
      assert {:error, _} = Validator.validate(schema, invalid_data)
    end

    test "handles default values" do
      fields = [
        {:name, :string, [required: true]},
        {:active, :boolean, [optional: true, default: true]},
        {:count, :integer, [optional: true, default: 0]}
      ]

      schema = Schema.define(fields)

      data = %{"name" => "test"}
      assert {:ok, result} = Validator.validate(schema, data)

      # Defaults should be applied
      assert result[:active] == true
      assert result[:count] == 0
    end

    test "accepts schema configuration options" do
      fields = [
        {:name, :string, [required: true]}
      ]

      schema =
        Schema.define(fields,
          title: "Test Schema",
          description: "A test schema",
          strict: true
        )

      assert schema.config.title == "Test Schema"
      assert schema.config.description == "A test schema"
      assert schema.config.strict == true
    end

    test "accepts post-validation function" do
      post_validate_fn = fn data ->
        if Map.get(data, :name) == "invalid" do
          {:error, "Invalid name"}
        else
          {:ok, data}
        end
      end

      fields = [
        {:name, :string, [required: true]}
      ]

      schema = Schema.define(fields, post_validate: post_validate_fn)

      # Valid case
      assert {:ok, _} = Validator.validate(schema, %{name: "valid"})

      # Invalid case (caught by post-validation)
      assert {:error, _} = Validator.validate(schema, %{name: "invalid"})
    end

    test "normalizes field specifications" do
      # Test various field option formats
      fields = [
        {:simple, :string, [required: true]},
        {:with_multiple_opts, :integer, [required: true, gt: 0, lt: 100]},
        {:minimal, :boolean, []},
        {:complex_type, {:array, :string}, [optional: true, min_items: 1]}
      ]

      schema = Schema.define(fields)

      # Should not raise and should create valid schema
      assert %Schema{} = schema
    end

    test "handles complex nested field structures" do
      fields = [
        {:user, :map,
         [
           required: true
         ]}
      ]

      schema = Schema.define(fields)

      valid_data = %{
        "user" => %{
          "name" => "Alice"
        }
      }

      assert {:ok, _} = Validator.validate(schema, valid_data)
    end

    test "raises on invalid field specifications" do
      assert_raise ArgumentError, fn ->
        Schema.define([
          {:invalid_field, :invalid_type, []}
        ])
      end
    end

    test "raises on malformed constraints" do
      assert_raise ArgumentError, fn ->
        Schema.define([
          {:field, :string, [invalid_constraint: "bad"]}
        ])
      end
    end

    test "raises on invalid post-validation function" do
      assert_raise ArgumentError, fn ->
        Schema.define(
          [
            {:field, :string, [required: true]}
          ],
          post_validate: "not_a_function"
        )
      end
    end
  end

  describe "use_schema macro" do
    test "basic macro expansion" do
      defmodule TestSchema1 do
        use Sinter.Schema

        use_schema do
          option :title, "Test Schema"

          field :name, :string, required: true
          field :age, :integer, optional: true
        end
      end

      schema = TestSchema1.schema()
      assert %Schema{} = schema
      assert schema.config.title == "Test Schema"

      # Should be usable for validation
      assert {:ok, _} = Validator.validate(schema, %{"name" => "test"})
    end

    test "field and option accumulation" do
      defmodule TestSchema2 do
        use Sinter.Schema

        use_schema do
          option :title, "Multi-field Schema"
          option :strict, true

          field :field1, :string, required: true
          field :field2, :integer, optional: true, gt: 0
          field :field3, :boolean, optional: true, default: false
        end
      end

      schema = TestSchema2.schema()

      # Test that all options are set
      assert schema.config.title == "Multi-field Schema"
      assert schema.config.strict == true

      # Test that all fields work
      data = %{"field1" => "test", "field2" => 5}
      assert {:ok, result} = Validator.validate(schema, data)
      # default applied
      assert result[:field3] == false
    end

    test "generates schema/0 function" do
      defmodule TestSchema3 do
        use Sinter.Schema

        use_schema do
          field :test, :string, required: true
        end
      end

      # Should have schema/0 function
      assert function_exported?(TestSchema3, :schema, 0)

      schema = TestSchema3.schema()
      assert %Schema{} = schema
    end

    test "DSL syntax with various field types" do
      defmodule TestSchema4 do
        use Sinter.Schema

        use_schema do
          option :title, "Complex Types"

          field :simple_string, :string, required: true
          field :number_list, {:array, :integer}, optional: true
          field :user_data, :map, required: true
          field :choice, :atom, required: true, choices: [:a, :b, :c]
          field :coordinates, {:tuple, [:float, :float]}, optional: true
        end
      end

      schema = TestSchema4.schema()

      valid_data = %{
        "simple_string" => "hello",
        "number_list" => [1, 2, 3],
        "user_data" => %{"key" => "value"},
        "choice" => :a,
        "coordinates" => {1.0, 2.0}
      }

      assert {:ok, _} = Validator.validate(schema, valid_data)
    end

    test "block evaluation order" do
      # This test ensures that the macro processes the block in the correct order
      defmodule TestSchema5 do
        use Sinter.Schema

        use_schema do
          field :first, :string, required: true
          option :title, "Ordered Schema"
          field :second, :integer, optional: true
          option :strict, false
          field :third, :boolean, optional: true
        end
      end

      schema = TestSchema5.schema()

      # Should have all options set
      assert schema.config.title == "Ordered Schema"
      assert schema.config.strict == false

      # Should handle all fields
      data = %{"first" => "test", "second" => 42, "third" => true}
      assert {:ok, _} = Validator.validate(schema, data)
    end
  end

  describe "schema utility functions" do
    test "fields/1 returns correct field map" do
      schema = simple_schema()
      fields = Schema.fields(schema)

      assert is_map(fields)
      assert Map.has_key?(fields, :name)
      assert Map.has_key?(fields, :age)
    end

    test "required_fields/1 returns only required fields" do
      fields = [
        {:required1, :string, [required: true]},
        {:optional1, :string, [optional: true]},
        {:required2, :integer, [required: true]},
        {:optional2, :boolean, [optional: true]}
      ]

      schema = Schema.define(fields)
      required = Schema.required_fields(schema)

      assert :required1 in required
      assert :required2 in required
      refute :optional1 in required
      refute :optional2 in required
    end

    test "optional_fields/1 returns only optional fields" do
      fields = [
        {:required1, :string, [required: true]},
        {:optional1, :string, [optional: true]},
        {:required2, :integer, [required: true]},
        {:optional2, :boolean, [optional: true]}
      ]

      schema = Schema.define(fields)
      optional = Schema.optional_fields(schema)

      assert :optional1 in optional
      assert :optional2 in optional
      refute :required1 in optional
      refute :required2 in optional
    end

    test "strict?/1 returns correct strict setting" do
      strict_schema = Schema.define([], strict: true)
      non_strict_schema = Schema.define([], strict: false)
      default_schema = Schema.define([])

      assert Schema.strict?(strict_schema) == true
      assert Schema.strict?(non_strict_schema) == false
      # default
      assert Schema.strict?(default_schema) == false
    end

    test "post_validate_fn/1 returns post-validation function" do
      post_fn = fn data -> {:ok, data} end
      schema_with_post = Schema.define([], post_validate: post_fn)
      schema_without_post = Schema.define([])

      assert Schema.post_validate_fn(schema_with_post) == post_fn
      assert Schema.post_validate_fn(schema_without_post) == nil
    end

    test "info/1 generates summary information" do
      schema =
        Schema.define(
          [
            {:name, :string, [required: true]},
            {:age, :integer, [optional: true]},
            {:tags, {:array, :string}, [optional: true]}
          ],
          title: "User Schema",
          description: "User information"
        )

      info = Schema.info(schema)

      assert is_map(info)
      assert info.title == "User Schema"
      assert info.description == "User information"
      assert info.field_count == 3
      assert info.required_count == 1
      assert info.optional_count == 2
      assert is_list(info.field_names)
      assert :name in info.field_names
      assert :age in info.field_names
      assert :tags in info.field_names
    end

    test "info/1 handles schema without metadata" do
      schema =
        Schema.define([
          {:field1, :string, [required: true]}
        ])

      info = Schema.info(schema)

      assert info.title == nil
      assert info.description == nil
      assert info.field_count == 1
      assert info.required_count == 1
      assert info.optional_count == 0
    end
  end

  describe "complex schema scenarios" do
    test "schema with various array types" do
      fields = [
        {:strings, {:array, :string}, [required: true, min_items: 1, max_items: 10]},
        {:numbers, {:array, :integer}, [optional: true]},
        {:mixed_array, {:array, :any}, [optional: true]},
        {:nested_arrays, {:array, {:array, :string}}, [optional: true]}
      ]

      schema = Schema.define(fields)

      valid_data = %{
        "strings" => ["hello", "world"],
        "numbers" => [1, 2, 3],
        "mixed_array" => ["string", 42, true],
        "nested_arrays" => [["a", "b"], ["c", "d"]]
      }

      assert {:ok, _} = Validator.validate(schema, valid_data)
    end

    test "schema with union types" do
      fields = [
        {:id, {:union, [:string, :integer]}, [required: true]},
        {:value, {:union, [:string, :integer, :float]}, [required: true]},
        {:optional_union, {:union, [:string, :boolean]}, [optional: true]},
        {:complex_union, {:union, [:string, {:array, :integer}]}, [optional: true]}
      ]

      schema = Schema.define(fields)

      # Test various valid union combinations
      test_cases = [
        %{"id" => "string_id", "value" => "string_value"},
        %{"id" => 42, "value" => 123},
        %{"id" => "mixed", "value" => 3.14},
        %{"id" => 999, "value" => "mixed_types"}
      ]

      for data <- test_cases do
        assert {:ok, _} = Validator.validate(schema, data)
      end
    end

    test "schema with tuple types" do
      fields = [
        {:coordinates, {:tuple, [:float, :float]}, [required: true]},
        {:rgb_color, {:tuple, [:integer, :integer, :integer]}, [required: true]},
        {:mixed_tuple, {:tuple, [:string, :integer, :boolean]}, [optional: true]},
        {:nested_tuple, {:tuple, [:string, {:tuple, [:integer, :integer]}]}, [optional: true]}
      ]

      schema = Schema.define(fields)

      valid_data = %{
        "coordinates" => {1.5, 2.5},
        "rgb_color" => {255, 128, 0}
      }

      assert {:ok, _} = Validator.validate(schema, valid_data)
    end

    test "empty schema" do
      schema = Schema.define([])

      # Should accept empty data
      assert {:ok, _} = Validator.validate(schema, %{})

      # Should also accept data if not strict
      assert {:ok, _} = Validator.validate(schema, %{"extra" => "field"})
    end

    test "schema with post-validation hook" do
      post_validate_fn = fn data ->
        if Map.get(data, :password) == Map.get(data, :password_confirmation) do
          {:ok, data}
        else
          {:error, "Passwords do not match"}
        end
      end

      fields = [
        {:password, :string, [required: true, min_length: 8]},
        {:password_confirmation, :string, [required: true]}
      ]

      schema = Schema.define(fields, post_validate: post_validate_fn)

      # Valid case - passwords match
      valid_data = %{
        "password" => "secret123",
        "password_confirmation" => "secret123"
      }

      assert {:ok, _} = Validator.validate(schema, valid_data)

      # Invalid case - passwords don't match
      invalid_data = %{
        "password" => "secret123",
        "password_confirmation" => "different"
      }

      assert {:error, _} = Validator.validate(schema, invalid_data)
    end
  end
end
