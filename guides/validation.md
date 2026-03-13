# Validation

This guide covers the Sinter validation system, from basic usage through
batch processing and error handling.

## Validation Pipeline

Every call to `Sinter.Validator.validate/3` runs a 5-step pipeline:

1. **Input Validation** -- Ensures the input is a valid map.
2. **Required Field Check** -- Verifies all required fields are present.
3. **Field Validation** -- Validates each field against its type and constraints.
4. **Strict Mode Check** -- Rejects unknown fields when strict mode is enabled.
5. **Post Validation** -- Runs custom cross-field validation if configured.

The pipeline short-circuits on the first step that produces errors, so later
steps never run against invalid data.

## Basic Validation

Use `Sinter.Validator.validate/3` to validate a map against a schema. It
returns `{:ok, validated_data}` on success or `{:error, errors}` on failure.

```elixir
schema = Sinter.Schema.define([
  {:name, :string, [required: true, min_length: 2]},
  {:age, :integer, [optional: true, gt: 0]}
])

# Successful validation
{:ok, validated} = Sinter.Validator.validate(schema, %{name: "Alice", age: 30})
# => {:ok, %{"name" => "Alice", "age" => 30}}

# Validation failure -- missing required field
{:error, errors} = Sinter.Validator.validate(schema, %{age: 30})
# errors contains a %Sinter.Error{path: ["name"], code: :required, ...}
```

Keys in the input map can be atoms or strings. Sinter normalizes all keys to
strings internally.

## Bang Variant

`Sinter.Validator.validate!/3` returns the validated data directly on success
and raises `Sinter.ValidationError` on failure.

```elixir
# Returns the validated map
validated = Sinter.Validator.validate!(schema, %{name: "Alice", age: 30})

# Raises Sinter.ValidationError
try do
  Sinter.Validator.validate!(schema, %{age: -1})
rescue
  e in Sinter.ValidationError ->
    IO.puts(e.message)
    # => "Validation failed with 2 errors:\nname: field is required\nage: must be greater than 0"

    # Access structured errors programmatically
    Enum.each(e.errors, fn error ->
      IO.inspect({error.path, error.code})
    end)
end
```

## Type Coercion

Pass `coerce: true` to automatically convert compatible types before
validation. Coercion is safe and predictable -- it never raises and only
performs well-defined conversions.

```elixir
schema = Sinter.Schema.define([
  {:count, :integer, [required: true]},
  {:ratio, :float, [required: true]},
  {:active, :boolean, [required: true]},
  {:label, :string, [required: true]}
])

{:ok, validated} = Sinter.Validator.validate(schema, %{
  count: "42",
  ratio: "3.14",
  active: "true",
  label: :hello
}, coerce: true)

# validated => %{"count" => 42, "ratio" => 3.14, "active" => true, "label" => "hello"}
```

### Supported Coercions

| Target Type | Accepted Source Types                            |
|-------------|--------------------------------------------------|
| `:string`   | atom, integer, float, boolean                    |
| `:integer`  | string (parseable, e.g. `"42"`)                  |
| `:float`    | string (parseable), integer                      |
| `:boolean`  | `"true"` / `"false"` strings                     |
| `:atom`     | string (must be an existing atom)                 |
| `:date`     | `Date` struct (converted to ISO 8601 string)      |
| `:datetime` | `DateTime` / `NaiveDateTime` (to ISO 8601 string) |

When coercion fails, you receive a `Sinter.Error` with `code: :coercion`:

```elixir
{:error, [error]} = Sinter.Validator.validate(
  Sinter.Schema.define([{:n, :integer, []}]),
  %{n: "not_a_number"},
  coerce: true
)

error.code    # => :coercion
error.message # => "cannot coerce 'not_a_number' to integer"
```

## Strict Mode

By default, Sinter ignores fields in the input that are not defined in the
schema. Enable strict mode to reject unknown fields.

Strict mode can be set at schema level or per-call:

```elixir
# Schema-level strict mode
schema = Sinter.Schema.define(
  [{:name, :string, [required: true]}],
  strict: true
)

{:error, [error]} = Sinter.Validator.validate(schema, %{name: "Alice", extra: "field"})
error.code    # => :strict
error.message # => "unexpected fields: [\"extra\"]"

# Per-call strict mode (overrides the schema setting)
schema = Sinter.Schema.define([{:name, :string, [required: true]}])

{:error, _} = Sinter.Validator.validate(schema, %{name: "Alice", extra: 1}, strict: true)
```

