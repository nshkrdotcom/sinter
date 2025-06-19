defmodule Sinter.TypesTest do
  use ExUnit.Case, async: true

  alias Sinter.Types

  # Helper functions
  defp assert_invalid(result) do
    case result do
      {:ok, data} -> flunk("Expected validation to fail, got success: #{inspect(data)}")
      {:error, errors} -> errors
    end
  end

  defp assert_error_with_code(errors, code) when is_list(errors) do
    matching_error = Enum.find(errors, fn error -> error.code == code end)

    if matching_error do
      matching_error
    else
      flunk("Expected error with code #{inspect(code)}, got: #{inspect(errors)}")
    end
  end

  describe "validate/3 - primitive types" do
    test "validates basic string type" do
      assert {:ok, "hello"} = Types.validate(:string, "hello", [])
      assert {:ok, ""} = Types.validate(:string, "", [])

      errors = assert_invalid(Types.validate(:string, 42, []))
      assert_error_with_code(errors, :type)

      errors = assert_invalid(Types.validate(:string, :atom, []))
      assert_error_with_code(errors, :type)
    end

    test "validates basic integer type" do
      assert {:ok, 42} = Types.validate(:integer, 42, [])
      assert {:ok, -10} = Types.validate(:integer, -10, [])
      assert {:ok, 0} = Types.validate(:integer, 0, [])

      errors = assert_invalid(Types.validate(:integer, "42", []))
      assert_error_with_code(errors, :type)

      errors = assert_invalid(Types.validate(:integer, 3.14, []))
      assert_error_with_code(errors, :type)
    end

    test "validates basic float type" do
      assert {:ok, 3.14} = Types.validate(:float, 3.14, [])
      assert {:ok, 42.0} = Types.validate(:float, 42.0, [])
      assert {:ok, -2.5} = Types.validate(:float, -2.5, [])

      errors = assert_invalid(Types.validate(:float, 42, []))
      assert_error_with_code(errors, :type)

      errors = assert_invalid(Types.validate(:float, "3.14", []))
      assert_error_with_code(errors, :type)
    end

    test "validates basic boolean type" do
      assert {:ok, true} = Types.validate(:boolean, true, [])
      assert {:ok, false} = Types.validate(:boolean, false, [])

      errors = assert_invalid(Types.validate(:boolean, "true", []))
      assert_error_with_code(errors, :type)

      errors = assert_invalid(Types.validate(:boolean, 1, []))
      assert_error_with_code(errors, :type)
    end

    test "validates basic atom type" do
      assert {:ok, :hello} = Types.validate(:atom, :hello, [])
      assert {:ok, :test} = Types.validate(:atom, :test, [])

      errors = assert_invalid(Types.validate(:atom, "hello", []))
      assert_error_with_code(errors, :type)

      errors = assert_invalid(Types.validate(:atom, 42, []))
      assert_error_with_code(errors, :type)
    end

    test "validates any type (accepts everything)" do
      assert {:ok, "string"} = Types.validate(:any, "string", [])
      assert {:ok, 42} = Types.validate(:any, 42, [])
      assert {:ok, true} = Types.validate(:any, true, [])
      assert {:ok, %{}} = Types.validate(:any, %{}, [])
      assert {:ok, []} = Types.validate(:any, [], [])
      assert {:ok, :atom} = Types.validate(:any, :atom, [])
    end

    test "validates map type" do
      assert {:ok, %{"key" => "value"}} = Types.validate(:map, %{"key" => "value"}, [])
      assert {:ok, %{}} = Types.validate(:map, %{}, [])

      errors = assert_invalid(Types.validate(:map, "not a map", []))
      assert_error_with_code(errors, :type)

      errors = assert_invalid(Types.validate(:map, [], []))
      assert_error_with_code(errors, :type)
    end
  end

  describe "validate/3 - array types" do
    test "validates array types" do
      # String array
      assert {:ok, ["a", "b", "c"]} = Types.validate({:array, :string}, ["a", "b", "c"], [])
      assert {:ok, []} = Types.validate({:array, :string}, [], [])

      # Integer array
      assert {:ok, [1, 2, 3]} = Types.validate({:array, :integer}, [1, 2, 3], [])

      # Mixed type array (any)
      assert {:ok, ["string", 42, true]} = Types.validate({:array, :any}, ["string", 42, true], [])

      # Invalid array type
      errors = assert_invalid(Types.validate({:array, :string}, "not an array", []))
      assert_error_with_code(errors, :type)

      # Invalid array items
      errors = assert_invalid(Types.validate({:array, :integer}, [1, "not_integer", 3], []))
      error = assert_error_with_code(errors, :type)
      assert error.path == [1]
    end

    test "generates proper error paths for nested arrays" do
      nested_array_type = {:array, {:array, :string}}
      invalid_nested = [["valid"], ["invalid", 123]]

      errors = assert_invalid(Types.validate(nested_array_type, invalid_nested, []))
      error = assert_error_with_code(errors, :type)
      assert error.path == [1, 1]
    end
  end

  describe "validate/3 - union types" do
    test "validates union types" do
      union_type = {:union, [:string, :integer]}

      # Valid string
      assert {:ok, "hello"} = Types.validate(union_type, "hello", [])

      # Valid integer
      assert {:ok, 42} = Types.validate(union_type, 42, [])

      # Invalid type (not in union)
      errors = assert_invalid(Types.validate(union_type, true, []))
      assert_error_with_code(errors, :type)

      errors = assert_invalid(Types.validate(union_type, 3.14, []))
      assert_error_with_code(errors, :type)
    end

    test "validates union types with priority order" do
      # First matching type should be used
      union_type = {:union, [:string, :any]}

      # String should match as string, not as any
      assert {:ok, "hello"} = Types.validate(union_type, "hello", [])

      # Non-string should match as any
      assert {:ok, 42} = Types.validate(union_type, 42, [])
    end
  end

  describe "validate/3 - tuple types" do
    test "validates tuple types" do
      tuple_type = {:tuple, [:string, :integer]}

      # Valid tuple
      assert {:ok, {"hello", 42}} = Types.validate(tuple_type, {"hello", 42}, [])

      # Invalid tuple type
      errors = assert_invalid(Types.validate(tuple_type, "not a tuple", []))
      assert_error_with_code(errors, :type)

      # Wrong tuple size
      errors = assert_invalid(Types.validate(tuple_type, {"hello"}, []))
      assert_error_with_code(errors, :tuple_size)

      errors = assert_invalid(Types.validate(tuple_type, {"hello", 42, "extra"}, []))
      assert_error_with_code(errors, :tuple_size)

      # Invalid tuple element types
      errors = assert_invalid(Types.validate(tuple_type, {42, "hello"}, []))
      assert length(errors) == 2
      assert Enum.any?(errors, fn error -> error.path == [0] and error.code == :type end)
      assert Enum.any?(errors, fn error -> error.path == [1] and error.code == :type end)
    end

    test "validates nested tuple types" do
      nested_tuple_type = {:tuple, [:string, {:tuple, [:integer, :integer]}]}
      valid_tuple = {"valid", {1, 2}}
      invalid_tuple = {"valid", {"invalid", 42}}

      assert {:ok, ^valid_tuple} = Types.validate(nested_tuple_type, valid_tuple, [])

      errors = assert_invalid(Types.validate(nested_tuple_type, invalid_tuple, []))
      error = assert_error_with_code(errors, :type)
      assert error.path == [1, 0]
    end
  end

  describe "validate/3 - map with key/value types" do
    test "validates map with key/value types" do
      map_type = {:map, :string, :integer}

      # Valid map
      assert {:ok, %{"a" => 1, "b" => 2}} = Types.validate(map_type, %{"a" => 1, "b" => 2}, [])

      # Invalid key type
      errors = assert_invalid(Types.validate(map_type, %{:atom_key => 1}, []))
      assert_error_with_code(errors, :type)

      # Invalid value type
      errors = assert_invalid(Types.validate(map_type, %{"key" => "not_integer"}, []))
      assert_error_with_code(errors, :type)
    end
  end

  describe "coerce/2" do
    test "coerces string from various types" do
      assert {:ok, "hello"} = Types.coerce(:string, :hello)
      assert {:ok, "42"} = Types.coerce(:string, 42)
      assert {:ok, "3.14"} = Types.coerce(:string, 3.14)
      assert {:ok, "true"} = Types.coerce(:string, true)
      assert {:ok, "false"} = Types.coerce(:string, false)

      # Already a string
      assert {:ok, "already"} = Types.coerce(:string, "already")
    end

    test "coerces integer from string" do
      assert {:ok, 42} = Types.coerce(:integer, "42")
      assert {:ok, -10} = Types.coerce(:integer, "-10")
      assert {:ok, 0} = Types.coerce(:integer, "0")

      # Already an integer
      assert {:ok, 42} = Types.coerce(:integer, 42)

      # Invalid coercion
      errors = assert_invalid(Types.coerce(:integer, "not_a_number"))
      assert_error_with_code(errors, :coercion)

      errors = assert_invalid(Types.coerce(:integer, "3.14"))
      assert_error_with_code(errors, :coercion)
    end

    test "coerces float from string and integer" do
      assert {:ok, 3.14} = Types.coerce(:float, "3.14")
      assert {:ok, 42.0} = Types.coerce(:float, "42")
      assert {:ok, 42.0} = Types.coerce(:float, 42)
      assert {:ok, -2.5} = Types.coerce(:float, "-2.5")

      # Already a float
      assert {:ok, 3.14} = Types.coerce(:float, 3.14)

      # Invalid coercion
      errors = assert_invalid(Types.coerce(:float, "not_a_number"))
      assert_error_with_code(errors, :coercion)
    end

    test "coerces boolean from string" do
      assert {:ok, true} = Types.coerce(:boolean, "true")
      assert {:ok, false} = Types.coerce(:boolean, "false")

      # Already a boolean
      assert {:ok, true} = Types.coerce(:boolean, true)
      assert {:ok, false} = Types.coerce(:boolean, false)
    end

    test "coerces atom from string (existing atoms only)" do
      # These atoms should already exist from other parts of the test
      assert {:ok, :hello} = Types.coerce(:atom, "hello")
      assert {:ok, :test} = Types.coerce(:atom, "test")

      # Already an atom
      assert {:ok, :existing} = Types.coerce(:atom, :existing)

      # Non-existing atom should fail
      errors = assert_invalid(Types.coerce(:atom, "definitely_not_an_existing_atom_12345"))
      assert_error_with_code(errors, :coercion)
    end

    test "coerces array elements recursively" do
      # String array from mixed types
      assert {:ok, ["1", "2", "3"]} = Types.coerce({:array, :string}, [1, 2, 3])

      # Integer array from strings
      assert {:ok, [1, 2, 3]} = Types.coerce({:array, :integer}, ["1", "2", "3"])

      # Partial coercion failure
      errors = assert_invalid(Types.coerce({:array, :integer}, ["1", "not_a_number", "3"]))
      assert_error_with_code(errors, :coercion)
    end

    test "handles union type coercion with priority" do
      union_type = {:union, [:integer, :string]}

      # Should try integer first, then string
      assert {:ok, 42} = Types.coerce(union_type, "42")
      assert {:ok, "not_a_number"} = Types.coerce(union_type, "not_a_number")

      # Already correct type
      assert {:ok, 123} = Types.coerce(union_type, 123)
      assert {:ok, "hello"} = Types.coerce(union_type, "hello")
    end

    test "preserves values that don't need coercion" do
      # No coercion needed
      assert {:ok, "string"} = Types.coerce(:string, "string")
      assert {:ok, 42} = Types.coerce(:integer, 42)
      assert {:ok, 3.14} = Types.coerce(:float, 3.14)
      assert {:ok, true} = Types.coerce(:boolean, true)
      assert {:ok, :atom} = Types.coerce(:atom, :atom)
      assert {:ok, %{}} = Types.coerce(:map, %{})
      assert {:ok, []} = Types.coerce({:array, :any}, [])
    end
  end

  describe "to_json_schema/1" do
    test "converts basic types to JSON Schema" do
      assert %{"type" => "string"} = Types.to_json_schema(:string)
      assert %{"type" => "integer"} = Types.to_json_schema(:integer)
      assert %{"type" => "number"} = Types.to_json_schema(:float)
      assert %{"type" => "boolean"} = Types.to_json_schema(:boolean)
      # any type has no restrictions
      assert %{} = Types.to_json_schema(:any)
    end

    test "converts array types to JSON Schema" do
      array_type = {:array, :string}
      schema = Types.to_json_schema(array_type)

      assert schema["type"] == "array"
      assert schema["items"] == %{"type" => "string"}

      # Nested array
      nested_array = {:array, {:array, :integer}}
      nested_schema = Types.to_json_schema(nested_array)

      assert nested_schema["type"] == "array"
      assert nested_schema["items"]["type"] == "array"
      assert nested_schema["items"]["items"]["type"] == "integer"
    end

    test "converts map types to JSON Schema" do
      map_schema = Types.to_json_schema(:map)
      assert map_schema["type"] == "object"

      # Map with key/value types
      typed_map = {:map, :string, :integer}
      schema = Types.to_json_schema(typed_map)
      assert schema["type"] == "object"
      assert schema["additionalProperties"] == %{"type" => "integer"}
    end

    test "converts union types to JSON Schema oneOf" do
      union_type = {:union, [:string, :integer]}
      schema = Types.to_json_schema(union_type)

      assert schema["oneOf"] == [
               %{"type" => "string"},
               %{"type" => "integer"}
             ]
    end

    test "converts tuple types to JSON Schema array with prefixItems" do
      tuple_type = {:tuple, [:string, :integer, :boolean]}
      schema = Types.to_json_schema(tuple_type)

      assert schema["type"] == "array"

      assert schema["prefixItems"] == [
               %{"type" => "string"},
               %{"type" => "integer"},
               %{"type" => "boolean"}
             ]

      # no additional items allowed
      assert schema["items"] == false
      assert schema["minItems"] == 3
      assert schema["maxItems"] == 3
    end

    test "handles nested type conversions" do
      # Array of objects
      nested_type = {:array, :map}
      schema = Types.to_json_schema(nested_type)

      assert schema["type"] == "array"
      assert schema["items"]["type"] == "object"

      # Union with complex types
      complex_union = {:union, [:string, {:array, :integer}]}
      schema = Types.to_json_schema(complex_union)

      assert schema["oneOf"] == [
               %{"type" => "string"},
               %{"type" => "array", "items" => %{"type" => "integer"}}
             ]
    end
  end

  describe "error handling" do
    test "provides descriptive error messages" do
      errors = assert_invalid(Types.validate(:string, 42, []))
      error = List.first(errors)
      assert error.message =~ "expected string"

      errors = assert_invalid(Types.validate(:integer, "hello", []))
      error = List.first(errors)
      assert error.message =~ "expected integer"
    end

    test "aggregates multiple errors correctly" do
      # Array with multiple invalid items
      errors = assert_invalid(Types.validate({:array, :integer}, ["not", "integers", 3], []))

      type_errors = Enum.filter(errors, fn error -> error.code == :type end)
      assert length(type_errors) == 2

      # Check error paths
      paths = Enum.map(type_errors, & &1.path)
      assert [0] in paths
      assert [1] in paths
      # Index 2 should be valid, no error
    end

    test "generates proper error paths for nested structures" do
      # Nested array validation
      nested_array_type = {:array, {:array, :string}}
      invalid_nested = [["valid"], ["invalid", 123]]

      errors = assert_invalid(Types.validate(nested_array_type, invalid_nested, []))
      error = assert_error_with_code(errors, :type)
      assert error.path == [1, 1]

      # Nested tuple validation
      nested_tuple_type = {:tuple, [:string, {:tuple, [:integer, :integer]}]}
      invalid_tuple = {"valid", {"invalid", 42}}

      errors = assert_invalid(Types.validate(nested_tuple_type, invalid_tuple, []))
      error = assert_error_with_code(errors, :type)
      assert error.path == [1, 0]
    end
  end
end
