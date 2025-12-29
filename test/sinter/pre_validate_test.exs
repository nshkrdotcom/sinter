defmodule Sinter.PreValidateTest do
  use ExUnit.Case, async: true

  alias Sinter.{Schema, Validator}

  describe "pre_validate option" do
    test "transforms data before validation" do
      schema =
        Schema.define(
          [
            {:amount, :integer, [required: true]}
          ],
          pre_validate: fn data ->
            case data do
              %{"amount" => amount} when is_binary(amount) ->
                Map.put(data, "amount", String.to_integer(amount))

              _ ->
                data
            end
          end
        )

      # String amount gets transformed to integer
      assert {:ok, %{"amount" => 42}} = Validator.validate(schema, %{"amount" => "42"})
    end

    test "pre_validate receives raw input data" do
      test_pid = self()

      schema =
        Schema.define(
          [{:name, :string, [required: true]}],
          pre_validate: fn data ->
            send(test_pid, {:pre_validate_called, data})
            data
          end
        )

      input = %{"name" => "test", "extra" => "field"}
      Validator.validate(schema, input)

      assert_receive {:pre_validate_called, ^input}
    end

    test "pre_validate can add fields" do
      schema =
        Schema.define(
          [
            {:full_name, :string, [required: true]},
            {:first_name, :string, [optional: true]},
            {:last_name, :string, [optional: true]}
          ],
          pre_validate: fn data ->
            first = Map.get(data, "first_name", "")
            last = Map.get(data, "last_name", "")
            Map.put(data, "full_name", "#{first} #{last}" |> String.trim())
          end
        )

      input = %{"first_name" => "John", "last_name" => "Doe"}
      assert {:ok, result} = Validator.validate(schema, input)
      assert result["full_name"] == "John Doe"
    end

    test "pre_validate can remove fields" do
      schema =
        Schema.define(
          [{:data, :map, [required: true]}],
          pre_validate: fn data ->
            Map.update(data, "data", %{}, fn d ->
              Map.drop(d, ["password", "secret"])
            end)
          end
        )

      input = %{"data" => %{"name" => "test", "password" => "secret123"}}
      assert {:ok, result} = Validator.validate(schema, input)
      refute Map.has_key?(result["data"], "password")
    end

    test "errors in pre_validate are caught and wrapped" do
      schema =
        Schema.define(
          [{:value, :integer, [required: true]}],
          pre_validate: fn _data ->
            raise "Pre-validation error"
          end
        )

      assert {:error, [error]} = Validator.validate(schema, %{"value" => 1})
      assert error.code == :pre_validate_error
    end

    test "pre_validate nil means no transformation" do
      schema =
        Schema.define(
          [{:name, :string, [required: true]}],
          pre_validate: nil
        )

      assert {:ok, _} = Validator.validate(schema, %{"name" => "test"})
    end

    test "pre_validate works with nested schemas" do
      inner_schema =
        Schema.define(
          [{:value, :integer, [required: true]}],
          pre_validate: fn data ->
            Map.update(data, "value", 0, &(&1 * 2))
          end
        )

      outer_schema =
        Schema.define([
          {:nested, {:object, inner_schema}, [required: true]}
        ])

      input = %{"nested" => %{"value" => 5}}
      assert {:ok, result} = Validator.validate(outer_schema, input)
      assert result["nested"]["value"] == 10
    end

    test "pre_validate can normalize input keys from atoms to strings" do
      schema =
        Schema.define(
          [{:name, :string, [required: true]}],
          pre_validate: fn data ->
            Enum.reduce(data, %{}, fn {k, v}, acc ->
              key = if is_atom(k), do: Atom.to_string(k), else: k
              Map.put(acc, key, v)
            end)
          end
        )

      # Atom keys should work after pre_validate normalizes them
      assert {:ok, %{"name" => "test"}} = Validator.validate(schema, %{name: "test"})
    end

    test "pre_validate returning error tuple fails validation" do
      schema =
        Schema.define(
          [{:value, :integer, [required: true]}],
          pre_validate: fn data ->
            if Map.get(data, "value") < 0 do
              raise "Negative values not allowed"
            else
              data
            end
          end
        )

      assert {:error, [error]} = Validator.validate(schema, %{"value" => -1})
      assert error.code == :pre_validate_error
    end
  end
end
