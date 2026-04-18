defmodule Sinter.DiscriminatedUnionTest do
  use ExUnit.Case, async: true

  alias Sinter.{JsonSchema, Schema, Types, Validator}

  # Helper schemas for testing
  defp encoded_text_schema do
    Schema.define([
      {:type, {:literal, "encoded_text"}, [required: true]},
      {:tokens, {:array, :integer}, [required: true]}
    ])
  end

  defp image_schema do
    Schema.define([
      {:type, {:literal, "image"}, [required: true]},
      {:data, :string, [required: true]},
      {:format, :string, [choices: ["png", "jpeg"], required: true]}
    ])
  end

  defp image_pointer_schema do
    Schema.define([
      {:type, {:literal, "image_asset_pointer"}, [required: true]},
      {:asset_id, :string, [required: true]}
    ])
  end

  defp text_schema do
    Schema.define([
      {:type, {:literal, :text}, [required: true]},
      {:content, :string, [required: true]}
    ])
  end

  describe "discriminated union type validation" do
    test "requires each variant to define the discriminator field" do
      assert_raise ArgumentError,
                   ~r/must define discriminator field "type"/,
                   fn ->
                     Schema.define([
                       {:detail,
                        {:discriminated_union,
                         [
                           discriminator: "type",
                           variants: %{
                             "broken" => Schema.define([{:value, :string, [required: true]}])
                           }
                         ]}, [required: true]}
                     ])
                   end
    end

    test "requires each variant discriminator field to use a literal type" do
      assert_raise ArgumentError,
                   ~r/discriminator field "type" must be a :literal/,
                   fn ->
                     Schema.define([
                       {:detail,
                        {:discriminated_union,
                         [
                           discriminator: "type",
                           variants: %{
                             "broken" =>
                               Schema.define([
                                 {:type, :string, [required: true]},
                                 {:value, :string, [required: true]}
                               ])
                           }
                         ]}, [required: true]}
                     ])
                   end
    end

    test "requires each variant discriminator literal to match the variant key" do
      assert_raise ArgumentError,
                   ~r/must use literal discriminator value "broken"/,
                   fn ->
                     Schema.define([
                       {:detail,
                        {:discriminated_union,
                         [
                           discriminator: "type",
                           variants: %{
                             "broken" =>
                               Schema.define([
                                 {:type, {:literal, "other"}, [required: true]},
                                 {:value, :string, [required: true]}
                               ])
                           }
                         ]}, [required: true]}
                     ])
                   end
    end

    test "validates correct encoded_text variant" do
      union_type =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "encoded_text" => encoded_text_schema(),
             "image" => image_schema(),
             "image_asset_pointer" => image_pointer_schema()
           }
         ]}

      data = %{"type" => "encoded_text", "tokens" => [1, 2, 3]}

      assert {:ok, validated} = Types.validate(union_type, data, [])
      assert validated["type"] == "encoded_text"
      assert validated["tokens"] == [1, 2, 3]
    end

    test "validates correct image variant" do
      union_type =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "encoded_text" => encoded_text_schema(),
             "image" => image_schema()
           }
         ]}

      data = %{"type" => "image", "data" => "base64data", "format" => "png"}

      assert {:ok, validated} = Types.validate(union_type, data, [])
      assert validated["type"] == "image"
      assert validated["data"] == "base64data"
    end

    test "returns error for unknown discriminator value" do
      union_type =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "encoded_text" => encoded_text_schema(),
             "image" => image_schema()
           }
         ]}

      data = %{"type" => "unknown", "foo" => "bar"}

      assert {:error, [error]} = Types.validate(union_type, data, [])
      assert error.code == :unknown_discriminator
      assert error.message =~ "unknown"
    end

    test "returns error for missing discriminator field" do
      union_type =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "encoded_text" => encoded_text_schema()
           }
         ]}

      data = %{"tokens" => [1, 2, 3]}

      assert {:error, [error]} = Types.validate(union_type, data, [])
      assert error.code == :missing_discriminator
    end

    test "returns variant validation errors with context" do
      union_type =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "encoded_text" => encoded_text_schema()
           }
         ]}

      # Missing required 'tokens' field
      data = %{"type" => "encoded_text"}

      assert {:error, errors} = Types.validate(union_type, data, [])
      assert errors != []
      # Should report the missing tokens field
      assert Enum.any?(errors, fn e -> e.message =~ "tokens" or e.message =~ "required" end)
    end

    test "handles atom discriminator values in variants" do
      union_type =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             :text => text_schema()
           }
         ]}

      data = %{"type" => :text, "content" => "hello"}
      assert {:ok, validated} = Types.validate(union_type, data, [])
      assert validated["content"] == "hello"
    end

    test "works with string key discriminator in data" do
      union_type =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "encoded_text" => encoded_text_schema()
           }
         ]}

      # String keys
      data = %{"type" => "encoded_text", "tokens" => [1]}
      assert {:ok, _} = Types.validate(union_type, data, [])
    end

    test "works with atom key discriminator in options" do
      union_type =
        {:discriminated_union,
         [
           discriminator: :type,
           variants: %{
             "encoded_text" => encoded_text_schema()
           }
         ]}

      # Atom keys in data
      data = %{type: "encoded_text", tokens: [1]}
      assert {:ok, _} = Types.validate(union_type, data, [])
    end

    test "returns error for non-map input" do
      union_type =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "encoded_text" => encoded_text_schema()
           }
         ]}

      assert {:error, [error]} = Types.validate(union_type, "not a map", [])
      assert error.code == :type
    end

    test "preserves path in nested errors" do
      union_type =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "image" => image_schema()
           }
         ]}

      # Invalid format choice
      data = %{"type" => "image", "data" => "base64", "format" => "gif"}

      assert {:error, errors} = Types.validate(union_type, data, ["chunk"])
      assert Enum.any?(errors, fn e -> "chunk" in e.path end)
    end
  end

  describe "discriminated union in schema fields" do
    test "validates discriminated union as field type" do
      chunk_union =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "encoded_text" => encoded_text_schema(),
             "image" => image_schema()
           }
         ]}

      parent_schema =
        Schema.define([
          {:chunks, {:array, chunk_union}, [required: true]}
        ])

      data = %{
        "chunks" => [
          %{"type" => "encoded_text", "tokens" => [1, 2]},
          %{"type" => "image", "data" => "abc", "format" => "png"}
        ]
      }

      assert {:ok, validated} = Validator.validate(parent_schema, data)
      assert length(validated["chunks"]) == 2
    end

    test "reports errors with correct paths for array of discriminated unions" do
      chunk_union =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "encoded_text" => encoded_text_schema(),
             "image" => image_schema()
           }
         ]}

      parent_schema =
        Schema.define([
          {:chunks, {:array, chunk_union}, [required: true]}
        ])

      # Second chunk has invalid variant
      data = %{
        "chunks" => [
          %{"type" => "encoded_text", "tokens" => [1, 2]},
          %{"type" => "unknown_type"}
        ]
      }

      assert {:error, errors} = Validator.validate(parent_schema, data)
      # Should report error at path chunks[1]
      assert Enum.any?(errors, fn e -> 1 in e.path end)
    end
  end

  describe "JSON Schema generation for discriminated unions" do
    test "generates oneOf with discriminator mapping" do
      union_type =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "encoded_text" => encoded_text_schema(),
             "image" => image_schema()
           }
         ]}

      json_schema = Types.to_json_schema(union_type)

      assert json_schema["oneOf"]
      assert length(json_schema["oneOf"]) == 2
      assert json_schema["discriminator"]["propertyName"] == "type"
      assert is_map(json_schema["discriminator"]["mapping"])
    end

    test "includes variant schemas in oneOf" do
      union_type =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "text" => Schema.define([{:type, {:literal, "text"}, []}, {:value, :string, []}])
           }
         ]}

      json_schema = Types.to_json_schema(union_type)

      assert [variant_schema] = json_schema["oneOf"]
      assert variant_schema["type"] == "object"
      assert Map.has_key?(variant_schema["properties"], "type")
    end
  end

  describe "JsonSchema.generate/1 with discriminated union fields" do
    test "generates schema for field containing discriminated union" do
      chunk_union =
        {:discriminated_union,
         [
           discriminator: "type",
           variants: %{
             "encoded_text" => encoded_text_schema()
           }
         ]}

      schema =
        Schema.define([
          {:chunk, chunk_union, [required: true]}
        ])

      json_schema = JsonSchema.generate(schema)

      assert json_schema["properties"]["chunk"]["oneOf"]
      assert json_schema["properties"]["chunk"]["discriminator"]
    end
  end
end
