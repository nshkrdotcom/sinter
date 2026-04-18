defmodule Sinter.DiscriminatedUnionJsonSchemaValidationRegressionTest do
  use ExUnit.Case, async: true

  alias Sinter.{JsonSchema, Schema, Types}

  defp union_type(variants, discriminator) do
    {:discriminated_union,
     [
       discriminator: discriminator,
       variants: variants
     ]}
  end

  defp generated_union_root(variants), do: generated_union_root(variants, "type")

  defp generated_union_root(variants, discriminator) do
    Schema.define([
      {:detail, union_type(variants, discriminator), [required: true]}
    ])
    |> JsonSchema.generate()
  end

  defp validate_generated_union(variants, value, discriminator \\ "type") do
    root = generated_union_root(variants, discriminator) |> JSV.build!()
    JSV.validate(%{"detail" => value}, root)
  end

  defp validate_standalone_variant(schema, value) do
    root = JsonSchema.generate(schema) |> JSV.build!()
    JSV.validate(value, root)
  end

  defp generated_union_schema(variants, discriminator \\ "type") do
    generated_union_root(variants, discriminator)
    |> get_in(["properties", "detail"])
  end

  defp resolve_local_pointer!(schema, "#/" <> pointer) do
    pointer
    |> String.split("/", trim: true)
    |> Enum.map(fn segment ->
      segment
      |> String.replace("~1", "/")
      |> String.replace("~0", "~")
    end)
    |> Enum.reduce(schema, fn segment, acc ->
      case acc do
        %{^segment => value} ->
          value

        _ ->
          flunk("unresolvable JSON pointer #/#{pointer} in #{inspect(schema)}")
      end
    end)
  end

  defp variant_schema!(union_schema, discriminator_value) do
    Enum.find(union_schema["oneOf"], fn variant ->
      get_in(variant, ["properties", "type", "const"]) == discriminator_value or
        get_in(variant, ["properties", "kind", "const"]) == discriminator_value
    end) || flunk("missing variant #{inspect(discriminator_value)} in #{inspect(union_schema)}")
  end

  defp normalize_standalone_schema(schema) do
    schema
    |> JsonSchema.generate()
    |> Map.drop(["$schema", "x-sinter-version", "x-sinter-field-count", "x-sinter-created-at"])
  end

  defp nested_detail_schema do
    Schema.define(
      [
        {:title, :string, [required: true]},
        {:description, :string, [optional: true]}
      ],
      strict: true
    )
  end

  defp nested_variant do
    Schema.define(
      [
        {:type, {:literal, "nested"}, [required: true]},
        {:detail, {:object, nested_detail_schema()}, [required: true]}
      ],
      strict: true
    )
  end

  defp constrained_variant do
    Schema.define([
      {:type, {:literal, "constrained"}, [required: true]},
      {:email, :string, [required: true, format: ~r/.+@.+/]},
      {:status, :string, [required: true, choices: ["draft", "published"]]},
      {:count, :integer, [optional: true, gteq: 1, lteq: 5]}
    ])
  end

  defp aliased_variant do
    Schema.define([
      {:type, {:literal, "aliased"}, [required: true]},
      {:account_name, :string, [required: true, alias: "accountName", min_length: 3]}
    ])
  end

  defp optional_discriminator_variant do
    Schema.define([
      {:kind, {:literal, "fallback"}, [optional: true]},
      {:value, :string, [required: true]}
    ])
  end

  describe "validator-driven discriminated union JSON Schema regressions" do
    test "rejects missing nested required fields the same way standalone schemas do" do
      invalid_value = %{"type" => "nested", "detail" => %{}}

      assert {:error, _} = validate_standalone_variant(nested_variant(), invalid_value)
      assert {:error, _} = validate_generated_union(%{"nested" => nested_variant()}, invalid_value)
    end

    test "rejects unknown nested properties for strict variants" do
      invalid_value = %{"type" => "nested", "detail" => %{"title" => "ok", "extra" => 1}}

      assert {:error, _} = validate_standalone_variant(nested_variant(), invalid_value)
      assert {:error, _} = validate_generated_union(%{"nested" => nested_variant()}, invalid_value)
    end

    test "rejects enum violations inside discriminated union variants" do
      invalid_value = %{
        "type" => "constrained",
        "email" => "person@example.com",
        "status" => "invalid-status"
      }

      assert {:error, _} = validate_standalone_variant(constrained_variant(), invalid_value)

      assert {:error, _} =
               validate_generated_union(%{"constrained" => constrained_variant()}, invalid_value)
    end

    test "rejects numeric bounds violations inside discriminated union variants" do
      below_minimum = %{
        "type" => "constrained",
        "email" => "person@example.com",
        "status" => "draft",
        "count" => 0
      }

      above_maximum = %{
        "type" => "constrained",
        "email" => "person@example.com",
        "status" => "draft",
        "count" => 9
      }

      assert {:error, _} = validate_standalone_variant(constrained_variant(), below_minimum)
      assert {:error, _} = validate_standalone_variant(constrained_variant(), above_maximum)

      assert {:error, _} =
               validate_generated_union(%{"constrained" => constrained_variant()}, below_minimum)

      assert {:error, _} =
               validate_generated_union(%{"constrained" => constrained_variant()}, above_maximum)
    end

    test "rejects regex pattern violations inside discriminated union variants" do
      invalid_value = %{
        "type" => "constrained",
        "email" => "not-an-email",
        "status" => "draft"
      }

      assert {:error, _} = validate_standalone_variant(constrained_variant(), invalid_value)

      assert {:error, _} =
               validate_generated_union(%{"constrained" => constrained_variant()}, invalid_value)
    end

    test "uses alias keys consistently with standalone variant schemas" do
      alias_payload = %{"type" => "aliased", "accountName" => "valid-name"}
      canonical_payload = %{"type" => "aliased", "account_name" => "valid-name"}

      assert {:ok, _} = validate_standalone_variant(aliased_variant(), alias_payload)
      assert {:error, _} = validate_standalone_variant(aliased_variant(), canonical_payload)

      assert {:ok, _} = validate_generated_union(%{"aliased" => aliased_variant()}, alias_payload)

      assert {:error, _} =
               validate_generated_union(%{"aliased" => aliased_variant()}, canonical_payload)
    end

    test "preserves string length validation when aliases are present" do
      invalid_value = %{"type" => "aliased", "accountName" => "ab"}

      assert {:error, _} = validate_standalone_variant(aliased_variant(), invalid_value)

      assert {:error, _} =
               validate_generated_union(%{"aliased" => aliased_variant()}, invalid_value)
    end

    test "requires the discriminator in generated schemas the same way runtime validation does" do
      variants = %{"fallback" => optional_discriminator_variant()}
      invalid_value = %{"value" => "ok"}

      assert {:error, _} = Types.validate(union_type(variants, "kind"), invalid_value, [])
      assert {:error, _} = validate_generated_union(variants, invalid_value, "kind")
    end
  end

  describe "discriminated union branch invariants" do
    test "each generated branch matches the standalone schema for that variant" do
      variants = %{
        "nested" => nested_variant(),
        "constrained" => constrained_variant(),
        "aliased" => aliased_variant()
      }

      union_schema = generated_union_schema(variants)

      for {discriminator_value, variant} <- variants do
        assert variant_schema!(union_schema, discriminator_value) ==
                 normalize_standalone_schema(variant)
      end
    end

    test "discriminator mappings resolve to concrete schemas in the generated document" do
      variants = %{
        "nested" => nested_variant(),
        "constrained" => constrained_variant()
      }

      root_schema = generated_union_root(variants)
      union_schema = get_in(root_schema, ["properties", "detail"])

      for {discriminator_value, ref} <- union_schema["discriminator"]["mapping"] do
        assert resolve_local_pointer!(root_schema, ref) ==
                 variant_schema!(union_schema, discriminator_value)
      end
    end
  end
end
