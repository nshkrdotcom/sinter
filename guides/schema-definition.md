# Schema Definition

This guide covers how to define, configure, and query schemas in Sinter. Schemas
are the foundation of Sinter's validation system -- they describe the structure,
types, and constraints of your data.

## Runtime Schemas

Use `Sinter.Schema.define/2` to create schemas at runtime. Each field is specified
as a `{name, type, opts}` tuple.

```elixir
schema = Sinter.Schema.define([
  {:name, :string, [required: true, min_length: 2]},
  {:age, :integer, [optional: true, gt: 0]},
  {:active, :boolean, [optional: true, default: true]}
])
```

The second argument accepts schema-level configuration options:

```elixir
schema = Sinter.Schema.define(
  [
    {:title, :string, [required: true, min_length: 3, max_length: 100]},
    {:price, :float, [required: true, gt: 0.0]},
    {:category, :string, [required: true, choices: ["electronics", "books"]]}
  ],
  title: "Product Schema",
  description: "Validates product data",
  strict: true
)
```

Runtime schemas are first-class data structures (`Sinter.Schema.t()`) that can be
passed around, stored, and composed dynamically. This makes them well suited for
frameworks that build schemas at runtime.

## Compile-Time Schemas

For schemas that are known at compile time, use the `use Sinter.Schema` macro
together with a `use_schema` block. This produces a module with a `schema/0`
function that returns a precompiled `Sinter.Schema.t()`.

```elixir
defmodule UserSchema do
  use Sinter.Schema

  use_schema do
    option :title, "User Schema"
    option :strict, true

    field :name, :string, required: true, min_length: 2
    field :age, :integer, optional: true, gt: 0
    field :active, :boolean, optional: true, default: true
  end
end

# Retrieve the compiled schema
schema = UserSchema.schema()
```

The `field` macro accepts the same arguments as a runtime field tuple --
`field name, type, opts`. The `option` macro sets schema-level configuration
(`:title`, `:description`, `:strict`, etc.).

`field` and `option` calls can be interleaved in any order inside the
`use_schema` block.

## Supported Types

### Primitive Types

| Type        | Elixir Values                     |
|-------------|-----------------------------------|
| `:string`   | Binaries (`"hello"`)              |
| `:integer`  | Integers (`42`)                   |
| `:float`    | Floats (`3.14`)                   |
| `:boolean`  | `true` / `false`                  |
| `:atom`     | Atoms (`:ok`)                     |
| `:any`      | Any value (no type check)         |
| `:map`      | Any map (`%{}`)                   |
| `:date`     | ISO 8601 date string (`"2024-01-15"`) |
| `:datetime` | ISO 8601 datetime string (`"2024-01-15T10:30:00Z"`) |
| `:uuid`     | UUID string (`"550e8400-e29b-41d4-a716-446655440000"`) |
| `:null`     | `nil`                             |

### Composite Types

**Array** -- a list where every element matches the inner type:

```elixir
{:tags, {:array, :string}, [required: true]}
{:matrix, {:array, {:array, :integer}}, [optional: true]}
```

**Union** -- a value that matches any one of the listed types:

```elixir
{:id, {:union, [:string, :integer]}, [required: true]}
```

**Tuple** -- a fixed-size tuple with positional types:

```elixir
{:coordinates, {:tuple, [:float, :float]}, [required: true]}
{:rgb, {:tuple, [:integer, :integer, :integer]}, [required: true]}
```

**Typed map** -- a map with constrained key and value types:

```elixir
{:metadata, {:map, :string, :any}, [optional: true]}
{:scores, {:map, :string, :integer}, [required: true]}
```

**Nullable** -- allows `nil` in addition to the inner type:

```elixir
{:middle_name, {:nullable, :string}, [optional: true]}
```

**Literal** -- matches exactly one value:

```elixir
{:type, {:literal, "text"}, [required: true]}
{:version, {:literal, 2}, [required: true]}
```

**Discriminated union** -- selects a variant schema based on a discriminator
field. Each variant must be a `Sinter.Schema.t()`:

```elixir
text_schema = Sinter.Schema.define([
  {:type, {:literal, "text"}, [required: true]},
  {:content, :string, [required: true]}
])

image_schema = Sinter.Schema.define([
  {:type, {:literal, "image"}, [required: true]},
  {:data, :string, [required: true]},
  {:format, :string, [required: true, choices: ["png", "jpeg"]]}
])

{:payload,
 {:discriminated_union,
  [
    discriminator: "type",
    variants: %{
      "text" => text_schema,
      "image" => image_schema
    }
  ]}, [required: true]}
```

