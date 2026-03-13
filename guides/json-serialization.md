# JSON Serialization

Sinter provides a complete JSON serialization pipeline through three cooperating
modules: `Sinter.JSON` for encoding and decoding, `Sinter.Transform` for
preparing data for serialization, and `Sinter.NotGiven` for distinguishing
omitted fields from explicit `nil` values.

## Encoding

`Sinter.JSON.encode/2` and `Sinter.JSON.encode!/2` apply the transform pipeline
to your data, then encode the result to a JSON string via Jason.

```elixir
data = %{
  account_name: "Acme Corp",
  created_at: ~U[2025-06-15 12:30:00Z],
  deleted_at: nil
}

# Safe version returns {:ok, json} or {:error, reason}
{:ok, json} = Sinter.JSON.encode(data)
# => {:ok, "{\"account_name\":\"Acme Corp\",\"created_at\":\"2025-06-15 12:30:00Z\",\"deleted_at\":null}"}

# Bang version raises on failure
json = Sinter.JSON.encode!(data)
```

Both functions accept the same options that `Sinter.Transform.transform/2`
supports -- `:aliases`, `:formats`, and `:drop_nil?`:

```elixir
json = Sinter.JSON.encode!(data,
  aliases: %{account_name: "accountName", created_at: "createdAt", deleted_at: "deletedAt"},
  formats: %{created_at: :iso8601},
  drop_nil?: true
)
# => "{\"accountName\":\"Acme Corp\",\"createdAt\":\"2025-06-15T12:30:00Z\"}"
```

## Decoding with Validation

`Sinter.JSON.decode/3` and `Sinter.JSON.decode!/3` decode a JSON string and
then validate the result against a Sinter schema. This combines parsing and
validation into a single step.

```elixir
schema = Sinter.Schema.define([
  {:name, :string, [required: true, min_length: 1]},
  {:age, :integer, [optional: true, gt: 0]}
])

json = ~s({"name": "Alice", "age": 30})

# Safe version
{:ok, validated} = Sinter.JSON.decode(json, schema)
# => {:ok, %{"name" => "Alice", "age" => 30}}

# Bang version raises Sinter.ValidationError on failure
validated = Sinter.JSON.decode!(json, schema)
```

When decoding fails -- whether due to malformed JSON or validation errors --
the error tuple contains a list of `Sinter.Error` structs:

```elixir
bad_json = ~s({"age": -5})

{:error, errors} = Sinter.JSON.decode(bad_json, schema)

for error <- errors do
  IO.puts(Sinter.Error.format(error))
end
# name: field is required
# age: must be greater than 0
```

Validation options such as `:coerce` are passed through to the validator:

```elixir
json = ~s({"name": "Bob", "age": "25"})

{:ok, validated} = Sinter.JSON.decode(json, schema, coerce: true)
# => {:ok, %{"name" => "Bob", "age" => 25}}
```

## Transform Pipeline

`Sinter.Transform.transform/2` converts Elixir data structures into
JSON-friendly maps. It applies a fixed sequence of transformations:

1. Key stringification (atom keys become string keys)
2. Alias application
3. Format application
4. NotGiven/Omit sentinel removal
5. nil dropping (when enabled)

The function recurses through maps, structs, and lists.

### Key Stringification

Atom keys are automatically converted to strings:

```elixir
Sinter.Transform.transform(%{user_name: "alice", active: true})
# => %{"user_name" => "alice", "active" => true}
```

### Alias Application

The `:aliases` option maps canonical keys to different output key names.
This is useful for converting between Elixir conventions (snake_case) and
API conventions (camelCase):

```elixir
data = %{first_name: "Alice", last_name: "Smith"}

Sinter.Transform.transform(data,
  aliases: %{first_name: "firstName", last_name: "lastName"}
)
# => %{"firstName" => "Alice", "lastName" => "Smith"}
```

### Format Application

The `:formats` option attaches formatters to specific keys. Sinter provides
the built-in `:iso8601` formatter for `DateTime`, `NaiveDateTime`, and `Date`
values. You can also supply any unary function:

```elixir
data = %{
  created_at: ~U[2025-06-15 12:30:00Z],
  starts_on: ~D[2025-07-01],
  score: 0.9537
}

Sinter.Transform.transform(data,
  formats: %{
    created_at: :iso8601,
    starts_on: :iso8601,
    score: &Float.round(&1, 2)
  }
)
# => %{"created_at" => "2025-06-15T12:30:00Z", "starts_on" => "2025-07-01", "score" => 0.95}
```

### NotGiven/Omit Sentinel Removal

