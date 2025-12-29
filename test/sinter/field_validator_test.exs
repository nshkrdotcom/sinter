defmodule Sinter.FieldValidatorTest do
  use ExUnit.Case, async: true

  alias Sinter.{Schema, Validator}

  describe "field validate option" do
    test "custom validator runs after type check" do
      schema =
        Schema.define([
          {:email, :string,
           [
             required: true,
             validate: fn value ->
               if String.contains?(value, "@"),
                 do: {:ok, value},
                 else: {:error, "must contain @"}
             end
           ]}
        ])

      assert {:ok, _} = Validator.validate(schema, %{"email" => "test@example.com"})
      assert {:error, [error]} = Validator.validate(schema, %{"email" => "invalid"})
      assert error.code == :custom_validation
      assert error.message =~ "@"
    end

    test "validator can transform value" do
      schema =
        Schema.define([
          {:name, :string,
           [
             required: true,
             validate: fn value ->
               {:ok, String.upcase(value)}
             end
           ]}
        ])

      assert {:ok, %{"name" => "ALICE"}} = Validator.validate(schema, %{"name" => "alice"})
    end

    test "validator receives value after type coercion" do
      schema =
        Schema.define(
          [
            {:count, :integer,
             [
               required: true,
               validate: fn value ->
                 if value > 0,
                   do: {:ok, value},
                   else: {:error, "must be positive"}
               end
             ]}
          ],
          coerce: true
        )

      assert {:ok, %{"count" => 5}} = Validator.validate(schema, %{"count" => "5"}, coerce: true)
      assert {:error, _} = Validator.validate(schema, %{"count" => "-1"}, coerce: true)
    end

    test "validator error includes field path" do
      schema =
        Schema.define([
          {:user,
           {:object,
            Schema.define([
              {:age, :integer,
               [
                 required: true,
                 validate: fn v ->
                   if v >= 0, do: {:ok, v}, else: {:error, "must be non-negative"}
                 end
               ]}
            ])}, [required: true]}
        ])

      assert {:error, [error]} =
               Validator.validate(schema, %{
                 "user" => %{"age" => -5}
               })

      assert error.path == ["user", "age"]
    end

    test "multiple validators can be specified as list" do
      not_empty = fn v ->
        if String.length(v) > 0, do: {:ok, v}, else: {:error, "cannot be empty"}
      end

      max_length = fn v ->
        if String.length(v) <= 10, do: {:ok, v}, else: {:error, "too long"}
      end

      schema =
        Schema.define([
          {:code, :string,
           [
             required: true,
             validate: [not_empty, max_length]
           ]}
        ])

      assert {:ok, _} = Validator.validate(schema, %{"code" => "ABC123"})
      assert {:error, _} = Validator.validate(schema, %{"code" => ""})
      assert {:error, _} = Validator.validate(schema, %{"code" => "VERYLONGCODE123"})
    end

    test "validator only runs if field is present" do
      schema =
        Schema.define([
          {:optional_field, :string,
           [
             optional: true,
             validate: fn _ -> {:error, "always fails"} end
           ]}
        ])

      # Should pass because field is not present
      assert {:ok, _} = Validator.validate(schema, %{})
    end

    test "validator runs on nil if field is present with nullable type" do
      schema =
        Schema.define([
          {:nullable_field, {:nullable, :string},
           [
             optional: true,
             validate: fn
               nil -> {:ok, nil}
               v -> {:ok, String.upcase(v)}
             end
           ]}
        ])

      assert {:ok, %{"nullable_field" => nil}} =
               Validator.validate(schema, %{"nullable_field" => nil})

      assert {:ok, %{"nullable_field" => "HELLO"}} =
               Validator.validate(schema, %{"nullable_field" => "hello"})
    end

    test "validator exception is caught and wrapped" do
      schema =
        Schema.define([
          {:value, :integer,
           [
             required: true,
             validate: fn _ -> raise "Validator crashed" end
           ]}
        ])

      assert {:error, [error]} = Validator.validate(schema, %{"value" => 42})
      assert error.code == :custom_validation_error
      assert error.message =~ "Validator crashed"
    end

    test "validators work with array elements" do
      schema =
        Schema.define([
          {:numbers, {:array, :integer},
           [
             required: true,
             validate: fn arr ->
               if Enum.all?(arr, &(&1 > 0)),
                 do: {:ok, arr},
                 else: {:error, "all numbers must be positive"}
             end
           ]}
        ])

      assert {:ok, _} = Validator.validate(schema, %{"numbers" => [1, 2, 3]})
      assert {:error, _} = Validator.validate(schema, %{"numbers" => [1, -2, 3]})
    end

    test "validator returning just :ok is treated as success with original value" do
      schema =
        Schema.define([
          {:value, :string,
           [
             required: true,
             validate: fn value ->
               if String.length(value) > 0, do: :ok, else: {:error, "empty"}
             end
           ]}
        ])

      assert {:ok, %{"value" => "test"}} = Validator.validate(schema, %{"value" => "test"})
    end
  end
end
