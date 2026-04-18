#!/usr/bin/env elixir

# Discriminated union JSON Schema examples for Sinter
# Demonstrates runtime validation, branch fidelity, discriminator mappings,
# and generated-schema validation for discriminated unions.

IO.puts("=== Sinter Discriminated Union JSON Schema Examples ===")
IO.puts("")

# Add the compiled beam files to the path (app + deps)
"../_build/dev/lib"
|> Path.expand(__DIR__)
|> Path.join("*/ebin")
|> Path.wildcard()
|> Enum.each(&Code.append_path/1)

resolve_ref = fn schema, "#/" <> pointer ->
  pointer
  |> String.split("/", trim: true)
  |> Enum.map(fn segment ->
    segment
    |> String.replace("~1", "/")
    |> String.replace("~0", "~")
  end)
  |> Enum.reduce(schema, fn segment, acc -> Map.fetch!(acc, segment) end)
end

# ============================================================================
# 1. DEFINE DISCRIMINATED UNION VARIANTS
# ============================================================================

IO.puts("1. Defining Discriminated Union Variants")
IO.puts("----------------------------------------")

text_chunk =
  Sinter.Schema.define(
    [
      {:type, {:literal, "text"}, [required: true]},
      {:content, :string,
       [
         required: true,
         min_length: 1,
         description: "Rendered text content",
         example: "Hello from Sinter"
       ]},
      {:language, :string, [optional: true, default: "en", choices: ["en", "es", "fr"]]}
    ],
    title: "TextChunk",
    description: "Chunk containing plain text"
  )

image_metadata =
  Sinter.Schema.define(
    [
      {:width, :integer, [required: true, gteq: 1]},
      {:height, :integer, [required: true, gteq: 1]},
      {:caption, :string, [optional: true]}
    ],
    strict: true,
    title: "ImageMetadata"
  )

image_chunk =
  Sinter.Schema.define(
    [
      {:type, {:literal, "image"}, [required: true]},
      {:asset_id, :string, [required: true, alias: "assetId"]},
      {:metadata, {:object, image_metadata}, [required: true]}
    ],
    title: "ImageChunk",
    description: "Chunk referencing an image asset",
    strict: true
  )

schema =
  Sinter.Schema.define(
    [
      {:chunk,
       {:discriminated_union,
        [
          discriminator: "type",
          variants: %{
            "text" => text_chunk,
            "image" => image_chunk
          }
        ]}, [required: true]}
    ],
    title: "ChunkEnvelope"
  )

IO.puts("✓ Built two variants with matching literal discriminators")
IO.puts("  Variants: text, image")
IO.puts("")

# ============================================================================
# 2. RUNTIME VALIDATION
# ============================================================================

IO.puts("2. Runtime Validation")
IO.puts("---------------------")

valid_runtime_payload = %{
  "chunk" => %{
    "type" => "image",
    "asset_id" => "asset-123",
    "metadata" => %{"width" => 1200, "height" => 800}
  }
}

{:ok, validated_payload} = Sinter.Validator.validate(schema, valid_runtime_payload)

IO.puts("✓ Runtime validator accepted the valid image payload")
IO.puts("  Canonical asset field: #{validated_payload["chunk"]["asset_id"]}")

invalid_runtime_payload = %{
  "chunk" => %{
    "type" => "image",
    "asset_id" => "asset-123",
    "metadata" => %{"width" => 1200}
  }
}

case Sinter.Validator.validate(schema, invalid_runtime_payload) do
  {:ok, _} ->
    IO.puts("✗ Unexpected runtime validation success")

  {:error, errors} ->
    IO.puts("✓ Runtime validator rejected invalid nested payload")
    IO.puts("  First error: #{List.first(errors).message}")
end

IO.puts("")

# ============================================================================
# 3. GENERATED JSON SCHEMA FIDELITY
# ============================================================================

