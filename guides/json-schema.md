# JSON Schema Generation

Sinter can convert its schema definitions into standard JSON Schema documents.
This is useful for integrating with LLM providers, generating API documentation,
and validating data interchange formats.

## Basic Generation

Use `Sinter.JsonSchema.generate/2` to convert a Sinter schema into a JSON Schema
map. By default, it produces a Draft 2020-12 schema.

```elixir
schema = Sinter.Schema.define([
  {:name, :string, [required: true, min_length: 2]},
  {:age, :integer, [optional: true, gt: 0]},
  {:tags, {:array, :string}, [optional: true, max_items: 10]}
], title: "User")

json_schema = Sinter.JsonSchema.generate(schema)

# Returns:
# %{
#   "$schema" => "https://json-schema.org/draft/2020-12/schema",
#   "type" => "object",
#   "title" => "User",
#   "properties" => %{
#     "name" => %{"type" => "string", "minLength" => 2},
#     "age" => %{"type" => "integer", "exclusiveMinimum" => 0},
#     "tags" => %{"type" => "array", "items" => %{"type" => "string"}, "maxItems" => 10}
#   },
#   "required" => ["name"],
#   "additionalProperties" => true,
#   "x-sinter-version" => "0.3.0",
#   "x-sinter-field-count" => 3,
#   "x-sinter-created-at" => "2026-03-12T..."
# }
```

Sinter maps its constraint options to their JSON Schema equivalents automatically:

| Sinter constraint | JSON Schema keyword    |
|-------------------|------------------------|
| `min_length`      | `minLength`            |
| `max_length`      | `maxLength`            |
| `gt`              | `exclusiveMinimum`     |
| `gteq`            | `minimum`              |
| `lt`              | `exclusiveMaximum`     |
| `lteq`            | `maximum`              |
| `min_items`       | `minItems`             |
| `max_items`       | `maxItems`             |
| `format` (Regex)  | `pattern`              |
| `choices`         | `enum`                 |

## Draft Selection

Sinter supports two JSON Schema drafts. The default is Draft 2020-12; pass the
`:draft` option to select Draft 7.

```elixir
schema = Sinter.Schema.define([
  {:name, :string, [required: true]}
])

# Draft 2020-12 (default)
d2020 = Sinter.JsonSchema.generate(schema)
d2020["$schema"]
#=> "https://json-schema.org/draft/2020-12/schema"

# Draft 7
d7 = Sinter.JsonSchema.generate(schema, draft: :draft7)
d7["$schema"]
#=> "http://json-schema.org/draft-07/schema#"
```

When you use a provider optimization (`:openai` or `:anthropic`), the draft
defaults to `:draft7` unless you explicitly override it. The `:generic` provider
keeps the default of `:draft2020_12`.

## Provider Optimizations

`Sinter.JsonSchema.for_provider/3` generates a JSON Schema tailored to a
specific LLM provider. It is a convenience wrapper around `generate/2` that
sets `optimize_for_provider` for you.

```elixir
schema = Sinter.Schema.define([
  {:question, :string, [required: true, description: "The user question"]},
  {:answer, :string, [required: true]},
  {:confidence, :float, [optional: true, gteq: 0.0, lteq: 1.0]}
])
```

### OpenAI (function calling)

```elixir
openai_schema = Sinter.JsonSchema.for_provider(schema, :openai)
```

Optimizations applied:

- Sets `additionalProperties: false` at every object level (required by OpenAI's
  strict function calling mode).
- Ensures a `required` array is always present, even when empty.
- Removes formats that OpenAI does not support well (`"date"`, `"time"`,
  `"email"`).
- Simplifies union types (`oneOf`) with more than three variants down to the
  first three, since large unions degrade function calling reliability.
- Defaults to Draft 7.

### Anthropic (tool use)

```elixir
anthropic_schema = Sinter.JsonSchema.for_provider(schema, :anthropic)
```

Optimizations applied:

- Sets `additionalProperties: false` at every object level.
- Ensures a `required` array is always present.
- Removes formats not well-supported by Anthropic (`"uri"`, `"uuid"`).
- Guarantees that every object-typed schema has a `properties` key, even if it
  is an empty map.
- Defaults to Draft 7.

### Generic

```elixir
generic_schema = Sinter.JsonSchema.for_provider(schema, :generic)
```

No provider-specific transformations are applied. The output is identical to
calling `Sinter.JsonSchema.generate/2` directly.

You can also pass additional options as the third argument:

```elixir
Sinter.JsonSchema.for_provider(schema, :openai,
  include_descriptions: false,
  flatten: true
)
```

## Strict Mode

When `strict: true` is set -- either on the schema itself or as a generation
option -- `additionalProperties: false` is applied recursively to every nested
object in the output.

```elixir
schema = Sinter.Schema.define([
  {:profile, {:object, [
    {:name, :string, [required: true]},
    {:address, {:object, [
      {:city, :string, [required: true]}
    ]}, [required: true]}
  ]}, [required: true]}
])

# Without strict mode
relaxed = Sinter.JsonSchema.generate(schema)
relaxed["additionalProperties"]                                          #=> true
relaxed["properties"]["profile"]["additionalProperties"]                 #=> true
relaxed["properties"]["profile"]["properties"]["address"]["additionalProperties"] #=> true

# With strict mode
strict = Sinter.JsonSchema.generate(schema, strict: true)
strict["additionalProperties"]                                           #=> false
strict["properties"]["profile"]["additionalProperties"]                  #=> false
strict["properties"]["profile"]["properties"]["address"]["additionalProperties"] #=> false
```

The `strict` option on `generate/2` overrides whatever the schema's own
`strict` setting is. Provider optimizations for `:openai` and `:anthropic`
always apply recursive strictness regardless of this flag.