## Pre/Post Validation Hooks

### Pre-Validation

The `pre_validate` function transforms raw input data before the validation
pipeline runs. Use it to normalize, rename, or reshape incoming data.

```elixir
schema = Sinter.Schema.define(
  [
    {:email, :string, [required: true]},
    {:name, :string, [required: true]}
  ],
  pre_validate: fn data ->
    data
    |> Map.update("email", nil, &String.downcase/1)
    |> Map.update("name", nil, &String.trim/1)
  end
)

{:ok, validated} = Sinter.Validator.validate(schema, %{
  email: "Alice@Example.COM",
  name: "  Alice  "
})
# validated["email"] => "alice@example.com"
# validated["name"]  => "Alice"
```

### Post-Validation

The `post_validate` function runs after all fields pass validation. Use it for
cross-field constraints that cannot be expressed per-field.

The function receives the validated data map and must return
`{:ok, data}` or `{:error, reason}`.

```elixir
schema = Sinter.Schema.define(
  [
    {:password, :string, [required: true, min_length: 8]},
    {:password_confirmation, :string, [required: true]}
  ],
  post_validate: fn data ->
    if data["password"] == data["password_confirmation"] do
      {:ok, data}
    else
      {:error, "password and confirmation do not match"}
    end
  end
)

{:error, [error]} = Sinter.Validator.validate(schema, %{
  password: "secret123",
  password_confirmation: "secret456"
})

error.code    # => :post_validation
error.message # => "password and confirmation do not match"
```

You can also return a list of `Sinter.Error` structs for multiple post-validation failures:

```elixir
post_validate: fn data ->
  errors = []

  errors =
    if data["start_date"] > data["end_date"],
      do: [Sinter.Error.new([:end_date], :range, "must be after start_date") | errors],
      else: errors

  case errors do
    [] -> {:ok, data}
    errs -> {:error, errs}
  end
end
```

## Custom Field Validators

The `:validate` field option accepts a function or list of functions for
per-field custom validation. Each function receives the field value and must
return `:ok`, `{:ok, value}`, `{:error, message}`, or `{:error, %Sinter.Error{}}`.

```elixir
schema = Sinter.Schema.define([
  {:email, :string, [
    required: true,
    validate: fn value ->
      if String.contains?(value, "@"),
        do: :ok,
        else: {:error, "must be a valid email address"}
    end
  ]},
  {:score, :integer, [
    required: true,
    validate: [
      fn value -> if value >= 0, do: :ok, else: {:error, "must be non-negative"} end,
      fn value -> if rem(value, 5) == 0, do: :ok, else: {:error, "must be a multiple of 5"} end
    ]
  ]}
])

{:error, errors} = Sinter.Validator.validate(schema, %{email: "invalid", score: 7})
# Two errors: one for email, one for score (pipeline stops at first failing validator per field)
```

When multiple validators are provided as a list, they run in order and
short-circuit on the first failure.

## Batch Validation

`Sinter.Validator.validate_many/3` validates a list of maps against the same
schema. It returns `{:ok, validated_list}` when all items pass, or
`{:error, errors_by_index}` with a map from index to errors.

```elixir
schema = Sinter.Schema.define([
  {:name, :string, [required: true]},
  {:age, :integer, [required: true, gt: 0]}
])

data = [
  %{name: "Alice", age: 30},
  %{name: "Bob", age: 25},
  %{name: "Charlie", age: 35}
]

{:ok, validated} = Sinter.Validator.validate_many(schema, data)
# validated is a list of three validated maps

# When some items fail:
bad_data = [
  %{name: "Alice", age: 30},
  %{name: "", age: -1},
  %{age: 20}
]

{:error, errors_by_index} = Sinter.Validator.validate_many(schema, bad_data)
# errors_by_index is a map: %{1 => [...], 2 => [...]}
# Index 0 (Alice) passed, so it does not appear in the error map
```

Error paths in batch validation include the item index, so
`error.path` might look like `[1, "name"]` for a failure on the second
item's `name` field.

## Stream Validation

`Sinter.Validator.validate_stream/3` wraps a stream (or any enumerable) and
validates each element lazily. This is useful for processing large datasets
without loading everything into memory.

```elixir
schema = Sinter.Schema.define([{:id, :integer, [required: true]}])

results =
  1..1_000_000
  |> Stream.map(&%{id: &1})
  |> Sinter.Validator.validate_stream(schema)
  |> Stream.filter(&match?({:ok, _}, &1))
  |> Stream.map(fn {:ok, data} -> data end)
  |> Enum.take(5)

# => [%{"id" => 1}, %{"id" => 2}, %{"id" => 3}, %{"id" => 4}, %{"id" => 5}]
```