IO.puts("3. Generated JSON Schema Fidelity")
IO.puts("---------------------------------")

json_schema = Sinter.JsonSchema.generate(schema)
chunk_schema = json_schema["properties"]["chunk"]

text_ref = chunk_schema["discriminator"]["mapping"]["text"]
image_ref = chunk_schema["discriminator"]["mapping"]["image"]

text_branch = resolve_ref.(json_schema, text_ref)
image_branch = resolve_ref.(json_schema, image_ref)

IO.puts("✓ Discriminator mappings resolve into concrete branch definitions")
IO.puts("  text ref: #{text_ref}")
IO.puts("  image ref: #{image_ref}")
IO.puts("  oneOf branch count: #{length(chunk_schema["oneOf"])}")
IO.puts("  top-level definition count: #{map_size(json_schema["$defs"])}")

IO.puts("")
IO.puts("✓ Text branch keeps descriptions, examples, defaults, and constraints")
IO.puts("  title: #{text_branch["title"]}")
IO.puts("  content description: #{get_in(text_branch, ["properties", "content", "description"])}")
IO.puts("  content example: #{inspect(get_in(text_branch, ["properties", "content", "examples"]))}")
IO.puts("  language default: #{get_in(text_branch, ["properties", "language", "default"])}")
IO.puts("  content minLength: #{get_in(text_branch, ["properties", "content", "minLength"])}")

IO.puts("")
IO.puts("✓ Image branch keeps aliases and strict nested object rules")
IO.puts("  branch title: #{image_branch["title"]}")
IO.puts("  property keys: #{inspect(Map.keys(image_branch["properties"]))}")

IO.puts(
  "  nested strict additionalProperties: #{get_in(image_branch, ["properties", "metadata", "additionalProperties"])}"
)

IO.puts("")

# ============================================================================
# 4. VALIDATING DATA AGAINST THE GENERATED SCHEMA
# ============================================================================

IO.puts("4. Validating Data Against the Generated Schema")
IO.puts("-----------------------------------------------")

compiled_root = JSV.build!(json_schema)

valid_wire_payload = %{
  "chunk" => %{
    "type" => "image",
    "assetId" => "asset-123",
    "metadata" => %{"width" => 1200, "height" => 800}
  }
}

invalid_wire_payload = %{
  "chunk" => %{
    "type" => "image",
    "assetId" => "asset-123",
    "metadata" => %{"width" => 1200}
  }
}

case JSV.validate(valid_wire_payload, compiled_root) do
  {:ok, _} ->
    IO.puts("✓ Generated JSON Schema accepts the valid wire-format payload")

  {:error, error} ->
    IO.puts("✗ Unexpected generated-schema validation failure: #{inspect(error)}")
end

case JSV.validate(invalid_wire_payload, compiled_root) do
  {:ok, _} ->
    IO.puts("✗ Unexpected generated-schema validation success")

  {:error, _error} ->
    IO.puts("✓ Generated JSON Schema rejects the invalid nested wire-format payload")
end

IO.puts("")

# ============================================================================
# 5. PROVIDER-OPTIMIZED OUTPUT
# ============================================================================

IO.puts("5. Provider-Optimized Output")
IO.puts("----------------------------")

openai_schema = Sinter.JsonSchema.for_provider(schema, :openai)
openai_chunk_schema = openai_schema["properties"]["chunk"]

openai_image_branch =
  resolve_ref.(openai_schema, openai_chunk_schema["discriminator"]["mapping"]["image"])

IO.puts("✓ OpenAI output uses Draft 7 definitions and keeps strict branch schemas")
IO.puts("  draft: #{openai_schema["$schema"]}")
IO.puts("  definitions key present: #{Map.has_key?(openai_schema, "definitions")}")
IO.puts("  image branch additionalProperties: #{openai_image_branch["additionalProperties"]}")
IO.puts("")

IO.puts("=== Discriminated Union JSON Schema Examples Complete ===")