The discriminator can be a string or atom key. Sinter looks up the discriminator
value in the input map, finds the matching variant, and validates against that
variant's schema. If the discriminator field is missing or its value does not
match any variant key, validation fails with a descriptive error.

Each variant must define the discriminator field itself, and that field must use
`{:literal, value}` with a value matching the variant key. Sinter validates this
when the schema is defined, so malformed discriminated unions fail fast instead
of producing ambiguous runtime behavior.

## Field Options

Every field accepts the following options as a keyword list:

| Option         | Description |
|----------------|-------------|
| `:required`    | Field must be present. Defaults to `true`. |
| `:optional`    | Field may be omitted. Equivalent to `required: false`. |
| `:default`     | Value used when the field is absent. Implies `optional: true`. |
| `:description` | Human-readable description (used in generated JSON Schema). |
| `:example`     | Example value for documentation purposes. |
| `:alias`       | Alternate field name accepted on input and used in JSON Schema output. |
| `:validate`    | Custom validator function or list of functions (see below). |

You cannot specify both `:required` and `:optional` on the same field.

```elixir
Sinter.Schema.define([
  {:name, :string, [required: true, description: "User's full name", example: "Jane Doe"]},
  {:role, :string, [default: "member", choices: ["admin", "member", "guest"]]},
  {:account_name, :string, [required: true, alias: "accountName"]}
])
```

### Field Aliases

An alias lets you accept input under a different key (e.g., camelCase from JSON)
while keeping a canonical snake_case name internally. During validation, the alias
key takes precedence if both the alias and canonical name are present.

```elixir
schema = Sinter.Schema.define([
  {:account_name, :string, [required: true, alias: "accountName"]},
  {:user_id, :string, [required: true, alias: "userId"]}
])

# Input uses alias keys
{:ok, result} = Sinter.Validator.validate(schema, %{"accountName" => "Acme", "userId" => "42"})
result["account_name"]  #=> "Acme"
result["user_id"]       #=> "42"
```

### Custom Validators

The `:validate` option accepts a function (arity 1) or a list of functions. Each
function receives the validated value and must return one of:

- `:ok` -- value passes; the original value is kept.
- `{:ok, new_value}` -- value passes; `new_value` replaces the original.
- `{:error, message}` -- validation fails with the given message string.

Validators run after type checking and constraint validation. When a list of
validators is given, they execute in order and short-circuit on the first error.

```elixir
Sinter.Schema.define([
  {:email, :string,
   [
     required: true,
     validate: fn value ->
       if String.contains?(value, "@"),
         do: {:ok, value},
         else: {:error, "must contain @"}
     end
   ]},

  {:code, :string,
   [
     required: true,
     validate: [
       fn v -> if String.length(v) > 0, do: :ok, else: {:error, "cannot be empty"} end,
       fn v -> if String.length(v) <= 10, do: :ok, else: {:error, "too long"} end
     ]
   ]}
])
```

If a validator raises an exception, the error is caught and wrapped as a
`:custom_validation_error`.

## Constraints

Constraints are specified alongside other field options. They are validated after
the type check passes.

### String and Array Length

```elixir
{:name, :string, [required: true, min_length: 2, max_length: 50]}
{:tags, {:array, :string}, [optional: true, min_items: 1, max_items: 10]}
```

### Numeric Bounds

| Constraint | Meaning                  |
|------------|--------------------------|
| `:gt`      | Greater than             |
| `:gteq`    | Greater than or equal to |
| `:lt`      | Less than                |
| `:lteq`    | Less than or equal to    |

```elixir
{:age, :integer, [required: true, gteq: 0, lt: 150]}
{:score, :float, [required: true, gt: 0.0, lteq: 100.0]}
```

### Format (Regex)

```elixir
{:email, :string, [required: true, format: ~r/^[^\s]+@[^\s]+\.[^\s]+$/]}
{:slug, :string, [required: true, format: ~r/^[a-z0-9\-]+$/]}
```

### Choices

```elixir
{:status, :string, [required: true, choices: ["active", "inactive", "pending"]]}
{:priority, :integer, [required: true, choices: [1, 2, 3]]}
```

## Nested Objects

Use `Sinter.Schema.object/1` to build a nested object type from field specs.
It returns an `{:object, schema}` tuple suitable for use as a field type.

```elixir
address_type = Sinter.Schema.object([
  {:street, :string, [required: true]},
  {:city, :string, [required: true]},
  {:zip, :string, [required: true, format: ~r/^\d{5}$/]}
])

schema = Sinter.Schema.define([
  {:name, :string, [required: true]},
  {:address, address_type, [required: true]}
])

{:ok, result} = Sinter.Validator.validate(schema, %{
  "name" => "Alice",
  "address" => %{"street" => "123 Main St", "city" => "Springfield", "zip" => "62704"}
})
```

