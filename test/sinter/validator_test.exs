defmodule Sinter.ValidatorTest do
  use ExUnit.Case, async: true

  alias Sinter.{Schema, ValidationError, Validator}

  # Helper function to create simple test schema
  defp test_schema(fields \\ nil, opts \\ []) do
    fields =
      fields ||
        [
          {:name, :string, [required: true, min_length: 2]},
          {:age, :integer, [optional: true, gt: 0, lt: 150]},
          {:email, :string, [optional: true, format: ~r/@/]},
          {:tags, {:array, :string}, [optional: true, max_items: 5]}
        ]

    Schema.define(fields, opts)
  end

  describe "validate/3 - basic validation pipeline" do
    test "validates valid data successfully" do
      schema = test_schema()

      valid_data = %{
        "name" => "Alice",
        "age" => 30,
        "email" => "alice@example.com",
        "tags" => ["developer", "elixir"]
      }

      assert {:ok, validated} = Validator.validate(schema, valid_data)
      assert validated[:name] == "Alice"
      assert validated[:age] == 30
      assert validated[:email] == "alice@example.com"
      assert validated[:tags] == ["developer", "elixir"]
    end

    test "validates minimal valid data (only required fields)" do
      schema = test_schema()

      minimal_data = %{"name" => "Bob"}

      assert {:ok, validated} = Validator.validate(schema, minimal_data)
      assert validated[:name] == "Bob"
      assert Map.has_key?(validated, :age) == false
      assert Map.has_key?(validated, :email) == false
      assert Map.has_key?(validated, :tags) == false
    end

    test "rejects non-map input" do
      schema = test_schema()

      assert {:error, [error]} = Validator.validate(schema, "not a map")
      assert error.code == :input_format
      assert error.path == []
      assert error.message =~ "Expected map"
    end

    test "validates with atom keys" do
      schema = test_schema()

      data_with_atoms = %{
        name: "Charlie",
        age: 25
      }

      assert {:ok, validated} = Validator.validate(schema, data_with_atoms)
      assert validated[:name] == "Charlie"
      assert validated[:age] == 25
    end

    test "validates with mixed string/atom keys" do
      schema = test_schema()

      mixed_data = %{
        "name" => "Diana",
        age: 35
      }

      assert {:ok, validated} = Validator.validate(schema, mixed_data)
      assert validated[:name] == "Diana"
      assert validated[:age] == 35
    end
  end

  describe "validate/3 - required field validation" do
    test "detects missing required fields" do
      schema = test_schema()

      data_missing_name = %{"age" => 30}

      assert {:error, [error]} = Validator.validate(schema, data_missing_name)
      assert error.code == :required
      assert error.path == [:name]
      assert error.message == "field is required"
    end

    test "detects multiple missing required fields" do
      schema =
        Schema.define([
          {:field1, :string, [required: true]},
          {:field2, :integer, [required: true]},
          {:field3, :string, [optional: true]}
        ])

      data = %{"field3" => "optional"}

      assert {:error, errors} = Validator.validate(schema, data)
      assert length(errors) == 2

      error_paths = Enum.map(errors, & &1.path)
      assert [:field1] in error_paths
      assert [:field2] in error_paths
    end

    test "allows missing optional fields" do
      schema =
        Schema.define([
          {:required_field, :string, [required: true]},
          {:optional_field, :string, [optional: true]}
        ])

      data = %{"required_field" => "present"}

      assert {:ok, validated} = Validator.validate(schema, data)
      assert validated[:required_field] == "present"
      assert Map.has_key?(validated, :optional_field) == false
    end
  end

  describe "validate/3 - default values" do
    test "applies default values for missing optional fields" do
      schema =
        Schema.define([
          {:name, :string, [required: true]},
          {:active, :boolean, [optional: true, default: true]},
          {:count, :integer, [optional: true, default: 0]},
          {:tags, {:array, :string}, [optional: true, default: []]}
        ])

      data = %{"name" => "Test"}

      assert {:ok, validated} = Validator.validate(schema, data)
      assert validated[:name] == "Test"
      assert validated[:active] == true
      assert validated[:count] == 0
      assert validated[:tags] == []
    end

    test "uses provided values over defaults" do
      schema =
        Schema.define([
          {:name, :string, [required: true]},
          {:active, :boolean, [optional: true, default: true]},
          {:count, :integer, [optional: true, default: 0]}
        ])

      data = %{
        "name" => "Test",
        "active" => false,
        "count" => 42
      }

      assert {:ok, validated} = Validator.validate(schema, data)
      assert validated[:name] == "Test"
      assert validated[:active] == false
      assert validated[:count] == 42
    end

    test "nil defaults are not applied" do
      schema =
        Schema.define([
          {:name, :string, [required: true]},
          {:nullable, :string, [optional: true, default: nil]}
        ])

      data = %{"name" => "Test"}

      assert {:ok, validated} = Validator.validate(schema, data)
      assert validated[:name] == "Test"
      assert Map.has_key?(validated, :nullable) == false
    end
  end

  describe "validate/3 - type validation" do
    test "validates string fields" do
      schema = Schema.define([{:text, :string, [required: true]}])

      assert {:ok, _} = Validator.validate(schema, %{"text" => "valid"})
      assert {:ok, _} = Validator.validate(schema, %{"text" => ""})

      assert {:error, [error]} = Validator.validate(schema, %{"text" => 123})
      assert error.code == :type
      assert error.path == [:text]
    end

    test "validates integer fields" do
      schema = Schema.define([{:number, :integer, [required: true]}])

      assert {:ok, _} = Validator.validate(schema, %{"number" => 42})
      assert {:ok, _} = Validator.validate(schema, %{"number" => -10})
      assert {:ok, _} = Validator.validate(schema, %{"number" => 0})

      assert {:error, [error]} = Validator.validate(schema, %{"number" => "42"})
      assert error.code == :type
      assert error.path == [:number]

      assert {:error, [error]} = Validator.validate(schema, %{"number" => 3.14})
      assert error.code == :type
    end

    test "validates float fields" do
      schema = Schema.define([{:decimal, :float, [required: true]}])

      assert {:ok, _} = Validator.validate(schema, %{"decimal" => 3.14})
      assert {:ok, _} = Validator.validate(schema, %{"decimal" => 42.0})

      assert {:error, [error]} = Validator.validate(schema, %{"decimal" => 42})
      assert error.code == :type
      assert error.path == [:decimal]
    end

    test "validates boolean fields" do
      schema = Schema.define([{:flag, :boolean, [required: true]}])

      assert {:ok, _} = Validator.validate(schema, %{"flag" => true})
      assert {:ok, _} = Validator.validate(schema, %{"flag" => false})

      assert {:error, [error]} = Validator.validate(schema, %{"flag" => "true"})
      assert error.code == :type
      assert error.path == [:flag]
    end

    test "validates array fields" do
      schema = Schema.define([{:items, {:array, :string}, [required: true]}])

      assert {:ok, _} = Validator.validate(schema, %{"items" => ["a", "b", "c"]})
      assert {:ok, _} = Validator.validate(schema, %{"items" => []})

      assert {:error, [error]} = Validator.validate(schema, %{"items" => "not array"})
      assert error.code == :type
      assert error.path == [:items]

      # Invalid array element type
      assert {:error, [error]} = Validator.validate(schema, %{"items" => ["valid", 123]})
      assert error.code == :type
      assert error.path == [:items, 1]
    end
  end

  describe "validate/3 - constraint validation" do
    test "validates string length constraints" do
      schema =
        Schema.define([
          {:short, :string, [required: true, min_length: 2, max_length: 5]}
        ])

      # Valid lengths
      assert {:ok, _} = Validator.validate(schema, %{"short" => "ab"})
      assert {:ok, _} = Validator.validate(schema, %{"short" => "abc"})
      assert {:ok, _} = Validator.validate(schema, %{"short" => "abcde"})

      # Too short
      assert {:error, [error]} = Validator.validate(schema, %{"short" => "a"})
      assert error.code == :min_length
      assert error.path == [:short]
      assert error.message =~ "at least 2"

      # Too long
      assert {:error, [error]} = Validator.validate(schema, %{"short" => "abcdef"})
      assert error.code == :max_length
      assert error.path == [:short]
      assert error.message =~ "at most 5"
    end

    test "validates array length constraints" do
      schema =
        Schema.define([
          {:items, {:array, :string}, [required: true, min_items: 1, max_items: 3]}
        ])

      # Valid lengths
      assert {:ok, _} = Validator.validate(schema, %{"items" => ["one"]})
      assert {:ok, _} = Validator.validate(schema, %{"items" => ["one", "two"]})
      assert {:ok, _} = Validator.validate(schema, %{"items" => ["one", "two", "three"]})

      # Too few
      assert {:error, [error]} = Validator.validate(schema, %{"items" => []})
      assert error.code == :min_items
      assert error.path == [:items]
      assert error.message =~ "at least 1"

      # Too many
      assert {:error, [error]} = Validator.validate(schema, %{"items" => ["a", "b", "c", "d"]})
      assert error.code == :max_items
      assert error.path == [:items]
      assert error.message =~ "at most 3"
    end

    test "validates numeric constraints" do
      schema =
        Schema.define([
          {:score, :integer, [required: true, gt: 0, lt: 100]},
          {:rating, :float, [required: true, gteq: 1.0, lteq: 5.0]}
        ])

      # Valid values
      assert {:ok, _} = Validator.validate(schema, %{"score" => 50, "rating" => 3.5})
      assert {:ok, _} = Validator.validate(schema, %{"score" => 1, "rating" => 1.0})
      assert {:ok, _} = Validator.validate(schema, %{"score" => 99, "rating" => 5.0})

      # Invalid score (too low)
      assert {:error, [error]} = Validator.validate(schema, %{"score" => 0, "rating" => 3.0})
      assert error.code == :gt
      assert error.path == [:score]
      assert error.message =~ "greater than 0"

      # Invalid score (too high)
      assert {:error, [error]} = Validator.validate(schema, %{"score" => 100, "rating" => 3.0})
      assert error.code == :lt
      assert error.path == [:score]
      assert error.message =~ "less than 100"

      # Invalid rating (too low)
      assert {:error, [error]} = Validator.validate(schema, %{"score" => 50, "rating" => 0.5})
      assert error.code == :gteq
      assert error.path == [:rating]
      assert error.message =~ "greater than or equal to 1.0"

      # Invalid rating (too high)
      assert {:error, [error]} = Validator.validate(schema, %{"score" => 50, "rating" => 5.5})
      assert error.code == :lteq
      assert error.path == [:rating]
      assert error.message =~ "less than or equal to 5.0"
    end

    test "validates format constraints" do
      schema =
        Schema.define([
          {:email, :string, [required: true, format: ~r/@/]},
          {:phone, :string, [required: true, format: ~r/^\d{3}-\d{3}-\d{4}$/]}
        ])

      # Valid formats
      assert {:ok, _} =
               Validator.validate(schema, %{
                 "email" => "test@example.com",
                 "phone" => "123-456-7890"
               })

      # Invalid email format
      assert {:error, [error]} =
               Validator.validate(schema, %{
                 "email" => "invalid-email",
                 "phone" => "123-456-7890"
               })

      assert error.code == :format
      assert error.path == [:email]
      assert error.message =~ "does not match"

      # Invalid phone format
      assert {:error, [error]} =
               Validator.validate(schema, %{
                 "email" => "test@example.com",
                 "phone" => "invalid-phone"
               })

      assert error.code == :format
      assert error.path == [:phone]
    end

    test "validates choice constraints" do
      schema =
        Schema.define([
          {:status, :string, [required: true, choices: ["active", "inactive", "pending"]]},
          {:priority, :integer, [required: true, choices: [1, 2, 3, 4, 5]]}
        ])

      # Valid choices
      assert {:ok, _} = Validator.validate(schema, %{"status" => "active", "priority" => 3})
      assert {:ok, _} = Validator.validate(schema, %{"status" => "pending", "priority" => 1})

      # Invalid status choice
      assert {:error, [error]} =
               Validator.validate(schema, %{"status" => "unknown", "priority" => 3})

      assert error.code == :choices
      assert error.path == [:status]
      assert error.message =~ "must be one of"

      # Invalid priority choice
      assert {:error, [error]} =
               Validator.validate(schema, %{"status" => "active", "priority" => 6})

      assert error.code == :choices
      assert error.path == [:priority]
    end

    test "validates multiple constraints on single field" do
      schema =
        Schema.define([
          {:password, :string, [required: true, min_length: 8, max_length: 20, format: ~r/[A-Z]/]}
        ])

      # Valid password
      assert {:ok, _} = Validator.validate(schema, %{"password" => "MyPassword123"})

      # Too short
      assert {:error, [error]} = Validator.validate(schema, %{"password" => "Short1"})
      assert error.code == :min_length

      # No uppercase letter
      assert {:error, [error]} = Validator.validate(schema, %{"password" => "lowercase123"})
      assert error.code == :format
    end
  end

  describe "validate/3 - coercion" do
    test "coerces types when enabled" do
      schema =
        Schema.define([
          {:count, :integer, [required: true]},
          {:price, :float, [required: true]},
          {:active, :boolean, [required: true]}
        ])

      data = %{
        "count" => "42",
        "price" => "19.99",
        "active" => "true"
      }

      assert {:ok, validated} = Validator.validate(schema, data, coerce: true)
      assert validated[:count] == 42
      assert validated[:price] == 19.99
      assert validated[:active] == true
    end

    test "coercion respects constraints" do
      schema =
        Schema.define([
          {:count, :integer, [required: true, gt: 0]}
        ])

      # Valid after coercion
      assert {:ok, validated} = Validator.validate(schema, %{"count" => "42"}, coerce: true)
      assert validated[:count] == 42

      # Invalid constraint after coercion
      assert {:error, [error]} = Validator.validate(schema, %{"count" => "0"}, coerce: true)
      assert error.code == :gt
      assert error.path == [:count]
    end

    test "coercion fails gracefully for invalid values" do
      schema =
        Schema.define([
          {:count, :integer, [required: true]}
        ])

      assert {:error, [error]} =
               Validator.validate(schema, %{"count" => "not_a_number"}, coerce: true)

      assert error.code == :coercion
      assert error.path == [:count]
    end

    test "coerces array elements individually" do
      schema =
        Schema.define([
          {:numbers, {:array, :integer}, [required: true]}
        ])

      data = %{"numbers" => ["1", "2", "3"]}

      assert {:ok, validated} = Validator.validate(schema, data, coerce: true)
      assert validated[:numbers] == [1, 2, 3]

      # Partial coercion failure
      data_mixed = %{"numbers" => ["1", "invalid", "3"]}
      assert {:error, errors} = Validator.validate(schema, data_mixed, coerce: true)
      assert length(errors) == 1
      error = List.first(errors)
      assert error.code == :coercion
      assert error.path == [:numbers, 1]
    end
  end

  describe "validate/3 - strict mode" do
    test "allows extra fields when not strict" do
      schema =
        Schema.define(
          [
            {:name, :string, [required: true]}
          ],
          strict: false
        )

      data = %{
        "name" => "Alice",
        "extra_field" => "extra_value",
        "another_extra" => 42
      }

      assert {:ok, validated} = Validator.validate(schema, data)
      assert validated[:name] == "Alice"
      # Extra fields are not included in result
      assert Map.has_key?(validated, :extra_field) == false
    end

    test "rejects extra fields when strict" do
      schema =
        Schema.define(
          [
            {:name, :string, [required: true]}
          ],
          strict: true
        )

      data = %{
        "name" => "Alice",
        "extra_field" => "extra_value"
      }

      assert {:error, [error]} = Validator.validate(schema, data)
      assert error.code == :strict
      assert error.path == []
      assert error.message =~ "unexpected fields"
      assert error.message =~ "extra_field"
    end

    test "strict mode can be overridden in options" do
      # Schema is not strict by default
      schema =
        Schema.define([
          {:name, :string, [required: true]}
        ])

      data = %{
        "name" => "Alice",
        "extra_field" => "extra_value"
      }

      # Override to strict
      assert {:error, [error]} = Validator.validate(schema, data, strict: true)
      assert error.code == :strict

      # Confirm default behavior still works
      assert {:ok, _} = Validator.validate(schema, data)
    end
  end

  describe "validate/3 - post validation" do
    test "executes post-validation function" do
      post_validate = fn data ->
        if Map.get(data, :password) == Map.get(data, :password_confirmation) do
          {:ok, Map.delete(data, :password_confirmation)}
        else
          {:error, "Passwords do not match"}
        end
      end

      schema =
        Schema.define(
          [
            {:password, :string, [required: true]},
            {:password_confirmation, :string, [required: true]}
          ],
          post_validate: post_validate
        )

      # Valid case
      valid_data = %{
        "password" => "secret123",
        "password_confirmation" => "secret123"
      }

      assert {:ok, validated} = Validator.validate(schema, valid_data)
      assert validated[:password] == "secret123"
      assert Map.has_key?(validated, :password_confirmation) == false

      # Invalid case
      invalid_data = %{
        "password" => "secret123",
        "password_confirmation" => "different"
      }

      assert {:error, [error]} = Validator.validate(schema, invalid_data)
      assert error.code == :post_validation
      assert error.message == "Passwords do not match"
    end

    test "handles post-validation errors" do
      post_validate = fn _data ->
        raise "Something went wrong"
      end

      schema =
        Schema.define(
          [
            {:name, :string, [required: true]}
          ],
          post_validate: post_validate
        )

      assert {:error, [error]} = Validator.validate(schema, %{"name" => "test"})
      assert error.code == :post_validation
      assert error.message =~ "Post-validation function failed"
    end

    test "handles invalid post-validation return values" do
      post_validate = fn _data ->
        "invalid return value"
      end

      schema =
        Schema.define(
          [
            {:name, :string, [required: true]}
          ],
          post_validate: post_validate
        )

      assert {:error, [error]} = Validator.validate(schema, %{"name" => "test"})
      assert error.code == :post_validation
      assert error.message =~ "invalid format"
    end
  end

  describe "validate!/3" do
    test "returns validated data on success" do
      schema = test_schema()
      data = %{"name" => "Alice", "age" => 30}

      validated = Validator.validate!(schema, data)
      assert validated[:name] == "Alice"
      assert validated[:age] == 30
    end

    test "raises ValidationError on failure" do
      schema = test_schema()
      # missing required name
      invalid_data = %{"age" => 30}

      assert_raise ValidationError, fn ->
        Validator.validate!(schema, invalid_data)
      end
    end

    test "raised exception contains error details" do
      schema = test_schema()
      # too short
      invalid_data = %{"name" => "a"}

      try do
        Validator.validate!(schema, invalid_data)
        flunk("Expected ValidationError to be raised")
      rescue
        e in ValidationError ->
          errors = ValidationError.errors(e)
          assert length(errors) == 1
          assert List.first(errors).code == :min_length
      end
    end
  end

  describe "validate_many/3" do
    test "validates multiple valid items" do
      schema = test_schema()

      data_list = [
        %{"name" => "Alice", "age" => 30},
        %{"name" => "Bob", "age" => 25},
        %{"name" => "Charlie"}
      ]

      assert {:ok, validated_list} = Validator.validate_many(schema, data_list)
      assert length(validated_list) == 3
      assert Enum.at(validated_list, 0)[:name] == "Alice"
      assert Enum.at(validated_list, 1)[:name] == "Bob"
      assert Enum.at(validated_list, 2)[:name] == "Charlie"
    end

    test "reports errors by index" do
      schema = test_schema()

      data_list = [
        # valid
        %{"name" => "Alice", "age" => 30},
        # missing name
        %{"age" => 25},
        # invalid age
        %{"name" => "Charlie", "age" => -5}
      ]

      assert {:error, error_map} = Validator.validate_many(schema, data_list)
      # index 1 has error
      assert Map.has_key?(error_map, 1)
      # index 2 has error
      assert Map.has_key?(error_map, 2)
      # index 0 is valid
      assert not Map.has_key?(error_map, 0)

      # Check specific errors
      assert List.first(error_map[1]).code == :required
      assert List.first(error_map[2]).code == :gt
    end

    test "includes index in error paths" do
      schema =
        Schema.define([
          {:items, {:array, :string}, [required: true]}
        ])

      data_list = [
        %{"items" => ["valid"]},
        # invalid array element
        %{"items" => ["valid", 123]}
      ]

      assert {:error, error_map} = Validator.validate_many(schema, data_list)
      error = List.first(error_map[1])
      # [batch_index, field, array_index]
      assert error.path == [1, :items, 1]
    end

    test "handles empty list" do
      schema = test_schema()

      assert {:ok, []} = Validator.validate_many(schema, [])
    end
  end

  describe "error path generation" do
    test "generates correct paths for nested structures" do
      schema =
        Schema.define([
          {:users, {:array, :map}, [required: true]}
        ])

      data = %{
        "users" => [
          %{"name" => "Alice"},
          # not a map
          "invalid_user"
        ]
      }

      assert {:error, [error]} = Validator.validate(schema, data)
      assert error.path == [:users, 1]
      assert error.code == :type
    end

    test "preserves path context through validation pipeline" do
      schema =
        Schema.define([
          {:nested, {:array, {:array, :string}}, [required: true]}
        ])

      data = %{
        "nested" => [
          ["valid", "strings"],
          # invalid element in nested array
          ["invalid", 123]
        ]
      }

      assert {:error, [error]} = Validator.validate(schema, data)
      assert error.path == [:nested, 1, 1]
      assert error.code == :type
    end
  end

  describe "edge cases and error handling" do
    test "handles schema with no fields" do
      empty_schema = Schema.define([])

      assert {:ok, %{}} = Validator.validate(empty_schema, %{})
      assert {:ok, %{}} = Validator.validate(empty_schema, %{"extra" => "field"})
    end

    test "handles very large data structures" do
      schema =
        Schema.define([
          {:items, {:array, :integer}, [required: true]}
        ])

      large_list = Enum.to_list(1..1000)
      data = %{"items" => large_list}

      assert {:ok, validated} = Validator.validate(schema, data)
      assert validated[:items] == large_list
    end

    test "handles deeply nested structures" do
      # Create a deeply nested array type
      nested_type =
        Enum.reduce(1..5, :string, fn _, acc ->
          {:array, acc}
        end)

      schema =
        Schema.define([
          {:deep, nested_type, [required: true]}
        ])

      # Create valid deeply nested data
      deep_data =
        Enum.reduce(1..5, "bottom", fn _, acc ->
          [acc]
        end)

      data = %{"deep" => deep_data}

      assert {:ok, validated} = Validator.validate(schema, data)
      assert validated[:deep] == deep_data
    end

    test "accumulates all validation errors" do
      schema =
        Schema.define([
          {:name, :string, [required: true, min_length: 5]},
          {:age, :integer, [required: true, gt: 0]},
          {:email, :string, [required: true, format: ~r/@/]}
        ])

      invalid_data = %{
        # too short
        "name" => "a",
        # too low
        "age" => -5,
        # no @
        "email" => "bad"
      }

      assert {:error, errors} = Validator.validate(schema, invalid_data)
      assert length(errors) == 3

      error_codes = Enum.map(errors, & &1.code)
      assert :min_length in error_codes
      assert :gt in error_codes
      assert :format in error_codes
    end
  end
end
