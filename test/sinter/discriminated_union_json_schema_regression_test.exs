defmodule Sinter.DiscriminatedUnionJsonSchemaRegressionTest do
  use ExUnit.Case, async: true

  alias Sinter.{JsonSchema, Schema, Types}

  defp union_type(variants) do
    {:discriminated_union,
     [
       discriminator: "type",
       variants: variants
     ]}
  end

  defp generated_union_schema(variants) do
    Schema.define([
      {:detail, union_type(variants), [required: true]}
    ])
    |> JsonSchema.generate()
    |> get_in(["properties", "detail"])
  end

  defp direct_union_schema(variants) do
    Types.to_json_schema(union_type(variants))
  end

  defp variant_schema!(union_schema, discriminator_value) do
    Enum.find(union_schema["oneOf"], fn variant ->
      get_in(variant, ["properties", "type", "const"]) == discriminator_value
    end) || flunk("missing variant #{inspect(discriminator_value)} in #{inspect(union_schema)}")
  end

  defp desc_variant do
    Schema.define([
      {:type, {:literal, "desc"}, [required: true]},
      {:content, :string, [required: true, description: "Description of the first item"]}
    ])
  end

  defp nested_detail_schema do
    Schema.define(
      [
        {:title, :string, [required: true, description: "Nested title"]},
        {:description, :string, [optional: true]}
      ],
      title: "Nested Detail",
      description: "Nested detail schema",
      strict: true
    )
  end

  defp nested_variant do
    Schema.define(
      [
        {:type, {:literal, "nested"}, [required: true]},
        {:detail, {:object, nested_detail_schema()},
         [required: true, description: "Detailed nested payload"]}
      ],
      title: "Nested Variant",
      description: "Variant with a nested object",
      strict: true
    )
  end

  defp constrained_variant do
    Schema.define([
      {:type, {:literal, "constrained"}, [required: true]},
      {:email, :string, [required: true, format: ~r/.+@.+/, description: "Notification email"]},
      {:status, :string, [required: true, choices: ["draft", "published"]]},
      {:count, :integer, [optional: true, gteq: 1, lteq: 5]},
      {:tags, {:array, :string}, [required: true, min_items: 1, max_items: 3]}
    ])
  end

  defp aliased_variant do
    Schema.define([
      {:type, {:literal, "aliased"}, [required: true]},
      {:account_name, :string, [required: true, alias: "accountName", min_length: 3]}
    ])
  end

  defp documented_variant do
    Schema.define([
      {:type, {:literal, "documented"}, [required: true]},
      {:summary, :string, [required: true, example: "Hello world"]},
      {:enabled, :boolean, [optional: true, default: true]}
    ])
  end

  describe "JsonSchema.generate/1 discriminated union regressions" do
    test "preserves field descriptions inside discriminated union variants" do
      union_schema = generated_union_schema(%{"desc" => desc_variant()})
      desc_schema = variant_schema!(union_schema, "desc")

      assert get_in(desc_schema, ["properties", "content", "description"]) ==
               "Description of the first item"
    end

    test "preserves nested object properties and required fields inside discriminated union variants" do
      union_schema = generated_union_schema(%{"nested" => nested_variant()})
      nested_schema = variant_schema!(union_schema, "nested")
      detail_schema = nested_schema["properties"]["detail"]

      assert detail_schema["type"] == "object"
      assert get_in(detail_schema, ["properties", "title", "type"]) == "string"
      assert get_in(detail_schema, ["properties", "description", "type"]) == "string"
      assert detail_schema["required"] == ["title"]
    end

    test "preserves nested field and schema metadata inside discriminated union variants" do
      union_schema = generated_union_schema(%{"nested" => nested_variant()})
      nested_schema = variant_schema!(union_schema, "nested")
      detail_schema = nested_schema["properties"]["detail"]

      assert nested_schema["title"] == "Nested Variant"
      assert nested_schema["description"] == "Variant with a nested object"
      assert detail_schema["title"] == "Nested Detail"
      assert detail_schema["description"] == "Detailed nested payload"
      assert get_in(detail_schema, ["properties", "title", "description"]) == "Nested title"
    end

    test "preserves field constraints inside discriminated union variants" do
      union_schema = generated_union_schema(%{"constrained" => constrained_variant()})
      constrained_schema = variant_schema!(union_schema, "constrained")
      properties = constrained_schema["properties"]

      assert properties["email"]["pattern"] == ".+@.+"
      assert properties["status"]["enum"] == ["draft", "published"]
      assert properties["count"]["minimum"] == 1
      assert properties["count"]["maximum"] == 5
      assert properties["tags"]["minItems"] == 1
      assert properties["tags"]["maxItems"] == 3
    end

    test "preserves field aliases inside discriminated union variants" do
      union_schema = generated_union_schema(%{"aliased" => aliased_variant()})
      aliased_schema = variant_schema!(union_schema, "aliased")

      assert Map.has_key?(aliased_schema["properties"], "accountName")
      refute Map.has_key?(aliased_schema["properties"], "account_name")
      assert Enum.sort(aliased_schema["required"]) == ["accountName", "type"]
    end

    test "preserves examples and defaults inside discriminated union variants" do
      union_schema = generated_union_schema(%{"documented" => documented_variant()})
      documented_schema = variant_schema!(union_schema, "documented")
      properties = documented_schema["properties"]

      assert properties["summary"]["examples"] == ["Hello world"]
      assert properties["enabled"]["default"] == true
    end

    test "preserves strict additionalProperties settings inside discriminated union variants" do
      union_schema = generated_union_schema(%{"nested" => nested_variant()})
      nested_schema = variant_schema!(union_schema, "nested")

      assert nested_schema["additionalProperties"] == false
      assert nested_schema["properties"]["detail"]["additionalProperties"] == false
    end
  end

  describe "Types.to_json_schema/1 discriminated union regressions" do
    test "retains nested object detail when serializing variant schemas directly" do
      union_schema = direct_union_schema(%{"nested" => nested_variant()})
      nested_schema = variant_schema!(union_schema, "nested")
      detail_schema = nested_schema["properties"]["detail"]

      assert detail_schema["type"] == "object"
      assert get_in(detail_schema, ["properties", "title", "type"]) == "string"
      assert detail_schema["title"] == "Nested Detail"
      assert detail_schema["additionalProperties"] == false
    end
  end
end
