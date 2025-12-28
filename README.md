<p align="center">
  <img src="assets/sinter.svg" width="200" height="200" alt="Sinter logo" />
</p>

# Sinter

**Unified schema definition, validation, and JSON Schema for Elixir**

[![CI](https://github.com/nshkrdotcom/sinter/actions/workflows/ci.yml/badge.svg)](https://github.com/nshkrdotcom/sinter/actions/workflows/ci.yml)

Sinter is a runtime-first schema library for JSON-shaped data. Schemas are defined once and used for
validation, coercion, and JSON Schema generation. By default, schema fields are string-keyed to avoid
atom leaks and to match JSON wire formats.

## Highlights

- String-keyed schema fields by default (safe for untrusted input)
- Nested object schemas with `Schema.object/1` and `{:object, ...}`
- Dual JSON Schema drafts (2020-12 default, Draft 7 for providers)
- JSON encode/decode helpers with aliasing and omit/nil handling
- JSV-backed JSON Schema validation

## Installation

Add `sinter` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sinter, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
schema = Sinter.Schema.define([
  {:name, :string, [required: true, min_length: 2]},
  {:age, :integer, [optional: true, gteq: 0]},
  {:profile,
   {:object,
    [
      {:nickname, :string, [optional: true]},
      {:joined_at, :datetime, [optional: true]}
    ]}, [optional: true]}
], strict: true)

{:ok, validated} =
  Sinter.Validator.validate(schema, %{
    "name" => "Ada",
    "age" => "36",
    "profile" => %{"joined_at" => "2024-01-01T12:00:00Z"}
  }, coerce: true)

validated["name"]
# => "Ada"
```

## Schema Definition

Sinter accepts atom or string field names but stores them internally as strings.

```elixir
# Runtime schema definition
schema = Sinter.Schema.define([
  {:title, :string, [required: true]},
  {:tags, {:array, :string}, [optional: true, min_items: 1]}
])

# Compile-time schema definition (same engine under the hood)
defmodule PostSchema do
  use Sinter.Schema

  use_schema do
    option :title, "Post"
    option :strict, true

    field :title, :string, required: true
    field :tags, {:array, :string}, optional: true, min_items: 1
  end
end
```

### Nested Objects

Use `Schema.object/1` (or `{:object, field_specs}`) to model structured data.

```elixir
address = Sinter.Schema.object([
  {:street, :string, [required: true]},
  {:zip, :string, [required: true]}
])

schema = Sinter.Schema.define([
  {:name, :string, [required: true]},
  {:address, address, [required: true]}
])
```

## Validation

```elixir
{:ok, data} = Sinter.Validator.validate(schema, %{
  "name" => "Ada",
  "address" => %{"street" => "Main", "zip" => "12345"}
})
```

## JSON Encode/Decode Helpers

`Sinter.JSON` combines the transform pipeline with JSON encoding/decoding.

```elixir
payload = %{
  name: "Ada",
  profile: %{
    nickname: Sinter.NotGiven.omit(),
    joined_at: ~N[2024-01-01 12:00:00]
  }
}

{:ok, json} = Sinter.JSON.encode(payload, formats: %{joined_at: :iso8601})
{:ok, decoded} = Sinter.JSON.decode(json, schema, coerce: true)

# Aliases are applied for outbound payloads
{:ok, json} =
  Sinter.JSON.encode(payload,
    aliases: %{name: "full_name"},
    formats: %{joined_at: :iso8601}
  )
```

## JSON Schema Generation

```elixir
json_schema = Sinter.JsonSchema.generate(schema)
# Draft 2020-12 by default

openai_schema = Sinter.JsonSchema.for_provider(schema, :openai)
# Draft 7 + recursive strictness for provider expectations

json_schema = Sinter.JsonSchema.generate(schema, draft: :draft7)
:ok = Sinter.JsonSchema.validate_schema(json_schema)
```

## Convenience Helpers

```elixir
{:ok, 42} = Sinter.validate_type(:integer, "42", coerce: true)
{:ok, "user@example.com"} =
  Sinter.validate_value(:email, :string, "user@example.com", format: ~r/@/)

{:ok, values} =
  Sinter.validate_many([
    {:string, "hello"},
    {:integer, 42},
    {:email, :string, "test@example.com", [format: ~r/@/]}
  ])
```

## Dynamic Schema Creation

```elixir
examples = [
  %{"name" => "Alice", "age" => 30},
  %{"name" => "Bob", "age" => 25}
]

schema = Sinter.infer_schema(examples)

input_schema = Sinter.Schema.define([{:query, :string, [required: true]}])
output_schema = Sinter.Schema.define([{:answer, :string, [required: true]}])
program_schema = Sinter.merge_schemas([input_schema, output_schema])
```

## Examples

Run everything at once:

```bash
examples/run_all.sh
```

Or run individual scripts from `examples/`:

- `basic_usage.exs`
- `readme_comprehensive.exs`
- `json_schema_generation.exs`
- `advanced_validation.exs`
- `dspy_integration.exs`

## License

MIT