Any field whose value is the `NotGiven` or `Omit` sentinel is silently removed
from the output. See the [NotGiven Sentinels](#notgiven-sentinels) section
below for details.

```elixir
alias Sinter.NotGiven

data = %{name: "Alice", nickname: NotGiven.value(), temp_token: NotGiven.omit()}

Sinter.Transform.transform(data)
# => %{"name" => "Alice"}
```

### nil Dropping

When `:drop_nil?` is set to `true`, keys with `nil` values are removed:

```elixir
data = %{name: "Alice", bio: nil, avatar_url: nil}

Sinter.Transform.transform(data, drop_nil?: true)
# => %{"name" => "Alice"}
```

### Schema-Based Aliases

Instead of passing an explicit `:aliases` map, you can reference a schema
and set `:use_aliases` to `true`. The transform will extract aliases defined
on the schema's fields:

```elixir
schema = Sinter.Schema.define([
  {:account_name, :string, [required: true, alias: "accountName"]},
  {:is_active, :boolean, [optional: true, alias: "isActive"]}
])

data = %{account_name: "Acme", is_active: true}

Sinter.Transform.transform(data, schema: schema, use_aliases: true)
# => %{"accountName" => "Acme", "isActive" => true}
```

Explicit `:aliases` are merged on top of schema-derived aliases, so you can
override individual keys when needed.

## NotGiven Sentinels

`Sinter.NotGiven` provides sentinel values for distinguishing between a field
that was intentionally omitted and one that was explicitly set to `nil`. This
pattern is common in API clients where you need to differentiate "do not send
this field" from "set this field to null."

### Creating Sentinels

```elixir
alias Sinter.NotGiven

# The NotGiven sentinel -- field was not provided
not_given = NotGiven.value()

# The Omit sentinel -- field should be explicitly dropped
omit = NotGiven.omit()
```

### Checking Sentinels

```elixir
NotGiven.not_given?(NotGiven.value())  # => true
NotGiven.not_given?(nil)               # => false
NotGiven.not_given?("hello")           # => false

NotGiven.omit?(NotGiven.omit())        # => true
NotGiven.omit?(nil)                    # => false
```

Guard-friendly versions are also available:

```elixir
import Sinter.NotGiven, only: [is_not_given: 1, is_omit: 1]

case value do
  v when is_not_given(v) -> :skip
  v when is_omit(v) -> :drop
  v -> {:use, v}
end
```

### Coalescing

`NotGiven.coalesce/2` replaces sentinel values with a fallback, leaving all
other values untouched:

```elixir
NotGiven.coalesce(NotGiven.value(), "default")  # => "default"
NotGiven.coalesce(NotGiven.omit(), "default")   # => "default"
NotGiven.coalesce(nil, "default")               # => nil
NotGiven.coalesce("hello", "default")           # => "hello"
```

### Practical Example

A typical use case is building request payloads with optional fields:

```elixir
alias Sinter.NotGiven

defmodule UserUpdateRequest do
  defstruct name: NotGiven.value(),
            email: NotGiven.value(),
            bio: NotGiven.value()
end

# Caller only wants to update the email
request = %UserUpdateRequest{email: "new@example.com"}

# Transform strips the NotGiven fields automatically
payload = Sinter.Transform.transform(request)
# => %{"email" => "new@example.com"}

# Explicitly setting bio to nil sends null in the payload
request = %UserUpdateRequest{email: "new@example.com", bio: nil}
payload = Sinter.Transform.transform(request)
# => %{"email" => "new@example.com", "bio" => nil}
```

## Field Aliases

Field aliases allow you to decouple the internal (Elixir-side) field name from
the external (JSON-side) field name. Define an alias on a schema field with
the `alias:` option:

```elixir
schema = Sinter.Schema.define([
  {:account_name, :string, [required: true, alias: "accountName"]},
  {:created_at, :string, [required: true, alias: "createdAt"]},
  {:is_active, :boolean, [optional: true, alias: "isActive"]}
])
```

Or using the compile-time DSL:

```elixir
defmodule AccountSchema do
  use Sinter.Schema

  use_schema do
    field :account_name, :string, required: true, alias: "accountName"
    field :created_at, :string, required: true, alias: "createdAt"
    field :is_active, :boolean, optional: true, alias: "isActive"
  end
end
```

Aliases affect two areas:

### Aliases in Transform and Encoding

When you pass `schema: schema, use_aliases: true` to `Sinter.Transform.transform/2`
(or indirectly through `Sinter.JSON.encode/2`), canonical field names are
replaced by their aliases in the output:

```elixir
data = %{account_name: "Acme", created_at: "2025-01-15", is_active: true}

Sinter.Transform.transform(data, schema: schema, use_aliases: true)
# => %{"accountName" => "Acme", "createdAt" => "2025-01-15", "isActive" => true}
```

### Aliases in JSON Schema Generation

`Sinter.JsonSchema.generate/1` uses alias names as property keys in the
generated JSON Schema, so the schema reflects the wire format:

```elixir
json_schema = Sinter.JsonSchema.generate(schema)

json_schema["properties"]
# => %{
#   "accountName" => %{"type" => "string"},
#   "createdAt" => %{"type" => "string"},
#   "isActive" => %{"type" => "boolean"}
# }

json_schema["required"]
# => ["accountName", "createdAt"]
```

### Aliases in Validation

During validation, `Sinter.Validator.validate/3` accepts data keyed by either
the canonical name or the alias. The alias takes precedence when both are
present:

```elixir
# Data using alias keys (e.g., decoded from an API response)
api_data = %{"accountName" => "Acme", "createdAt" => "2025-01-15"}

{:ok, validated} = Sinter.Validator.validate(schema, api_data)
# => {:ok, %{"account_name" => "Acme", "created_at" => "2025-01-15"}}
```

### Querying Aliases

You can retrieve the alias map from a schema programmatically:

```elixir
Sinter.Schema.field_aliases(schema)
# => %{"account_name" => "accountName", "created_at" => "createdAt", "is_active" => "isActive"}
```
