defmodule SinterTest do
  use ExUnit.Case, async: true

  alias Sinter.Schema

  describe "validate_type/3 - single type validation" do
    test "validates basic types successfully" do
      assert {:ok, "hello"} = Sinter.validate_type(:string, "hello")
      assert {:ok, 42} = Sinter.validate_type(:integer, 42)
      assert {:ok, 3.14} = Sinter.validate_type(:float, 3.14)
      assert {:ok, true} = Sinter.validate_type(:boolean, true)
      assert {:ok, :atom} = Sinter.validate_type(:atom, :atom)
      assert {:ok, %{}} = Sinter.validate_type(:map, %{})
      assert {:ok, "anything"} = Sinter.validate_type(:any, "anything")
    end

    test "rejects invalid types" do
      assert {:error, [error]} = Sinter.validate_type(:string, 42)
      assert error.code == :type
      assert error.path == []

      assert {:error, [error]} = Sinter.validate_type(:integer, "42")
      assert error.code == :type
    end

    test "validates array types" do
      assert {:ok, ["a", "b"]} = Sinter.validate_type({:array, :string}, ["a", "b"])
      assert {:ok, [1, 2, 3]} = Sinter.validate_type({:array, :integer}, [1, 2, 3])
      assert {:ok, []} = Sinter.validate_type({:array, :any}, [])

      # Invalid array element
      assert {:error, [error]} = Sinter.validate_type({:array, :string}, ["valid", 123])
      assert error.code == :type
      assert error.path == [1]
    end

    test "validates union types" do
      union_type = {:union, [:string, :integer]}

      assert {:ok, "hello"} = Sinter.validate_type(union_type, "hello")
      assert {:ok, 42} = Sinter.validate_type(union_type, 42)

      assert {:error, [error]} = Sinter.validate_type(union_type, true)
      assert error.code == :type
    end

    test "validates tuple types" do
      tuple_type = {:tuple, [:string, :integer]}

      assert {:ok, {"hello", 42}} = Sinter.validate_type(tuple_type, {"hello", 42})

      # Wrong tuple size
      assert {:error, [error]} = Sinter.validate_type(tuple_type, {"hello"})
      assert error.code == :tuple_size

      # Wrong element type
      assert {:error, errors} = Sinter.validate_type(tuple_type, {42, "hello"})
      assert length(errors) == 2
    end

    test "applies constraints through options" do
      # String length constraint
      assert {:ok, "hello"} = Sinter.validate_type(:string, "hello", min_length: 3)
      assert {:error, [error]} = Sinter.validate_type(:string, "hi", min_length: 3)
      assert error.code == :min_length

      # Numeric constraint
      assert {:ok, 50} = Sinter.validate_type(:integer, 50, gt: 0, lt: 100)
      assert {:error, [error]} = Sinter.validate_type(:integer, 0, gt: 0)
      assert error.code == :gt

      # Format constraint
      assert {:ok, "test@example.com"} =
               Sinter.validate_type(:string, "test@example.com", format: ~r/@/)

      assert {:error, [error]} = Sinter.validate_type(:string, "invalid", format: ~r/@/)
      assert error.code == :format
    end

    test "applies constraints through explicit constraints option" do
      constraints = [min_length: 5, format: ~r/^[A-Z]/]

      assert {:ok, "HELLO"} = Sinter.validate_type(:string, "HELLO", constraints: constraints)

      # Too short
      assert {:error, [error]} = Sinter.validate_type(:string, "HI", constraints: constraints)
      assert error.code == :min_length

      # Wrong format
      assert {:error, [error]} = Sinter.validate_type(:string, "hello", constraints: constraints)
      assert error.code == :format
    end

    test "enables type coercion when requested" do
      assert {:ok, 42} = Sinter.validate_type(:integer, "42", coerce: true)
      assert {:ok, 3.14} = Sinter.validate_type(:float, "3.14", coerce: true)
      assert {:ok, true} = Sinter.validate_type(:boolean, "true", coerce: true)
      assert {:ok, "hello"} = Sinter.validate_type(:string, :hello, coerce: true)

      # Coercion with constraints
      assert {:ok, 42} = Sinter.validate_type(:integer, "42", coerce: true, gt: 0)
      assert {:error, [error]} = Sinter.validate_type(:integer, "0", coerce: true, gt: 0)
      assert error.code == :gt
    end

    test "handles coercion failures gracefully" do
      assert {:error, [error]} = Sinter.validate_type(:integer, "not_a_number", coerce: true)
      assert error.code == :coercion
      assert error.path == []
    end

    test "strips temporary field names from error paths" do
      # This tests that the internal __temp__ field is removed from error paths
      assert {:error, [error]} = Sinter.validate_type(:string, 123)
      # Should not contain [:__temp__]
      assert error.path == []

      # For array validation
      assert {:error, [error]} = Sinter.validate_type({:array, :string}, ["valid", 123])
      # Should not contain [:__temp__, 1]
      assert error.path == [1]
    end
  end

  describe "validate_value/4 - named field validation" do
    test "validates named fields successfully" do
      assert {:ok, "Alice"} = Sinter.validate_value(:name, :string, "Alice")
      assert {:ok, 30} = Sinter.validate_value(:age, :integer, 30)
    end

    test "includes field name in error paths" do
      assert {:error, [error]} = Sinter.validate_value(:email, :string, 123)
      assert error.code == :type
      assert error.path == [:email]

      # For nested structures
      assert {:error, [error]} = Sinter.validate_value(:tags, {:array, :string}, ["valid", 123])
      assert error.code == :type
      assert error.path == [:tags, 1]
    end

    test "applies constraints to named fields" do
      assert {:ok, "alice@example.com"} =
               Sinter.validate_value(
                 :email,
                 :string,
                 "alice@example.com",
                 format: ~r/@/
               )

      assert {:error, [error]} =
               Sinter.validate_value(
                 :email,
                 :string,
                 "invalid",
                 format: ~r/@/
               )

      assert error.code == :format
      assert error.path == [:email]
    end

    test "supports coercion for named fields" do
      assert {:ok, 42} = Sinter.validate_value(:count, :integer, "42", coerce: true)

      assert {:error, [error]} = Sinter.validate_value(:count, :integer, "invalid", coerce: true)
      assert error.code == :coercion
      assert error.path == [:count]
    end

    test "combines constraints and coercion" do
      assert {:ok, 42} =
               Sinter.validate_value(
                 :score,
                 :integer,
                 "42",
                 coerce: true,
                 gt: 0,
                 lt: 100
               )

      # Constraint violation after coercion
      assert {:error, [error]} =
               Sinter.validate_value(
                 :score,
                 :integer,
                 "150",
                 coerce: true,
                 lt: 100
               )

      assert error.code == :lt
      assert error.path == [:score]
    end
  end

  describe "validate_many/2 - batch validation" do
    test "validates multiple type/value pairs" do
      pairs = [
        {:string, "hello"},
        {:integer, 42},
        {:boolean, true}
      ]

      assert {:ok, ["hello", 42, true]} = Sinter.validate_many(pairs)
    end

    test "validates named type/value pairs" do
      pairs = [
        {:name, :string, "Alice"},
        {:age, :integer, 30},
        {:email, :string, "alice@example.com"}
      ]

      assert {:ok, ["Alice", 30, "alice@example.com"]} = Sinter.validate_many(pairs)
    end

    test "validates pairs with individual constraints" do
      pairs = [
        {:email, :string, "alice@example.com", [format: ~r/@/]},
        {:score, :integer, 85, [gt: 0, lt: 100]},
        {:name, :string, "Alice", [min_length: 2]}
      ]

      assert {:ok, ["alice@example.com", 85, "Alice"]} = Sinter.validate_many(pairs)
    end

    test "reports errors by index" do
      pairs = [
        {:string, "valid"},
        # type error
        {:integer, "invalid"},
        {:string, "valid_again"}
      ]

      assert {:error, error_map} = Sinter.validate_many(pairs)
      assert Map.has_key?(error_map, 1)
      assert not Map.has_key?(error_map, 0)
      assert not Map.has_key?(error_map, 2)

      assert List.first(error_map[1]).code == :type
    end

    test "supports global options" do
      pairs = [
        {:integer, "42"},
        {:float, "3.14"},
        {:boolean, "true"}
      ]

      assert {:ok, [42, 3.14, true]} = Sinter.validate_many(pairs, coerce: true)
    end

    test "merges field options with global options" do
      pairs = [
        # field-specific constraints
        {:score, :integer, "85", [gt: 0, lt: 100]},
        # no field constraints
        {:count, :integer, "42"}
      ]

      assert {:ok, [85, 42]} = Sinter.validate_many(pairs, coerce: true)

      # Field constraint violation
      invalid_pairs = [
        # violates field constraint
        {:score, :integer, "150", [lt: 100]}
      ]

      assert {:error, error_map} = Sinter.validate_many(invalid_pairs, coerce: true)
      assert List.first(error_map[0]).code == :lt
    end

    test "handles empty list" do
      assert {:ok, []} = Sinter.validate_many([])
    end

    test "handles mixed success and failure" do
      pairs = [
        {:string, "valid"},
        {:integer, "invalid_int"},
        {:string, "also_valid"},
        {:boolean, "invalid_bool"}
      ]

      assert {:error, error_map} = Sinter.validate_many(pairs)
      # invalid integer
      assert Map.has_key?(error_map, 1)
      # invalid boolean
      assert Map.has_key?(error_map, 3)
      # valid string
      assert not Map.has_key?(error_map, 0)
      # valid string
      assert not Map.has_key?(error_map, 2)
    end
  end

  describe "validator_for/2 - reusable validators" do
    test "creates reusable type validator" do
      email_validator = Sinter.validator_for(:string, format: ~r/@/)

      assert {:ok, "test@example.com"} = email_validator.("test@example.com")
      assert {:error, [error]} = email_validator.("invalid")
      assert error.code == :format
    end

    test "creates validator with multiple constraints" do
      password_validator =
        Sinter.validator_for(:string,
          min_length: 8,
          # requires uppercase
          format: ~r/[A-Z]/
        )

      assert {:ok, "Password123"} = password_validator.("Password123")

      # "short" fails both min_length and format constraints
      assert {:error, errors} = password_validator.("short")
      assert length(errors) == 2
      error_codes = Enum.map(errors, & &1.code)
      assert :min_length in error_codes
      assert :format in error_codes

      assert {:error, [error]} = password_validator.("nouppercase123")
      assert error.code == :format
    end

    test "creates validator with coercion" do
      int_validator = Sinter.validator_for(:integer, coerce: true, gt: 0)

      assert {:ok, 42} = int_validator.("42")
      assert {:error, [error]} = int_validator.("0")
      assert error.code == :gt

      assert {:error, [error]} = int_validator.("invalid")
      assert error.code == :coercion
    end

    test "validator captures constraints at creation time" do
      # Create validator with specific constraint
      validator1 = Sinter.validator_for(:integer, gt: 10)
      validator2 = Sinter.validator_for(:integer, gt: 20)

      # Each validator should use its own constraints
      assert {:ok, 15} = validator1.(15)
      assert {:error, _} = validator1.(5)

      assert {:ok, 25} = validator2.(25)
      # Too low for validator2
      assert {:error, _} = validator2.(15)
    end

    test "works with complex types" do
      array_validator = Sinter.validator_for({:array, :string}, min_items: 1, max_items: 3)

      assert {:ok, ["one"]} = array_validator.(["one"])
      assert {:ok, ["one", "two"]} = array_validator.(["one", "two"])

      assert {:error, [error]} = array_validator.([])
      assert error.code == :min_items

      assert {:error, [error]} = array_validator.(["a", "b", "c", "d"])
      assert error.code == :max_items
    end
  end

  describe "batch_validator_for/2 - reusable batch validators" do
    test "creates reusable batch validator" do
      user_validator =
        Sinter.batch_validator_for([
          {:name, :string},
          {:age, :integer}
        ])

      valid_user = %{name: "Alice", age: 30}
      assert {:ok, validated} = user_validator.(valid_user)
      assert validated[:name] == "Alice"
      assert validated[:age] == 30

      # missing age
      invalid_user = %{name: "Bob"}
      assert {:error, _} = user_validator.(invalid_user)
    end

    test "supports field constraints in batch validator" do
      user_validator =
        Sinter.batch_validator_for([
          {:name, :string, [min_length: 2]},
          {:age, :integer, [gt: 0, lt: 150]}
        ])

      valid_user = %{name: "Alice", age: 30}
      assert {:ok, _} = user_validator.(valid_user)

      # Name too short
      invalid_user1 = %{name: "A", age: 30}
      assert {:error, errors} = user_validator.(invalid_user1)
      assert List.first(errors).code == :min_length

      # Age invalid
      invalid_user2 = %{name: "Bob", age: -5}
      assert {:error, errors} = user_validator.(invalid_user2)
      assert List.first(errors).code == :gt
    end

    test "applies global options to batch validator" do
      user_validator =
        Sinter.batch_validator_for(
          [
            {:name, :string},
            {:age, :integer}
          ],
          coerce: true
        )

      data_with_strings = %{name: "Alice", age: "30"}
      assert {:ok, validated} = user_validator.(data_with_strings)
      assert validated[:name] == "Alice"
      # coerced from string
      assert validated[:age] == 30
    end

    test "batch validator preserves validation behavior" do
      # Create validator equivalent to direct schema validation
      validator =
        Sinter.batch_validator_for([
          {:email, :string, [format: ~r/@/]},
          {:score, :integer, [gt: 0, lt: 100]}
        ])

      # Compare with direct schema validation
      schema =
        Schema.define([
          {:email, :string, [required: true, format: ~r/@/]},
          {:score, :integer, [required: true, gt: 0, lt: 100]}
        ])

      test_data = %{email: "test@example.com", score: 85}

      {:ok, validator_result} = validator.(test_data)
      {:ok, schema_result} = Sinter.Validator.validate(schema, test_data)

      # Results should be equivalent
      assert validator_result[:email] == schema_result[:email]
      assert validator_result[:score] == schema_result[:score]
    end
  end

  describe "integration with full validation pipeline" do
    test "convenience functions work with complex schemas" do
      # Test that convenience functions integrate properly with the full system

      # Validate a complex union type
      union_type = {:union, [:string, {:array, :integer}]}
      assert {:ok, "text"} = Sinter.validate_type(union_type, "text")
      assert {:ok, [1, 2, 3]} = Sinter.validate_type(union_type, [1, 2, 3])

      # Validate with multiple constraints
      assert {:ok, "Valid123"} =
               Sinter.validate_type(:string, "Valid123",
                 min_length: 5,
                 format: ~r/[A-Z]/,
                 max_length: 20
               )
    end

    test "error handling consistency across convenience functions" do
      # All convenience functions should produce consistent error formats

      # Single type validation
      {:error, [error1]} = Sinter.validate_type(:string, 123)

      # Named value validation
      {:error, [error2]} = Sinter.validate_value(:field, :string, 123)

      # Batch validation
      {:error, error_map} = Sinter.validate_many([{:string, 123}])
      error3 = List.first(error_map[0])

      # All should have same basic error structure
      assert error1.code == error2.code
      assert error2.code == error3.code
      assert error1.code == :type

      # Paths should be appropriate for each context
      assert error1.path == []
      assert error2.path == [:field]
      # Batch errors don't include field names by default
      assert error3.path == []
    end

    test "coercion works consistently across functions" do
      # Test coercion behavior is consistent

      # Single type
      assert {:ok, 42} = Sinter.validate_type(:integer, "42", coerce: true)

      # Named value
      assert {:ok, 42} = Sinter.validate_value(:count, :integer, "42", coerce: true)

      # Batch
      assert {:ok, [42]} = Sinter.validate_many([{:integer, "42"}], coerce: true)

      # Validator function
      validator = Sinter.validator_for(:integer, coerce: true)
      assert {:ok, 42} = validator.("42")
    end

    test "constraint validation works across all functions" do
      constraint_opts = [gt: 0, lt: 100]

      # All should accept value 50
      assert {:ok, 50} = Sinter.validate_type(:integer, 50, constraint_opts)
      assert {:ok, 50} = Sinter.validate_value(:score, :integer, 50, constraint_opts)
      assert {:ok, [50]} = Sinter.validate_many([{:integer, 50}], constraint_opts)

      validator = Sinter.validator_for(:integer, constraint_opts)
      assert {:ok, 50} = validator.(50)

      # All should reject value 150
      assert {:error, [error]} = Sinter.validate_type(:integer, 150, constraint_opts)
      assert error.code == :lt

      assert {:error, [error]} = Sinter.validate_value(:score, :integer, 150, constraint_opts)
      assert error.code == :lt

      assert {:error, error_map} = Sinter.validate_many([{:integer, 150}], constraint_opts)
      assert List.first(error_map[0]).code == :lt

      assert {:error, [error]} = validator.(150)
      assert error.code == :lt
    end
  end

  describe "performance and memory usage" do
    test "validators can be reused efficiently" do
      # Create validator once
      validator = Sinter.validator_for(:string, min_length: 5)

      # Use many times - should not recreate schema internally
      results =
        Enum.map(1..100, fn i ->
          validator.("value_#{i}")
        end)

      # All should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    test "batch validator handles large datasets" do
      batch_validator =
        Sinter.batch_validator_for([
          {:id, :integer},
          {:name, :string}
        ])

      # Create large dataset
      large_dataset =
        Enum.map(1..1000, fn i ->
          %{id: i, name: "user_#{i}"}
        end)

      # Should handle efficiently
      results = Enum.map(large_dataset, batch_validator)

      # All should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))
    end

    test "validate_many handles large batches" do
      # Create large batch of validations
      large_batch =
        Enum.map(1..1000, fn i ->
          {:string, "value_#{i}"}
        end)

      assert {:ok, results} = Sinter.validate_many(large_batch)
      assert length(results) == 1000
      assert List.first(results) == "value_1"
      assert List.last(results) == "value_1000"
    end
  end

  describe "edge cases and error handling" do
    test "handles nil values appropriately" do
      # Most types should reject nil
      assert {:error, [error]} = Sinter.validate_type(:string, nil)
      assert error.code == :type

      # Any type should accept nil
      assert {:ok, nil} = Sinter.validate_type(:any, nil)
    end

    test "handles empty collections" do
      assert {:ok, []} = Sinter.validate_type({:array, :string}, [])
      assert {:ok, []} = Sinter.validate_many([])
    end

    test "provides helpful error messages" do
      {:error, [error]} = Sinter.validate_type(:string, 123)
      assert error.message =~ "expected string"
      assert error.message =~ "got integer"

      {:error, [error]} = Sinter.validate_value(:email, :string, 123)
      assert error.path == [:email]
      assert error.message =~ "expected string"
    end

    test "handles complex nested validation errors" do
      complex_type = {:array, {:tuple, [:string, :integer]}}
      invalid_data = [{"valid", 42}, {"invalid", "not_int"}]

      {:error, [error]} = Sinter.validate_type(complex_type, invalid_data)
      # Second array item, second tuple element
      assert error.path == [1, 1]
      assert error.code == :type
    end

    test "gracefully handles malformed input to convenience functions" do
      # validate_many with malformed pairs should give clear error
      assert_raise CaseClauseError, fn ->
        Sinter.validate_many(["not", "a", "proper", "format"])
      end
    end
  end

  describe "documentation examples work correctly" do
    test "basic usage example from module docs" do
      # Test the example from the module documentation

      # Single type validation
      assert {:ok, 42} = Sinter.validate_type(:integer, "42", coerce: true)
      assert {:ok, ["hello", "world"]} = Sinter.validate_type({:array, :string}, ["hello", "world"])

      # Named field validation
      assert {:ok, "test@example.com"} =
               Sinter.validate_value(
                 :email,
                 :string,
                 "test@example.com",
                 constraints: [format: ~r/@/]
               )

      # Batch validation
      assert {:ok, ["hello", 42, "test@example.com"]} =
               Sinter.validate_many([
                 {:string, "hello"},
                 {:integer, 42},
                 {:email, :string, "test@example.com", [format: ~r/@/]}
               ])
    end

    test "reusable validator examples" do
      # Email validator
      email_validator = Sinter.validator_for(:string, constraints: [format: ~r/@/])
      assert {:ok, "test@example.com"} = email_validator.("test@example.com")
      assert {:error, [error]} = email_validator.("invalid")
      assert error.code == :format

      # Batch validator
      batch_validator =
        Sinter.batch_validator_for([
          {:name, :string},
          {:age, :integer}
        ])

      assert {:ok, %{name: "Alice", age: 30}} = batch_validator.(%{name: "Alice", age: 30})
    end
  end

  describe "infer_schema/1 - dynamic schema creation" do
    test "infers schema from simple examples" do
      examples = [
        %{"name" => "Alice", "age" => 30},
        %{"name" => "Bob", "age" => 25},
        %{"name" => "Charlie", "age" => 35}
      ]

      schema = Sinter.infer_schema(examples)

      assert %Sinter.Schema{} = schema
      fields = Sinter.Schema.fields(schema)
      assert Map.has_key?(fields, :name)
      assert Map.has_key?(fields, :age)
      assert fields[:name].type == :string
      assert fields[:age].type == :integer
    end

    test "infers schema with mixed types" do
      examples = [
        %{"id" => "123", "score" => 95.5, "active" => true},
        %{"id" => "456", "score" => 87.2, "active" => false}
      ]

      schema = Sinter.infer_schema(examples)
      fields = Sinter.Schema.fields(schema)

      assert fields[:id].type == :string
      assert fields[:score].type == :float
      assert fields[:active].type == :boolean
    end

    test "infers schema with arrays" do
      examples = [
        %{"tags" => ["red", "blue"], "scores" => [1, 2, 3]},
        %{"tags" => ["green"], "scores" => [4, 5]}
      ]

      schema = Sinter.infer_schema(examples)
      fields = Sinter.Schema.fields(schema)

      assert fields[:tags].type == {:array, :string}
      assert fields[:scores].type == {:array, :integer}
    end

    test "handles missing fields across examples" do
      examples = [
        %{"name" => "Alice", "age" => 30},
        # missing age
        %{"name" => "Bob"},
        # extra field
        %{"name" => "Charlie", "age" => 35, "email" => "charlie@test.com"}
      ]

      schema = Sinter.infer_schema(examples)
      fields = Sinter.Schema.fields(schema)

      # in all examples
      assert fields[:name].required == true
      # missing in some
      assert fields[:age].required == false
      # missing in most
      assert fields[:email].required == false
    end

    test "raises on empty examples" do
      assert_raise ArgumentError, fn ->
        Sinter.infer_schema([])
      end
    end

    test "raises on non-map examples" do
      assert_raise ArgumentError, fn ->
        Sinter.infer_schema(["not", "maps"])
      end
    end
  end

  describe "merge_schemas/1 - schema composition" do
    test "merges two simple schemas" do
      schema1 =
        Sinter.Schema.define([
          {:name, :string, [required: true]},
          {:age, :integer, [optional: true]}
        ])

      schema2 =
        Sinter.Schema.define([
          {:email, :string, [required: true, format: ~r/@/]},
          {:active, :boolean, [optional: true, default: true]}
        ])

      merged = Sinter.merge_schemas([schema1, schema2])
      fields = Sinter.Schema.fields(merged)

      assert Map.has_key?(fields, :name)
      assert Map.has_key?(fields, :age)
      assert Map.has_key?(fields, :email)
      assert Map.has_key?(fields, :active)

      assert fields[:name].required == true
      assert fields[:email].required == true
      assert fields[:age].required == false
      assert fields[:active].default == true
    end

    test "handles conflicting field definitions" do
      schema1 =
        Sinter.Schema.define([
          {:name, :string, [required: true, min_length: 2]}
        ])

      schema2 =
        Sinter.Schema.define([
          # conflict
          {:name, :string, [required: false, min_length: 5]}
        ])

      merged = Sinter.merge_schemas([schema1, schema2])
      fields = Sinter.Schema.fields(merged)

      # Last schema wins for conflicts
      assert fields[:name].required == false
      assert Enum.find(fields[:name].constraints, &match?({:min_length, 5}, &1))
    end

    test "merges schema configurations" do
      schema1 = Sinter.Schema.define([], title: "Schema 1", strict: true)
      schema2 = Sinter.Schema.define([], description: "Schema 2", strict: false)

      merged = Sinter.merge_schemas([schema1, schema2])
      config = Sinter.Schema.config(merged)

      # first non-nil wins
      assert config.title == "Schema 1"
      assert config.description == "Schema 2"
      # last wins
      assert config.strict == false
    end

    test "raises on empty schema list" do
      assert_raise ArgumentError, fn ->
        Sinter.merge_schemas([])
      end
    end
  end
end
