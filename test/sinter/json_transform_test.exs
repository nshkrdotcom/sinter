defmodule Sinter.JSONTransformTest do
  use ExUnit.Case, async: true

  alias Sinter.{JSON, NotGiven, Schema, Transform}

  describe "Sinter.Transform" do
    test "drops NotGiven and omit sentinels while stringifying keys" do
      input = %{
        a: 1,
        b: NotGiven.value(),
        c: NotGiven.omit(),
        d: nil,
        nested: %{keep: "ok", drop: NotGiven.value()}
      }

      assert %{"a" => 1, "d" => nil, "nested" => %{"keep" => "ok"}} =
               Transform.transform(input)
    end

    test "applies aliases and formats" do
      input = %{snake_key: "value", timestamp: ~N[2024-01-01 00:00:00]}

      result =
        Transform.transform(input,
          aliases: %{snake_key: "camelKey"},
          formats: %{timestamp: :iso8601}
        )

      assert result["camelKey"] == "value"
      assert result["timestamp"] == "2024-01-01T00:00:00"
    end

    test "drops nil values when configured" do
      input = %{"a" => nil, "b" => 1}

      assert %{"b" => 1} = Transform.transform(input, drop_nil?: true)
    end
  end

  describe "Sinter.JSON" do
    test "encodes using transform pipeline" do
      data = %{
        name: "Alice",
        age: 30,
        omit_me: NotGiven.omit()
      }

      assert {:ok, json} = JSON.encode(data, aliases: %{name: "full_name"})
      assert {:ok, decoded} = Jason.decode(json)

      assert decoded == %{"full_name" => "Alice", "age" => 30}
    end

    test "decodes and validates JSON payloads" do
      schema =
        Schema.define([
          {:name, :string, [required: true]},
          {:age, :integer, [optional: true]}
        ])

      assert {:ok, validated} = JSON.decode(~s({"name":"Alice","age":30}), schema)
      assert validated["name"] == "Alice"
      assert validated["age"] == 30
    end

    test "returns validation errors for invalid payloads" do
      schema = Schema.define([{:count, :integer, [required: true]}])

      assert {:error, errors} = JSON.decode(~s({"count":"not-a-number"}), schema)
      assert Enum.any?(errors, &(&1.code == :type))
    end

    test "supports coercion during decode" do
      schema = Schema.define([{:count, :integer, [required: true]}])

      assert {:ok, validated} = JSON.decode(~s({"count":"42"}), schema, coerce: true)
      assert validated["count"] == 42
    end
  end
end
