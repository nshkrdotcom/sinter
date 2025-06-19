defmodule Sinter.Schema do
  @moduledoc """
  Unified schema definition for Sinter.

  This module provides the single, canonical way to define data validation schemas
  in Sinter. It follows the "One True Way" principle - all schema creation flows
  through `define/2`, whether at runtime or compile-time.

  ## Basic Usage

      # Runtime schema definition
      schema = Sinter.Schema.define([
        {:name, :string, [required: true, min_length: 2]},
        {:age, :integer, [optional: true, gt: 0]}
      ])

      # Compile-time schema definition
      defmodule UserSchema do
        use Sinter.Schema

        use_schema do
          field :name, :string, required: true, min_length: 2
          field :age, :integer, optional: true, gt: 0
        end
      end

  ## Field Specifications

  Each field is specified as a tuple: `{name, type_spec, options}`

  ### Supported Options

  * `:required` - Field must be present (default: true)
  * `:optional` - Field may be omitted (default: false)
  * `:default` - Default value if field is missing (implies optional: true)
  * `:description` - Human-readable description
  * `:example` - Example value for documentation

  ### Constraints

  * `:min_length`, `:max_length` - For strings and arrays
  * `:gt`, `:gteq`, `:lt`, `:lteq` - For numbers
  * `:format` - Regex pattern for strings
  * `:choices` - List of allowed values

  ## Schema Configuration

  * `:title` - Schema title for documentation
  * `:description` - Schema description
  * `:strict` - Reject unknown fields (default: false)
  * `:post_validate` - Custom validation function
  """

  alias Sinter.Types

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Sinter.Schema, only: [use_schema: 1, field: 2, field: 3, option: 2]
    end
  end

  @type field_spec :: {atom(), Types.type_spec(), keyword()}

  @type field_definition :: %{
          name: atom(),
          type: Types.type_spec(),
          required: boolean(),
          constraints: keyword(),
          description: String.t() | nil,
          example: term() | nil,
          default: term() | nil
        }

  @type config :: %{
          title: String.t() | nil,
          description: String.t() | nil,
          strict: boolean(),
          post_validate: function() | nil
        }

  @type metadata :: %{
          created_at: DateTime.t(),
          field_count: non_neg_integer(),
          sinter_version: String.t()
        }

  @enforce_keys [:fields, :config, :metadata, :definition]
  defstruct [:fields, :config, :metadata, :definition]

  @type t :: %__MODULE__{
          fields: %{atom() => field_definition()},
          config: config(),
          metadata: metadata(),
          definition: map()
        }

  @doc """
  Defines a schema from field specifications.

  This is the unified entry point for all schema creation in Sinter.
  Both runtime and compile-time schema definition ultimately use this function.

  ## Parameters

    * `field_specs` - List of field specifications
    * `opts` - Schema configuration options

  ## Options

    * `:title` - Schema title for documentation
    * `:description` - Schema description
    * `:strict` - Reject unknown fields (default: false)
    * `:post_validate` - Custom validation function

  ## Examples

      iex> schema = Sinter.Schema.define([
      ...>   {:name, :string, [required: true, min_length: 2]},
      ...>   {:age, :integer, [optional: true, gt: 0]}
      ...> ], title: "User Schema")
      iex> schema.config.title
      "User Schema"

      iex> schema.fields[:name].required
      true
  """
  @spec define([field_spec()], keyword()) :: t()
  def define(field_specs, opts \\ []) when is_list(field_specs) do
    # Validate field specifications
    validated_specs = Enum.map(field_specs, &validate_field_spec/1)

    # Normalize field specifications into field definitions
    fields =
      validated_specs
      |> Enum.map(&normalize_field_spec/1)
      |> Map.new(fn field -> {field.name, field} end)

    # Build configuration
    config = build_config(opts)

    # Create metadata
    metadata = %{
      created_at: DateTime.utc_now(),
      field_count: map_size(fields),
      sinter_version: get_sinter_version()
    }

    # Build internal definition (for compatibility)
    definition = %{
      fields: fields,
      config: config
    }

    %__MODULE__{
      fields: fields,
      config: config,
      metadata: metadata,
      definition: definition
    }
  end

  @doc """
  Compile-time schema definition macro.

  This macro provides a DSL for defining schemas at compile time.
  It accumulates field and option definitions and creates a schema
  using `define/2`.

  ## Example

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

      # The module will have a schema/0 function
      UserSchema.schema()
  """
  defmacro use_schema(do: block) do
    quote do
      @sinter_fields []
      @sinter_options []

      unquote(block)

      field_specs = Enum.reverse(@sinter_fields)
      schema_opts = @sinter_options |> Enum.reverse() |> Keyword.new()

      @sinter_schema Sinter.Schema.define(field_specs, schema_opts)

      @doc "Returns the compiled schema."
      @spec schema() :: Sinter.Schema.t()
      def schema, do: @sinter_schema
    end
  end

  @doc """
  Adds an option to the schema being defined.

  Used within `use_schema` blocks.

  ## Examples

      option :title, "User Schema"
      option :strict, true
  """
  defmacro option(key, value) do
    quote do
      @sinter_options [{unquote(key), unquote(value)} | @sinter_options]
    end
  end

  @doc """
  Defines a field in the schema.

  Used within `use_schema` blocks.

  ## Examples

      field :name, :string, required: true, min_length: 2
      field :age, :integer, optional: true, gt: 0
      field :active, :boolean, optional: true, default: true
  """
  defmacro field(name, type_spec, opts \\ []) do
    quote do
      @sinter_fields [{unquote(name), unquote(type_spec), unquote(opts)} | @sinter_fields]
    end
  end

  # Query functions

  @doc """
  Returns the field definitions map.

  ## Examples

      iex> schema = Sinter.Schema.define([{:name, :string, [required: true]}])
      iex> fields = Sinter.Schema.fields(schema)
      iex> fields[:name].required
      true
  """
  @spec fields(t()) :: %{atom() => field_definition()}
  def fields(%__MODULE__{fields: fields}), do: fields

  @doc """
  Returns the schema configuration.

  ## Examples

      iex> schema = Sinter.Schema.define([], title: "Test Schema")
      iex> config = Sinter.Schema.config(schema)
      iex> config.title
      "Test Schema"
  """
  @spec config(t()) :: config()
  def config(%__MODULE__{config: config}), do: config

  @doc """
  Returns a list of required field names.

  ## Examples

      iex> schema = Sinter.Schema.define([
      ...>   {:name, :string, [required: true]},
      ...>   {:age, :integer, [optional: true]}
      ...> ])
      iex> Sinter.Schema.required_fields(schema)
      [:name]
  """
  @spec required_fields(t()) :: [atom()]
  def required_fields(%__MODULE__{fields: fields}) do
    fields
    |> Enum.filter(fn {_name, field} -> field.required end)
    |> Enum.map(fn {name, _field} -> name end)
  end

  @doc """
  Returns a list of optional field names.

  ## Examples

      iex> schema = Sinter.Schema.define([
      ...>   {:name, :string, [required: true]},
      ...>   {:age, :integer, [optional: true]}
      ...> ])
      iex> Sinter.Schema.optional_fields(schema)
      [:age]
  """
  @spec optional_fields(t()) :: [atom()]
  def optional_fields(%__MODULE__{fields: fields}) do
    fields
    |> Enum.reject(fn {_name, field} -> field.required end)
    |> Enum.map(fn {name, _field} -> name end)
  end

  @doc """
  Returns true if the schema is in strict mode.

  ## Examples

      iex> schema = Sinter.Schema.define([], strict: true)
      iex> Sinter.Schema.strict?(schema)
      true
  """
  @spec strict?(t()) :: boolean()
  def strict?(%__MODULE__{config: %{strict: strict}}), do: strict

  @doc """
  Returns the post-validation function if defined.

  ## Examples

      iex> post_fn = fn data -> {:ok, data} end
      iex> schema = Sinter.Schema.define([], post_validate: post_fn)
      iex> Sinter.Schema.post_validate_fn(schema)
      #Function<...>
  """
  @spec post_validate_fn(t()) :: function() | nil
  def post_validate_fn(%__MODULE__{config: %{post_validate: fun}}), do: fun

  @doc """
  Returns summary information about the schema.

  ## Examples

      iex> schema = Sinter.Schema.define([
      ...>   {:name, :string, [required: true]},
      ...>   {:age, :integer, [optional: true]}
      ...> ], title: "User Schema")
      iex> info = Sinter.Schema.info(schema)
      iex> info.field_count
      2
      iex> info.title
      "User Schema"
  """
  @spec info(t()) :: map()
  def info(%__MODULE__{} = schema) do
    %{
      field_count: map_size(schema.fields),
      required_count: length(required_fields(schema)),
      optional_count: length(optional_fields(schema)),
      field_names: Map.keys(schema.fields),
      title: schema.config.title,
      description: schema.config.description,
      strict: strict?(schema),
      has_post_validation: not is_nil(post_validate_fn(schema)),
      created_at: schema.metadata.created_at
    }
  end

  # Private helper functions

  @spec validate_field_spec(field_spec()) :: field_spec()
  defp validate_field_spec({name, type_spec, opts} = field_spec)
       when is_atom(name) and is_list(opts) do
    # Validate that the type specification is supported
    _ = validate_type_spec(type_spec)

    # Validate options
    _ = validate_field_options(opts)

    field_spec
  end

  defp validate_field_spec(invalid) do
    raise ArgumentError, """
    Invalid field specification: #{inspect(invalid)}

    Expected: {name, type_spec, options}
    Where:
      - name is an atom
      - type_spec is a valid type specification
      - options is a keyword list
    """
  end

  @spec validate_type_spec(Types.type_spec()) :: :ok
  defp validate_type_spec(type_spec)
       when type_spec in [:string, :integer, :float, :boolean, :atom, :any, :map],
       do: :ok

  defp validate_type_spec({:array, inner_type}), do: validate_type_spec(inner_type)
  defp validate_type_spec({:array, inner_type, _constraints}), do: validate_type_spec(inner_type)

  defp validate_type_spec({:union, types}) when is_list(types) do
    Enum.each(types, &validate_type_spec/1)
  end

  defp validate_type_spec({:tuple, types}) when is_list(types) do
    Enum.each(types, &validate_type_spec/1)
  end

  defp validate_type_spec({:map, key_type, value_type}) do
    validate_type_spec(key_type)
    validate_type_spec(value_type)
  end

  defp validate_type_spec(invalid) do
    raise ArgumentError, "Invalid type specification: #{inspect(invalid)}"
  end

  @spec validate_field_options(keyword()) :: :ok
  defp validate_field_options(opts) do
    valid_keys = [
      :required,
      :optional,
      :default,
      :description,
      :example,
      :min_length,
      :max_length,
      :min_items,
      :max_items,
      :gt,
      :gteq,
      :lt,
      :lteq,
      :format,
      :choices,
      # DSPEx metadata for field classification
      :dspex_field_type
    ]

    invalid_keys = Keyword.keys(opts) -- valid_keys

    if invalid_keys != [] do
      raise ArgumentError, "Invalid field options: #{inspect(invalid_keys)}"
    end

    # Validate mutual exclusivity
    if Keyword.has_key?(opts, :required) and Keyword.has_key?(opts, :optional) do
      raise ArgumentError, "Cannot specify both :required and :optional"
    end

    :ok
  end

  @spec normalize_field_spec(field_spec()) :: field_definition()
  defp normalize_field_spec({name, type_spec, opts}) do
    # Determine if field is required
    required = determine_required(opts)

    # Extract constraints from options
    constraints = extract_constraints(opts)

    # Normalize type specification with constraints if needed
    normalized_type = normalize_type_with_constraints(type_spec, constraints)

    %{
      name: name,
      type: normalized_type,
      required: required,
      constraints: constraints,
      description: Keyword.get(opts, :description),
      example: Keyword.get(opts, :example),
      default: Keyword.get(opts, :default)
    }
  end

  @spec determine_required(keyword()) :: boolean()
  defp determine_required(opts) do
    cond do
      Keyword.has_key?(opts, :required) ->
        Keyword.get(opts, :required)

      Keyword.get(opts, :optional, false) ->
        false

      Keyword.has_key?(opts, :default) ->
        # Fields with defaults are optional
        false

      true ->
        # Default is required
        true
    end
  end

  @spec extract_constraints(keyword()) :: keyword()
  defp extract_constraints(opts) do
    constraint_keys = [
      :min_length,
      :max_length,
      :min_items,
      :max_items,
      :gt,
      :gteq,
      :lt,
      :lteq,
      :format,
      :choices
    ]

    Keyword.take(opts, constraint_keys)
  end

  @spec build_config(keyword()) :: config()
  defp build_config(opts) do
    # Validate post_validate function if provided
    case Keyword.get(opts, :post_validate) do
      nil ->
        :ok

      fun when is_function(fun, 1) ->
        :ok

      invalid ->
        raise ArgumentError, "post_validate must be a function/1, got: #{inspect(invalid)}"
    end

    %{
      title: Keyword.get(opts, :title),
      description: Keyword.get(opts, :description),
      strict: Keyword.get(opts, :strict, false),
      post_validate: Keyword.get(opts, :post_validate)
    }
  end

  @spec normalize_type_with_constraints(Types.type_spec(), keyword()) :: Types.type_spec()
  defp normalize_type_with_constraints({:array, inner_type}, constraints) do
    array_constraints = Keyword.take(constraints, [:min_items, :max_items])

    if array_constraints == [] do
      {:array, inner_type}
    else
      {:array, inner_type, array_constraints}
    end
  end

  defp normalize_type_with_constraints(type_spec, _constraints), do: type_spec

  @doc """
  Extracts field types from a schema for analysis and introspection.

  This is useful for DSPEx teleprompters that need to analyze the structure
  of schemas for optimization purposes.

  ## Parameters

    * `schema` - A Sinter schema

  ## Returns

    * A map of field_name => type_spec

  ## Examples

      iex> schema = Sinter.Schema.define([
      ...>   {:name, :string, [required: true]},
      ...>   {:tags, {:array, :string}, [optional: true]}
      ...> ])
      iex> Sinter.Schema.field_types(schema)
      %{
        name: :string,
        tags: {:array, :string}
      }
  """
  @spec field_types(t()) :: %{atom() => Sinter.Types.type_spec()}
  def field_types(%__MODULE__{fields: fields}) do
    Map.new(fields, fn {name, field_def} ->
      {name, field_def.type}
    end)
  end

  @doc """
  Extracts constraint information from schema fields.

  Returns a map of field names to their constraint lists, useful for
  teleprompter analysis and optimization.

  ## Parameters

    * `schema` - A Sinter schema

  ## Returns

    * A map of field_name => constraints_list

  ## Examples

      iex> schema = Sinter.Schema.define([
      ...>   {:name, :string, [required: true, min_length: 2, max_length: 50]},
      ...>   {:score, :integer, [required: true, gt: 0, lteq: 100]}
      ...> ])
      iex> Sinter.Schema.constraints(schema)
      %{
        name: [min_length: 2, max_length: 50],
        score: [gt: 0, lteq: 100]
      }
  """
  @spec constraints(t()) :: %{atom() => keyword()}
  def constraints(%__MODULE__{fields: fields}) do
    Map.new(fields, fn {name, field_def} ->
      {name, field_def.constraints}
    end)
  end

  @spec get_sinter_version() :: String.t()
  defp get_sinter_version do
    case Application.spec(:sinter, :vsn) do
      nil -> "unknown"
      version when is_list(version) -> List.to_string(version)
      version when is_binary(version) -> version
    end
  end
end