You can also inline the field specs directly as a list, and Sinter will create
the nested schema automatically:

```elixir
Sinter.Schema.define([
  {:user,
   {:object,
    [
      {:name, :string, [required: true]},
      {:email, :string, [required: true]}
    ]}, [required: true]}
])
```

Or pass a prebuilt `Sinter.Schema.t()`:

```elixir
inner = Sinter.Schema.define([{:value, :integer, [required: true]}])

Sinter.Schema.define([
  {:nested, {:object, inner}, [required: true]}
])
```

## Schema Configuration

Schema-level options are passed as the second argument to `Sinter.Schema.define/2`
or via `option` in a `use_schema` block.

| Option           | Type           | Default | Description |
|------------------|----------------|---------|-------------|
| `:title`         | `String.t()`   | `nil`   | Schema title (appears in JSON Schema output). |
| `:description`   | `String.t()`   | `nil`   | Schema description. |
| `:strict`        | `boolean()`    | `false` | When `true`, reject data containing fields not defined in the schema. |
| `:post_validate` | `(map() -> {:ok, map()} \| {:error, String.t()})` | `nil` | Runs after all field validation succeeds. |
| `:pre_validate`  | `(term() -> term())` | `nil` | Transforms raw input before validation begins. |

### Strict Mode

By default Sinter ignores extra fields. Enable strict mode to reject them:

```elixir
schema = Sinter.Schema.define(
  [{:name, :string, [required: true]}],
  strict: true
)

Sinter.Validator.validate(schema, %{"name" => "Alice", "extra" => "oops"})
#=> {:error, [%Sinter.Error{code: :strict, message: "unexpected fields: [\"extra\"]"}]}
```

### Post-Validation Hook

The `:post_validate` function receives the fully validated data map and can
perform cross-field checks or final transformations. It must return
`{:ok, data}` or `{:error, message}`.

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
      {:error, "Passwords do not match"}
    end
  end
)
```

### Pre-Validation Hook

The `:pre_validate` function receives the raw input and returns transformed data
that then enters the normal validation pipeline. Use it to normalize keys,
inject computed fields, or strip sensitive data before validation.

```elixir
schema = Sinter.Schema.define(
  [
    {:full_name, :string, [required: true]},
    {:first_name, :string, [optional: true]},
    {:last_name, :string, [optional: true]}
  ],
  pre_validate: fn data ->
    first = Map.get(data, "first_name", "")
    last = Map.get(data, "last_name", "")
    Map.put(data, "full_name", String.trim("#{first} #{last}"))
  end
)
```

If the function raises, the error is caught and returned as a
`:pre_validate_error`.

## Querying Schemas

`Sinter.Schema` provides several functions for inspecting a schema at runtime.

### `Schema.fields/1`

Returns the full map of field name to field definition:

```elixir
fields = Sinter.Schema.fields(schema)
fields["name"].type      #=> :string
fields["name"].required  #=> true
```

### `Schema.required_fields/1` and `Schema.optional_fields/1`

Return lists of field names:

```elixir
Sinter.Schema.required_fields(schema)  #=> ["name"]
Sinter.Schema.optional_fields(schema)  #=> ["age", "active"]
```

### `Schema.field_types/1`

Returns a map of field name to type spec:

```elixir
Sinter.Schema.field_types(schema)
#=> %{"name" => :string, "age" => :integer, "tags" => {:array, :string}}
```

### `Schema.constraints/1`

Returns a map of field name to constraint keyword list:

```elixir
Sinter.Schema.constraints(schema)
#=> %{"name" => [min_length: 2, max_length: 50], "score" => [gt: 0, lteq: 100]}
```

Fields with no constraints return an empty list.

### `Schema.field_aliases/1`

Returns a map of canonical field names to their aliases. Only fields with an
`:alias` option are included:

```elixir
schema = Sinter.Schema.define([
  {:account_name, :string, [alias: "accountName"]},
  {:user_id, :string, [alias: "userId"]},
  {:name, :string, []}
])

Sinter.Schema.field_aliases(schema)
#=> %{"account_name" => "accountName", "user_id" => "userId"}
```

### `Schema.info/1`

Returns a summary map with counts, configuration, and metadata:

```elixir
info = Sinter.Schema.info(schema)

info.field_count      #=> 3
info.required_count   #=> 1
info.optional_count   #=> 2
info.field_names      #=> ["name", "age", "active"]
info.title            #=> "User Schema"
info.description      #=> "Validates user data"
info.strict           #=> false
info.has_post_validation #=> false
info.created_at       #=> ~U[2024-01-15 10:30:00Z]
```
