# Getting Started

Sinter is a runtime-first schema validation library for JSON-shaped data in Elixir.
Schemas are defined once and used for validation, coercion, and JSON Schema generation.
Fields are string-keyed by default to avoid atom leaks when working with external input.

## Installation

Add `sinter` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:sinter, "~> 0.2.0"}
  ]
end
```

Then fetch the dependency:

```
$ mix deps.get
```

## Your First Schema

Schemas are created with `Sinter.Schema.define/2`. Each field is specified as a
`{name, type, options}` tuple:

```elixir
schema = Sinter.Schema.define([
  {:name, :string, [required: true, min_length: 1]},
  {:age, :integer, [optional: true, gt: 0]}
], title: "Person")
```

Field names can be atoms or strings. Internally, Sinter normalizes all field
names to strings so that input data with string keys (typical of decoded JSON)
is matched without creating atoms at runtime.

For compile-time definitions, use the `use Sinter.Schema` DSL:

```elixir
defmodule PersonSchema do
  use Sinter.Schema

  use_schema do
    option :title, "Person"

    field :name, :string, required: true, min_length: 1
    field :age, :integer, optional: true, gt: 0
  end
end

# Access the compiled schema at runtime
PersonSchema.schema()
```

## Validating Data

Pass a schema and a map to `Sinter.Validator.validate/3`. Keys in the input map
can be atoms or strings:

```elixir
schema = Sinter.Schema.define([
  {:name, :string, [required: true]},
  {:age, :integer, [optional: true, gt: 0]}
])

# Successful validation
{:ok, validated} = Sinter.Validator.validate(schema, %{"name" => "Alice", "age" => 30})
# => {:ok, %{"name" => "Alice", "age" => 30}}

# Atom keys are also accepted
{:ok, validated} = Sinter.Validator.validate(schema, %{name: "Alice", age: 30})
```

When validation fails, you receive a list of `Sinter.Error` structs with the
path, error code, and a human-readable message:

```elixir
{:error, errors} = Sinter.Validator.validate(schema, %{"age" => -1})

# errors contains:
# [
#   %Sinter.Error{path: ["name"], code: :required, message: "field is required"},
#   %Sinter.Error{path: ["age"], code: :gt, message: "must be greater than 0"}
# ]

# Format errors for display
Sinter.Error.format_errors(errors)
# => "name: field is required\nage: must be greater than 0"
```

A bang variant, `Sinter.Validator.validate!/3`, raises `Sinter.ValidationError`
on failure.

## Type Coercion

Real-world input often arrives as strings (query parameters, CSV rows, JSON
decoded with string values). Enable coercion with the `coerce: true` option
to automatically convert compatible values:

```elixir
schema = Sinter.Schema.define([
  {:count, :integer, [required: true, gt: 0]}
])

# Without coercion -- "42" is a string, not an integer
{:error, _} = Sinter.Validator.validate(schema, %{"count" => "42"})

# With coercion -- "42" is converted to 42, then validated
{:ok, validated} = Sinter.Validator.validate(schema, %{"count" => "42"}, coerce: true)
# => {:ok, %{"count" => 42}}
```

Coercion is applied before constraint checks, so the converted value is
validated against the full set of constraints.

## Generating JSON Schema

Use `Sinter.JsonSchema.generate/2` to produce a standard JSON Schema from any
Sinter schema:

```elixir
schema = Sinter.Schema.define([
  {:name, :string, [required: true, min_length: 2]},
  {:age, :integer, [optional: true, gt: 0]}
], title: "Person")

json_schema = Sinter.JsonSchema.generate(schema)
# => %{
#   "type" => "object",
#   "title" => "Person",
#   "properties" => %{
#     "name" => %{"type" => "string", "minLength" => 2},
#     "age" => %{"type" => "integer", "exclusiveMinimum" => 0}
#   },
#   "required" => ["name"],
#   "additionalProperties" => true,
#   ...
# }
```

For LLM provider APIs, generate optimized schemas with the
`:optimize_for_provider` option:

```elixir
openai_schema = Sinter.JsonSchema.generate(schema, optimize_for_provider: :openai)
anthropic_schema = Sinter.JsonSchema.generate(schema, optimize_for_provider: :anthropic)
```

You can also validate a generated JSON Schema against the meta-schema:

```elixir
:ok = Sinter.JsonSchema.validate_schema(json_schema)
```

## Next Steps

Now that you have the basics, explore these guides for deeper coverage:

- [Schema Definition](schema-definition.md) -- field types, nested objects, unions, and constraints
- [Validation](validation.md) -- strict mode, batch validation, custom validators, and hooks
- [JSON Schema](json-schema.md) -- drafts, provider optimizations, and reference flattening
- [JSON Serialization](json-serialization.md) -- encoding, decoding, and round-trip workflows
- [DSPEx Integration](dspex-integration.md) -- schema inference, merging, and LLM-oriented validation
