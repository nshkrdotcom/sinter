defmodule SinterTest do
  use ExUnit.Case
  doctest Sinter

  alias Sinter.{Error, Schema, Validator}

  describe "basic functionality" do
    test "schema creation and validation works" do
      # Create a simple schema
      schema =
        Schema.define([
          {:name, :string, [required: true, min_length: 2]},
          {:age, :integer, [optional: true, gt: 0]}
        ])

      # Valid data should pass
      assert {:ok, validated} = Validator.validate(schema, %{name: "Alice", age: 30})
      assert validated.name == "Alice"
      assert validated.age == 30

      # Invalid data should fail
      assert {:error, errors} = Validator.validate(schema, %{name: "A", age: -5})
      assert length(errors) == 2
    end

    test "type validation works" do
      # String validation
      assert {:ok, "hello"} = Sinter.validate_type(:string, "hello")
      assert {:error, [%Error{}]} = Sinter.validate_type(:string, 123)

      # Integer validation with coercion
      assert {:ok, 42} = Sinter.validate_type(:integer, "42", coerce: true)
      assert {:ok, 42} = Sinter.validate_type(:integer, 42)
    end

    test "array validation works" do
      array_type = {:array, :integer}

      assert {:ok, [1, 2, 3]} = Sinter.validate_type(array_type, [1, 2, 3])
      assert {:error, [%Error{}]} = Sinter.validate_type(array_type, [1, "two", 3])
    end

    test "constraint validation works" do
      # String length constraints
      constraints = [min_length: 3, max_length: 10]
      assert {:ok, "hello"} = Sinter.validate_type(:string, "hello", constraints: constraints)
      assert {:error, [%Error{}]} = Sinter.validate_type(:string, "hi", constraints: constraints)

      assert {:error, [%Error{}]} =
               Sinter.validate_type(:string, "this is too long", constraints: constraints)

      # Numeric constraints
      constraints = [gt: 0, lt: 100]
      assert {:ok, 50} = Sinter.validate_type(:integer, 50, constraints: constraints)
      assert {:error, [%Error{}]} = Sinter.validate_type(:integer, -1, constraints: constraints)
      assert {:error, [%Error{}]} = Sinter.validate_type(:integer, 100, constraints: constraints)
    end

    test "error formatting works" do
      error = Error.new([:user, :email], :format, "invalid email format")

      formatted = Error.format(error)
      assert formatted == "user.email: invalid email format"

      formatted_no_path = Error.format(error, include_path: false)
      assert formatted_no_path == "invalid email format"
    end

    test "batch validation works" do
      validations = [
        {:string, "hello"},
        {:integer, 42},
        {:boolean, true}
      ]

      assert {:ok, ["hello", 42, true]} = Sinter.validate_many(validations)

      # With errors
      validations_with_errors = [
        {:string, "hello"},
        {:integer, "not a number"},
        {:boolean, true}
      ]

      assert {:error, error_map} = Sinter.validate_many(validations_with_errors)
      # Second item (index 1) should have errors
      assert Map.has_key?(error_map, 1)
    end
  end
end
