#!/usr/bin/env elixir

# Examples covering all functionality from the Sinter README
# This file demonstrates every code example and feature mentioned in the documentation

IO.puts("=== Sinter Comprehensive Examples (README Coverage) ===")
IO.puts("")

# Add the compiled beam files to the path so we can run this as a script (app + deps)
"../_build/dev/lib"
|> Path.expand(__DIR__)
|> Path.join("*/ebin")
|> Path.wildcard()
|> Enum.each(&Code.append_path/1)

# ============================================================================
# 1. SCHEMA DEFINITION
# ============================================================================

IO.puts("1. SCHEMA DEFINITION")
IO.puts("--------------------")

schema =
  Sinter.Schema.define(
    [
      {:name, :string, [required: true, min_length: 2]},
      {:age, :integer, [optional: true, gteq: 0]},
      {:profile,
       {:object,
        [
          {:nickname, :string, [optional: true]},
          {:joined_at, :datetime, [optional: true]}
        ]}, [optional: true]}
    ],
    strict: true
  )

IO.puts("✓ Runtime schema created")
IO.puts("  Fields: #{inspect(Map.keys(schema.fields))}")

# Compile-time schema definition

defmodule UserSchema do
  use Sinter.Schema

  use_schema do
    option :title, "User"
    option :strict, true

    field :name, :string, required: true
    field :age, :integer, optional: true, gteq: 0
  end
end

compiled_schema = UserSchema.schema()
IO.puts("✓ Compile-time schema created with title: #{compiled_schema.config.title}")
IO.puts("")

# ============================================================================
# 2. VALIDATION
# ============================================================================

IO.puts("2. VALIDATION")
IO.puts("------------")

{:ok, validated} =
  Sinter.Validator.validate(
    schema,
    %{
      "name" => "Ada",
      "age" => "36",
      "profile" => %{"joined_at" => "2024-01-01T12:00:00Z"}
    },
    coerce: true
  )

IO.puts("✓ Validation successful")
IO.puts("  Name: #{validated["name"]}")
IO.puts("")

# ============================================================================
# 3. JSON ENCODE/DECODE HELPERS
# ============================================================================

IO.puts("3. JSON ENCODE/DECODE HELPERS")
IO.puts("-----------------------------")

payload = %{
  name: "Ada",
  profile: %{
    nickname: Sinter.NotGiven.omit(),
    joined_at: ~N[2024-01-01 12:00:00]
  }
}

{:ok, json} = Sinter.JSON.encode(payload, formats: %{joined_at: :iso8601})

{:ok, decoded} = Sinter.JSON.decode(json, schema, coerce: true)
IO.puts("✓ JSON encoded and decoded")
IO.puts("  Name: #{decoded["name"]}")

{:ok, _aliased_json} =
  Sinter.JSON.encode(payload,
    aliases: %{name: "full_name"},
    formats: %{joined_at: :iso8601}
  )

IO.puts("")

# ============================================================================
# 4. JSON SCHEMA GENERATION
# ============================================================================

IO.puts("4. JSON SCHEMA GENERATION")
IO.puts("-------------------------")

json_schema = Sinter.JsonSchema.generate(schema)
openai_schema = Sinter.JsonSchema.for_provider(schema, :openai)

IO.puts("✓ Default draft: #{json_schema["$schema"]}")
IO.puts("✓ Provider draft: #{openai_schema["$schema"]}")

:ok = Sinter.JsonSchema.validate_schema(json_schema)
IO.puts("✓ JSON Schema validated")

text_chunk =
  Sinter.Schema.define([
    {:type, {:literal, "text"}, [required: true]},
    {:content, :string, [required: true, min_length: 1]}
  ])

image_chunk =
  Sinter.Schema.define(
    [
      {:type, {:literal, "image"}, [required: true]},
      {:url, :string, [required: true]},
      {:alt, :string, [optional: true]}
    ],
    strict: true
  )

chunk_envelope =
  Sinter.Schema.define([
    {:chunk,
     {:discriminated_union,
      [
        discriminator: "type",
        variants: %{
          "text" => text_chunk,
          "image" => image_chunk
        }
      ]}, [required: true]}
  ])

chunk_json_schema = Sinter.JsonSchema.generate(chunk_envelope)
chunk_schema = chunk_json_schema["properties"]["chunk"]

IO.puts("✓ Discriminated union schema generated")
IO.puts("  Branches: #{length(chunk_schema["oneOf"])}")
IO.puts("  Mapping keys: #{inspect(Map.keys(chunk_schema["discriminator"]["mapping"]))}")
IO.puts("")

# ============================================================================
# 5. CONVENIENCE HELPERS
# ============================================================================

IO.puts("5. CONVENIENCE HELPERS")
IO.puts("----------------------")

{:ok, 42} = Sinter.validate_type(:integer, "42", coerce: true)

{:ok, "user@example.com"} =
  Sinter.validate_value(:email, :string, "user@example.com", format: ~r/@/)

{:ok, values} =
  Sinter.validate_many([
    {:string, "hello"},
    {:integer, 42},
    {:email, :string, "test@example.com", [format: ~r/@/]}
  ])

IO.puts("✓ Convenience helpers validated: #{inspect(values)}")
IO.puts("")

# ============================================================================
# 6. DYNAMIC SCHEMA CREATION
# ============================================================================

IO.puts("6. DYNAMIC SCHEMA CREATION")
IO.puts("--------------------------")

examples = [
  %{"name" => "Alice", "age" => 30},
  %{"name" => "Bob", "age" => 25}
]

inferred_schema = Sinter.infer_schema(examples)
IO.puts("✓ Inferred fields: #{inspect(Map.keys(inferred_schema.fields))}")

input_schema = Sinter.Schema.define([{:query, :string, [required: true]}])
output_schema = Sinter.Schema.define([{:answer, :string, [required: true]}])
program_schema = Sinter.merge_schemas([input_schema, output_schema])

IO.puts("✓ Merged fields: #{inspect(Map.keys(program_schema.fields))}")
IO.puts("")

IO.puts("=== All README Examples Completed Successfully! ===")