Note the argument order: the stream is the second argument (after the schema),
matching the `validate/3` convention.

Each element in the resulting stream is either `{:ok, validated}` or
`{:error, errors}`, so you can partition successes and failures downstream.

## Error Handling

All validation errors are represented as `Sinter.Error` structs with four
fields:

| Field     | Type                          | Description                          |
|-----------|-------------------------------|--------------------------------------|
| `path`    | `[atom \| String.t \| integer]` | Path to the offending field          |
| `code`    | `atom`                        | Machine-readable error code          |
| `message` | `String.t`                    | Human-readable description           |
| `context` | `map \| nil`                  | Optional additional context          |

### Formatting Errors

```elixir
error = Sinter.Error.new([:user, :email], :format, "invalid email format")

Sinter.Error.format(error)
# => "user.email: invalid email format"

Sinter.Error.format(error, include_path: false)
# => "invalid email format"

Sinter.Error.format(error, path_separator: "/")
# => "user/email: invalid email format"
```

### Grouping Errors

```elixir
errors = [
  Sinter.Error.new([:name], :required, "field is required"),
  Sinter.Error.new([:name], :min_length, "too short"),
  Sinter.Error.new([:email], :format, "invalid format"),
  Sinter.Error.new([:age], :required, "field is required")
]

# Group by field path
Sinter.Error.group_by_path(errors)
# => %{
#   [:name]  => [%Error{code: :required, ...}, %Error{code: :min_length, ...}],
#   [:email] => [%Error{code: :format, ...}],
#   [:age]   => [%Error{code: :required, ...}]
# }

# Group by error code
Sinter.Error.group_by_code(errors)
# => %{
#   required:   [%Error{path: [:name], ...}, %Error{path: [:age], ...}],
#   min_length: [%Error{path: [:name], ...}],
#   format:     [%Error{path: [:email], ...}]
# }
```

### Serializing Errors

`Error.to_map/1` converts an error to a plain map suitable for JSON
serialization:

```elixir
error = Sinter.Error.new([:user, :email], :format, "invalid email format")

Sinter.Error.to_map(error)
# => %{
#   "path"    => ["user", "email"],
#   "code"    => "format",
#   "message" => "invalid email format"
# }
```

For a list of errors, use `Sinter.Error.to_maps/1`.

## Convenience Helpers

The top-level `Sinter` module provides shorthand functions that create
temporary schemas internally, useful for one-off validations.

### `Sinter.validate_type/3`

Validates a single value against a type specification.

```elixir
{:ok, 42} = Sinter.validate_type(:integer, "42", coerce: true)

{:ok, ["a", "b"]} = Sinter.validate_type({:array, :string}, ["a", "b"])

{:error, [error]} = Sinter.validate_type(:string, 123)
error.code # => :type
```

### `Sinter.validate_value/4`

Validates a named value with constraints. The field name appears in error
paths.

```elixir
{:ok, "test@example.com"} = Sinter.validate_value(
  :email, :string, "test@example.com",
  constraints: [format: ~r/@/]
)

{:ok, 95} = Sinter.validate_value(
  :score, :integer, "95",
  coerce: true, constraints: [gteq: 0, lteq: 100]
)
```

### `Sinter.validate_many/2`

Validates multiple values against different type specifications in a single
call.

```elixir
{:ok, results} = Sinter.validate_many([
  {:string, "hello"},
  {:integer, 42},
  {:email, :string, "user@example.com", [format: ~r/@/]}
])
# results => ["hello", 42, "user@example.com"]
```

### `Sinter.validator_for/2`

Creates a reusable validation function for repeated single-value checks.

```elixir
email_validator = Sinter.validator_for(:string, constraints: [format: ~r/@/])

{:ok, "a@b.com"} = email_validator.("a@b.com")
{:error, _}      = email_validator.("invalid")
```

### `Sinter.batch_validator_for/2`

Creates a reusable validation function backed by a pre-built schema.
Avoids re-creating the schema on every call.

```elixir
validate_user = Sinter.batch_validator_for([
  {:name, :string},
  {:age, :integer}
])

{:ok, validated} = validate_user.(%{name: "Alice", age: 30})
{:error, errors} = validate_user.(%{name: 123})
```
