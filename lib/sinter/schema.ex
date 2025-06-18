defmodule Sinter.Schema do
  @moduledoc """
  The unified schema definition engine for Sinter.

  This module provides the core schema definition functionality that serves as the
  single source of truth for all schema creation in Sinter. Both compile-time macros
  and runtime helpers ultimately use this module's `define/2` function.

  ## Core Principle

  All roads lead to `Sinter.Schema.define/2`. Whether you're using:
  - Compile-time `use_schema` macro
  - Runtime schema creation
  - Helper functions in the main `Sinter` module

  They all ultimately call this module's unified engine.
  """

  alias Sinter.{Types, Error}

  @type field_spec :: {atom(), Types.type_spec(), keyword()}
  @type schema_opts :: [
    title: String.t(),
    description: String.t(),
    strict: boolean(),
    post_validate: (map() -> {:ok, map()} | {:error, String.t() | Error.t()})
  ]

  @enforce_keys [:fields, :config]
  defstruct [:fields, :config, :metadata]

  @type t :: %__MODULE__{
    fields: %{atom() => field_definition()},
    config: config(),
    metadata: map()
  }

  @type field_definition :: %{
    name: atom(),
    type: Types.type_definition(),
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

  @doc """
  Defines a schema from a list of field specifications.

  This is the core engine for all schema creation in Sinter. All other schema
  definition methods ultimately call this function.

  ## Parameters

    * `field_specs` - List of field specifications in the format:
      `{field_name, type_spec, opts}`
    * `opts` - Schema configuration options

  ## Field Specification Format

      {field_name, type_spec, field_opts}

  Where:
  - `field_name` is an atom
  - `type_spec` is a type specification (see `Sinter.Types`)
  - `field_opts` are field-specific options

  ## Field Options

    * `:required` - Whether the field is required (default: true)
    * `:optional` - Convenience for `required: false`
    * `:constraints` - List of validation constraints
    * `:description` - Field description
    * `:example` - Example value
    * `:default` - Default value (makes field optional)

  ## Schema Options

    * `:title` - Schema title for documentation
    * `:description` - Schema description
    * `:strict` - Reject unknown fields (default: false)
    * `:post_validate` - Function for cross-field validation

  ## Examples

      # Basic schema
      fields = [
        {:name, :string, [required: true, min_length: 2]},
        {:age, :integer, [optional: true, gt: 0]}
      ]
      schema = Sinter.Schema.define(fields)

      # Schema with configuration
      schema = Sinter.Schema.define(fields,
        title: "User Schema",
        strict: true,
        post_validate: &validate_business_rules/1
      )

      # Complex field types
      fields = [
        {:tags, {:array, :string}, [min_items: 1]},
        {:metadata, {:map, {:string, :any}}, [optional: true]},
        {:status, {:union, [:pending, :active, :completed]}, [default: :pending]}
      ]
  """
  @spec define([field_spec()], schema_opts()) :: t()
  def define(field_specs, opts \\ []) when is_list(field_specs) do
    # Validate and normalize field specifications
    fields =
      field_specs
      |> Enum.map(&normalize_field_spec/1)
      |> Map.new(fn field -> {field.name, field} end)

    # Build configuration
    config = build_config(opts)

    # Create metadata
    metadata = %{
      created_at: DateTime.utc_now(),
      field_count: map_size(fields),
      sinter_version: Application.spec(:sinter, :vsn) || "unknown"
    }

    %__MODULE__{
      fields: fields,
      config: config,
      metadata: metadata
    }
  end

  @doc """
  Macro for defining schemas at compile-time.

  This macro provides a declarative DSL for schema definition that ultimately
  calls `define/2` under the hood. It's syntactic sugar that compiles to the
  same unified engine.

  ## Examples

      defmodule UserSchema do
        import Sinter.Schema

        use_schema do
          option :title, "User Schema"
          option :strict, true
          option :post_validate, &UserSchema.validate_business_rules/1

          field :name, :string, [required: true, min_length: 2]
          field :email, :string, [required: true, format: ~r/@/]
          field :age, :integer, [optional: true, gt: 0]
        end

        def validate_business_rules(data) do
          # Custom validation logic
          {:ok, data}
        end
      end
  """
  defmacro use_schema(do: block) do
    quote do
      @sinter_fields []
      @sinter_options []

      unquote(block)

      field_specs = Enum.reverse(@sinter_fields)
      schema_opts = @sinter_options |> Enum.reverse() |> Keyword.new()

      @sinter_schema Sinter.Schema.define(field_specs, schema_opts)

      def schema, do: @sinter_schema
    end
  end

  @doc """
  Adds an option to a schema being defined in a `use_schema` block.
  """
  defmacro option(key, value) do
    quote do
      @sinter_options [{unquote(key), unquote(value)} | @sinter_options]
    end
  end

  @doc """
  Defines a field in a `use_schema` block.
  """
  defmacro field(name, type_spec, opts \\ []) do
    quote do
      @sinter_fields [{unquote(name), unquote(type_spec), unquote(opts)} | @sinter_fields]
    end
  end

  @doc """
  Gets field definitions from a schema.

  ## Examples

      iex> fields = Sinter.Schema.fields(schema)
      iex> Map.keys(fields)
      [:name, :email, :age]
  """
  @spec fields(t()) :: %{atom() => field_definition()}
  def fields(%__MODULE__{fields: fields}), do: fields

  @doc """
  Gets the configuration from a schema.
  """
  @spec config(t()) :: config()
  def config(%__MODULE__{config: config}), do: config

  @doc """
  Gets required field names from a schema.
  """
  @spec required_fields(t()) :: [atom()]
  def required_fields(%__MODULE__{fields: fields}) do
    fields
    |> Enum.filter(fn {_name, field} -> field.required end)
    |> Enum.map(fn {name, _field} -> name end)
  end

  @doc """
  Gets optional field names from a schema.
  """
  @spec optional_fields(t()) :: [atom()]
  def optional_fields(%__MODULE__{fields: fields}) do
    fields
    |> Enum.reject(fn {_name, field} -> field.required end)
    |> Enum.map(fn {name, _field} -> name end)
  end

  @doc """
  Checks if a schema is configured for strict validation.
  """
  @spec strict?(t()) :: boolean()
  def strict?(%__MODULE__{config: %{strict: strict}}), do: strict

  @doc """
  Gets the post-validation function if configured.
  """
  @spec post_validate_fn(t()) :: function() | nil
  def post_validate_fn(%__MODULE__{config: %{post_validate: fun}}), do: fun

  @doc """
  Returns summary information about a schema.
  """
  @spec info(t()) :: map()
  def info(%__MODULE__{} = schema) do
    %{
      field_count: map_size(schema.fields),
      required_fields: required_fields(schema),
      optional_fields: optional_fields(schema),
      strict: strict?(schema),
      has_post_validation: not is_nil(post_validate_fn(schema)),
      title: schema.config.title,
      created_at: schema.metadata.created_at
    }
  end

  # Private helper functions

  @spec normalize_field_spec(field_spec()) :: field_definition()
  defp normalize_field_spec({name, type_spec, opts}) when is_atom(name) do
    # Extract field options
    required = determine_required(opts)
    constraints = extract_constraints(opts)

    %{
      name: name,
      type: Types.normalize_type(type_spec, constraints),
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
        false  # Fields with defaults are optional
      true ->
        true   # Default is required
    end
  end

  @spec extract_constraints(keyword()) :: keyword()
  defp extract_constraints(opts) do
    constraint_keys = [
      :min_length, :max_length, :min_items, :max_items,
      :gt, :lt, :gteq, :lteq, :format, :choices
    ]

    Keyword.take(opts, constraint_keys)
  end

  @spec build_config(schema_opts()) :: config()
  defp build_config(opts) do
    %{
      title: Keyword.get(opts, :title),
      description: Keyword.get(opts, :description),
      strict: Keyword.get(opts, :strict, false),
      post_validate: Keyword.get(opts, :post_validate)
    }
  end
end