## Options

`Sinter.JsonSchema.generate/2` accepts the following options:

| Option                    | Default         | Description                                                                                    |
|---------------------------|-----------------|------------------------------------------------------------------------------------------------|
| `:draft`                  | `:draft2020_12` | JSON Schema draft version (`:draft2020_12` or `:draft7`). Provider targets default to `:draft7`. |
| `:include_descriptions`   | `true`          | Whether to include `description` annotations on fields.                                        |
| `:flatten`                | `false`         | Inline all `$ref` references, producing a self-contained schema.                               |
| `:optimize_for_provider`  | `:generic`      | Apply provider-specific transformations (`:openai`, `:anthropic`, or `:generic`).               |
| `:strict`                 | schema default  | Override the schema's strict setting. Applies `additionalProperties: false` recursively.        |

### Excluding Descriptions

Field descriptions increase token count when schemas are sent to LLM providers.
Disable them to save tokens:

```elixir
schema = Sinter.Schema.define([
  {:name, :string, [required: true, description: "The user's full name"]}
])

compact = Sinter.JsonSchema.generate(schema, include_descriptions: false)

Map.has_key?(compact["properties"]["name"], "description")
#=> false
```

### Flattening References

The `:flatten` option resolves all `$ref` pointers inline, producing a
self-contained document with no external references:

```elixir
Sinter.JsonSchema.generate(schema, flatten: true)
```

## Schema Validation

`Sinter.JsonSchema.validate_schema/2` checks whether a JSON Schema map is
structurally valid by building it with JSV against the appropriate meta-schema.

```elixir
valid = %{
  "type" => "object",
  "properties" => %{
    "name" => %{"type" => "string"}
  },
  "required" => ["name"]
}

:ok = Sinter.JsonSchema.validate_schema(valid)

invalid = %{
  "type" => "not-a-real-type",
  "minLength" => "should-be-integer"
}

{:error, issues} = Sinter.JsonSchema.validate_schema(invalid)
# issues is a list of error message strings
```

You can also specify the draft to validate against:

```elixir
Sinter.JsonSchema.validate_schema(schema_map, draft: :draft7)
Sinter.JsonSchema.validate_schema(schema_map, draft: :draft2020_12)
```

This is useful as a final check before sending generated schemas to an external
service.

## Metadata

Sinter automatically attaches extension metadata to every generated JSON Schema
at the top level:

| Key                    | Value                                          |
|------------------------|------------------------------------------------|
| `x-sinter-version`    | The Sinter library version that generated it.  |
| `x-sinter-field-count` | Number of fields defined in the source schema. |
| `x-sinter-created-at` | ISO 8601 timestamp of when the schema was created. |

```elixir
schema = Sinter.Schema.define([
  {:a, :string, [required: true]},
  {:b, :integer, [optional: true]}
])

json_schema = Sinter.JsonSchema.generate(schema)

json_schema["x-sinter-version"]     #=> "0.3.0"
json_schema["x-sinter-field-count"] #=> 2
json_schema["x-sinter-created-at"]  #=> "2026-03-12T12:00:00.000000Z"
```

These keys use the `x-` extension prefix and are ignored by standard JSON Schema
validators.

## Discriminated Unions

Discriminated unions are emitted as `oneOf` branches with a JSON Schema
`discriminator`. Each branch keeps the same detail you would get from generating
that variant as a standalone schema: nested object properties, aliases,
constraints, descriptions, defaults, examples, and strict
`additionalProperties` settings are all preserved.

```elixir
text_variant = Sinter.Schema.define([
  {:type, {:literal, "text"}, [required: true]},
  {:content, :string, [required: true, min_length: 1]}
])

image_variant = Sinter.Schema.define([
  {:type, {:literal, "image"}, [required: true]},
  {:url, :string, [required: true]},
  {:caption, :string, [optional: true]}
], strict: true)

schema = Sinter.Schema.define([
  {:chunk,
   {:discriminated_union,
    [
      discriminator: "type",
      variants: %{
        "text" => text_variant,
        "image" => image_variant
      }
    ]}, [required: true]}
])

json_schema = Sinter.JsonSchema.generate(schema)
chunk_schema = json_schema["properties"]["chunk"]
```

The discriminator field is always listed as required for each branch, even if a
variant marks it optional, so generated JSON Schema matches Sinter's runtime
selection logic.

Sinter also emits definition entries for discriminator mappings. In Draft
2020-12 output these live under `$defs`; in Draft 7 output they live under
`definitions`.

```elixir
chunk_schema["discriminator"]["mapping"]
#=> %{
#=>   "image" => "#/$defs/properties__chunk__image",
#=>   "text" => "#/$defs/properties__chunk__text"
#=> }

json_schema["$defs"]["properties__chunk__text"]["properties"]["content"]
#=> %{"minLength" => 1, "type" => "string"}
```

## Field Aliases

When a field has an `:alias` option, the alias is used as the property name in
the generated JSON Schema instead of the canonical Elixir field name. This lets
you keep idiomatic snake_case names in Elixir while producing camelCase (or any
other convention) in the JSON output.

```elixir
schema = Sinter.Schema.define([
  {:account_name, :string, [required: true, alias: "accountName"]},
  {:created_at, :datetime, [required: true, alias: "createdAt"]},
  {:is_active, :boolean, [optional: true, alias: "isActive"]}
])

json_schema = Sinter.JsonSchema.generate(schema)

Map.keys(json_schema["properties"])
#=> ["accountName", "createdAt", "isActive"]

json_schema["required"]
#=> ["accountName", "createdAt"]
```

Aliases affect both the `properties` map keys and the `required` array entries.
The canonical field names are still used internally by `Sinter.Validator` when
validating Elixir data.
