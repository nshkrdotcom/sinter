defmodule Sinter do
  @moduledoc """
  Unified schema definition, validation, and JSON generation for Elixir.

  Sinter provides a focused, high-performance schema validation library designed
  specifically for dynamic frameworks. It follows the "One True Way" principle:

  - **One way** to define schemas (unified core engine)
  - **One way** to validate data (single validation pipeline)
  - **One way** to generate JSON Schema (unified generator)

  ## Quick Start

      # Define a schema
      fields = [
        {:name, :string, [required: true]},
        {:age, :integer, [optional: true, gt: 0]}
      ]
      schema = Sinter.Schema.define(fields)

      # Validate data
      {:ok, validated} = Sinter.Validator.validate(schema, %{
        name: "Alice",
        age: 30
      })

      # Generate JSON Schema
      json_schema = Sinter.JsonSchema.generate(schema)

  ## Dynamic Schema Creation

  Sinter supports dynamic schema creation for teleprompters and runtime optimization:

      # Infer schema from examples (perfect for MIPRO teleprompter)
      examples = [
        %{"name" => "Alice", "age" => 30},
        %{"name" => "Bob", "age" => 25}
      ]
      schema = Sinter.infer_schema(examples)

      # Merge schemas for signature composition
      input_schema = Sinter.Schema.define([{:query, :string, [required: true]}])
      output_schema = Sinter.Schema.define([{:answer, :string, [required: true]}])
      program_schema = Sinter.merge_schemas([input_schema, output_schema])

  ## Convenience Helpers

  This module provides convenient helper functions for common validation tasks
  that internally use the core unified engine.

  ## Design Philosophy

  Sinter distills data validation to its pure essence, extracting the essential
  power from complex systems while eliminating unnecessary abstraction. It follows
  three key principles:

  1. **Validation, Not Transformation** - Sinter validates data structure and constraints
     but does not perform business logic transformations
  2. **Runtime-First Design** - Schemas are data structures that can be created and
     modified at runtime, perfect for dynamic frameworks
  3. **Unified Core Engine** - All validation flows through a single, well-tested
     pipeline for consistency and reliability
  """

  alias Sinter.{Schema, Validator}

  @type schema :: Schema.t()
  @type validation_opts :: Validator.validation_opts()
  @type validation_result :: {:ok, term()} | {:error, [Sinter.Error.t()]}

  @doc """
  Validates a single value against a type specification.

  This is a convenient helper for one-off type validation that creates a
  temporary schema internally and uses the unified validation engine.

  ## Parameters

    * `type_spec` - The type specification to validate against
    * `value` - The value to validate
    * `opts` - Validation options

  ## Options

    * `:coerce` - Enable type coercion (default: false)
    * `:constraints` - Additional constraints to apply

  ## Returns

    * `{:ok, validated_value}` on success
    * `{:error, errors}` on validation failure

  ## Examples

      iex> Sinter.validate_type(:integer, "42", coerce: true)
      {:ok, 42}

      iex> Sinter.validate_type({:array, :string}, ["hello", "world"])
      {:ok, ["hello", "world"]}

      iex> {:error, [error]} = Sinter.validate_type(:string, 123)
      iex> error.code
      :type
  """
  @spec validate_type(Sinter.Types.type_spec(), term(), validation_opts()) :: validation_result()
  def validate_type(type_spec, value, opts \\ []) do
    # Extract explicit constraints or treat all non-validation options as constraints
    explicit_constraints = Keyword.get(opts, :constraints, [])
    validation_option_keys = [:coerce, :strict, :constraints]

    {validation_only_opts, constraint_opts} = Keyword.split(opts, validation_option_keys)

    # Combine explicit constraints with direct constraint options
    constraints = explicit_constraints ++ constraint_opts

    # Create temporary single-field schema
    temp_schema = Schema.define([{:__temp__, type_spec, constraints}])

    case Validator.validate(
           temp_schema,
           %{__temp__: value},
           Keyword.delete(validation_only_opts, :constraints)
         ) do
      {:ok, %{__temp__: validated_value}} ->
        {:ok, validated_value}

      {:error, errors} ->
        # Strip the temporary field name from error paths
        fixed_errors =
          Enum.map(errors, fn error ->
            case error.path do
              [:__temp__ | rest] -> %{error | path: rest}
              path -> %{error | path: path}
            end
          end)

        {:error, fixed_errors}
    end
  end

  @doc """
  Validates a single named value against a type specification.

  This is a convenient helper for single field validation that creates a
  temporary schema internally.

  ## Parameters

    * `field_name` - Name for the field (used in error messages)
    * `type_spec` - The type specification to validate against
    * `value` - The value to validate
    * `opts` - Validation options and constraints

  ## Examples

      iex> Sinter.validate_value(:email, :string, "test@example.com",
      ...>   constraints: [format: ~r/@/])
      {:ok, "test@example.com"}

      iex> Sinter.validate_value(:score, :integer, "95",
      ...>   coerce: true, constraints: [gteq: 0, lteq: 100])
      {:ok, 95}
  """
  @spec validate_value(atom(), Sinter.Types.type_spec(), term(), validation_opts()) ::
          validation_result()
  def validate_value(field_name, type_spec, value, opts \\ []) do
    # Extract explicit constraints or treat all non-validation options as constraints
    explicit_constraints = Keyword.get(opts, :constraints, [])
    validation_option_keys = [:coerce, :strict, :constraints]

    {validation_only_opts, constraint_opts} = Keyword.split(opts, validation_option_keys)

    # Combine explicit constraints with direct constraint options
    constraints = explicit_constraints ++ constraint_opts

    # Create temporary schema with named field
    temp_schema = Schema.define([{field_name, type_spec, constraints}])

    case Validator.validate(
           temp_schema,
           %{field_name => value},
           Keyword.delete(validation_only_opts, :constraints)
         ) do
      {:ok, validated_map} -> {:ok, Map.get(validated_map, field_name)}
      {:error, errors} -> {:error, errors}
    end
  end

  @doc """
  Validates multiple values efficiently against their respective type specifications.

  ## Parameters

    * `type_value_pairs` - List of `{type_spec, value}` or `{field_name, type_spec, value}` tuples
    * `opts` - Validation options

  ## Examples

      iex> Sinter.validate_many([
      ...>   {:string, "hello"},
      ...>   {:integer, 42},
      ...>   {:email, :string, "test@example.com", [format: ~r/@/]}
      ...> ])
      {:ok, ["hello", 42, "test@example.com"]}
  """
  @spec validate_many(
          [
            {Sinter.Types.type_spec(), term()}
            | {atom(), Sinter.Types.type_spec(), term()}
            | {atom(), Sinter.Types.type_spec(), term(), keyword()}
          ],
          validation_opts()
        ) :: {:ok, [term()]} | {:error, %{integer() => [Sinter.Error.t()]}}
  def validate_many(type_value_pairs, opts \\ []) do
    results =
      type_value_pairs
      |> Enum.with_index()
      |> Enum.map(fn {spec, index} ->
        case spec do
          {type_spec, value} ->
            validate_type(type_spec, value, opts)

          {field_name, type_spec, value} ->
            validate_value(field_name, type_spec, value, opts)

          {field_name, type_spec, value, field_opts} ->
            merged_opts = Keyword.merge(opts, field_opts)
            validate_value(field_name, type_spec, value, merged_opts)
        end
        |> case do
          {:ok, validated} -> {:ok, {index, validated}}
          {:error, errors} -> {:error, {index, errors}}
        end
      end)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {oks, []} ->
        validated_values =
          oks
          |> Enum.map(fn {:ok, {_index, value}} -> value end)

        {:ok, validated_values}

      {_, errors} ->
        error_map =
          errors
          |> Enum.map(fn {:error, {index, errs}} -> {index, errs} end)
          |> Map.new()

        {:error, error_map}
    end
  end

  @doc """
  Creates a reusable validation function for a specific type and constraints.

  Returns a function that can be used to validate multiple values against
  the same specification efficiently.

  ## Parameters

    * `type_spec` - The type specification
    * `base_opts` - Base validation options and constraints

  ## Examples

      iex> email_validator = Sinter.validator_for(:string,
      ...>   constraints: [format: ~r/@/])
      iex> email_validator.("test@example.com")
      {:ok, "test@example.com"}
      iex> {:error, [error]} = email_validator.("invalid")
      iex> error.code
      :format
  """
  @spec validator_for(Sinter.Types.type_spec(), validation_opts()) ::
          (term() -> validation_result())
  def validator_for(type_spec, base_opts \\ []) do
    fn value ->
      validate_type(type_spec, value, base_opts)
    end
  end

  @doc """
  Creates a batch validator function for multiple type specifications.

  ## Parameters

    * `field_specs` - List of field specifications or `{name, type_spec}` tuples
    * `base_opts` - Base validation options

  ## Examples

      iex> batch_validator = Sinter.batch_validator_for([
      ...>   {:name, :string},
      ...>   {:age, :integer}
      ...> ])
      iex> batch_validator.(%{name: "Alice", age: 30})
      {:ok, %{name: "Alice", age: 30}}
  """
  @spec batch_validator_for([{atom(), Sinter.Types.type_spec()}], validation_opts()) ::
          (map() -> {:ok, map()} | {:error, [Sinter.Error.t()]})
  def batch_validator_for(field_specs, base_opts \\ []) do
    # Create schema once for reuse
    fields =
      Enum.map(field_specs, fn
        {name, type_spec} -> {name, type_spec, []}
        {name, type_spec, constraints} -> {name, type_spec, constraints}
      end)

    schema = Schema.define(fields)

    fn data ->
      Validator.validate(schema, data, base_opts)
    end
  end

  # ============================================================================
  # PHASE 2: DYNAMIC SCHEMA CREATION FOR DSPEX
  # ============================================================================

  @doc """
  Creates a schema by analyzing examples to infer field types and requirements.

  This function is essential for DSPEx teleprompters like MIPRO that need to
  dynamically optimize schemas based on program execution examples.

  ## Parameters

    * `examples` - List of maps representing example data
    * `opts` - Schema creation options

  ## Options

    * `:title` - Schema title
    * `:description` - Schema description
    * `:strict` - Whether to reject unknown fields (default: false)
    * `:min_occurrence_ratio` - Minimum ratio for field to be considered required (default: 0.8)

  ## Returns

    * `Schema.t()` - A schema inferred from the examples

  ## Examples

      iex> examples = [
      ...>   %{"name" => "Alice", "age" => 30},
      ...>   %{"name" => "Bob", "age" => 25},
      ...>   %{"name" => "Charlie", "age" => 35}
      ...> ]
      iex> schema = Sinter.infer_schema(examples)
      iex> fields = Sinter.Schema.fields(schema)
      iex> fields[:name].type
      :string
      iex> fields[:age].type
      :integer

  ## Algorithm

  1. **Field Discovery**: Find all unique field names across examples
  2. **Type Inference**: Determine the most common type for each field
  3. **Requirement Analysis**: Fields present in >= min_occurrence_ratio are required
  4. **Constraint Inference**: Infer basic constraints from value patterns
  """
  @spec infer_schema([map()], keyword()) :: Schema.t()
  def infer_schema(examples, opts \\ []) when is_list(examples) do
    if Enum.empty?(examples) do
      raise ArgumentError, "Cannot infer schema from empty examples list"
    end

    # Validate all examples are maps
    unless Enum.all?(examples, &is_map/1) do
      raise ArgumentError, "All examples must be maps"
    end

    min_occurrence_ratio = Keyword.get(opts, :min_occurrence_ratio, 0.8)
    example_count = length(examples)

    # Step 1: Discover all field names
    all_field_names =
      examples
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.uniq()

    # Step 2: Analyze each field
    field_specs =
      Enum.map(all_field_names, fn field_name ->
        analyze_field(field_name, examples, example_count, min_occurrence_ratio)
      end)

    # Step 3: Create schema with inferred fields
    schema_opts = Keyword.drop(opts, [:min_occurrence_ratio])
    Schema.define(field_specs, schema_opts)
  end

  @doc """
  Merges multiple schemas into a single schema.

  This is useful for DSPEx signature composition where you need to combine
  input and output schemas or merge component signatures.

  ## Parameters

    * `schemas` - List of Schema.t() to merge
    * `opts` - Optional schema configuration overrides

  ## Merge Rules

  1. **Fields**: All fields from all schemas are included
  2. **Conflicts**: Later schemas override earlier ones for conflicting field definitions
  3. **Configuration**: First non-nil configuration value wins, except for `:strict` where last wins

  ## Examples

      iex> input_schema = Sinter.Schema.define([
      ...>   {:query, :string, [required: true]}
      ...> ])
      iex> output_schema = Sinter.Schema.define([
      ...>   {:answer, :string, [required: true]},
      ...>   {:confidence, :float, [optional: true]}
      ...> ])
      iex> merged = Sinter.merge_schemas([input_schema, output_schema])
      iex> fields = Sinter.Schema.fields(merged)
      iex> Map.keys(fields)
      [:query, :answer, :confidence]
  """
  @spec merge_schemas([Schema.t()], keyword()) :: Schema.t()
  def merge_schemas(schemas, opts \\ []) when is_list(schemas) do
    if Enum.empty?(schemas) do
      raise ArgumentError, "Cannot merge empty schemas list"
    end

    # Collect all fields from all schemas
    all_fields =
      schemas
      |> Enum.flat_map(fn schema ->
        Schema.fields(schema)
        |> Enum.map(fn {name, field_def} ->
          # Convert field definition back to field spec format
          {name, field_def.type, build_field_options(field_def)}
        end)
      end)

    # Handle field conflicts - later definitions override earlier ones
    unique_fields =
      all_fields
      # Reverse so later entries have precedence
      |> Enum.reverse()
      |> Enum.uniq_by(fn {name, _type, _opts} -> name end)
      # Restore original order
      |> Enum.reverse()

    # Merge configurations
    merged_config = merge_schema_configs(schemas)
    final_opts = Keyword.merge(merged_config, opts)

    Schema.define(unique_fields, final_opts)
  end

  # ============================================================================
  # PRIVATE HELPER FUNCTIONS FOR SCHEMA INFERENCE
  # ============================================================================

  # Analyzes a single field across all examples to determine its specification
  @spec analyze_field(String.t() | atom(), [map()], integer(), float()) ::
          {atom(), Sinter.Types.type_spec(), keyword()}
  defp analyze_field(field_name, examples, example_count, min_occurrence_ratio) do
    # Normalize field name to atom
    field_atom = if is_binary(field_name), do: String.to_atom(field_name), else: field_name

    # Extract all values for this field
    field_values =
      examples
      |> Enum.map(&Map.get(&1, field_name))
      |> Enum.reject(&is_nil/1)

    occurrence_count = length(field_values)
    occurrence_ratio = occurrence_count / example_count

    # Determine if field is required
    required = occurrence_ratio >= min_occurrence_ratio

    # Infer type from values
    inferred_type = infer_field_type(field_values)

    # Build field options
    field_opts = [required: required]

    {field_atom, inferred_type, field_opts}
  end

  # Infers the type of a field from its values
  @spec infer_field_type([term()]) :: Sinter.Types.type_spec()
  defp infer_field_type([]), do: :any

  defp infer_field_type(values) do
    # Group values by their Elixir type
    type_frequencies =
      values
      |> Enum.map(&get_elixir_type/1)
      |> Enum.frequencies()

    # Get the most common type
    {most_common_type, _frequency} =
      type_frequencies
      |> Enum.max_by(fn {_type, count} -> count end)

    most_common_type
  end

  # Maps an Elixir value to its Sinter type specification
  @spec get_elixir_type(term()) :: Sinter.Types.type_spec()
  defp get_elixir_type(value) when is_binary(value), do: :string
  defp get_elixir_type(value) when is_integer(value), do: :integer
  defp get_elixir_type(value) when is_float(value), do: :float
  defp get_elixir_type(value) when is_boolean(value), do: :boolean
  defp get_elixir_type(value) when is_atom(value), do: :atom
  defp get_elixir_type(value) when is_map(value), do: :map

  defp get_elixir_type(value) when is_list(value) do
    case infer_array_type(value) do
      :mixed -> {:array, :any}
      inner_type -> {:array, inner_type}
    end
  end

  defp get_elixir_type(_value), do: :any

  # Infers the inner type of an array
  @spec infer_array_type([term()]) :: Sinter.Types.type_spec() | :mixed
  defp infer_array_type([]), do: :any

  defp infer_array_type(list) do
    # Get types of all elements
    element_types =
      list
      |> Enum.map(&get_elixir_type/1)
      |> Enum.uniq()

    case element_types do
      # All elements same type
      [single_type] -> single_type
      # Mixed types, use :any
      _multiple -> :mixed
    end
  end

  # Builds field options from a field definition (for schema merging)
  @spec build_field_options(Schema.field_definition()) :: keyword()
  defp build_field_options(field_def) do
    opts = [required: field_def.required]

    opts = if field_def.description, do: [description: field_def.description] ++ opts, else: opts
    opts = if field_def.example, do: [example: field_def.example] ++ opts, else: opts
    opts = if field_def.default, do: [default: field_def.default] ++ opts, else: opts

    # Add constraints
    field_def.constraints ++ opts
  end

  # Merges configuration from multiple schemas
  @spec merge_schema_configs([Schema.t()]) :: keyword()
  defp merge_schema_configs(schemas) do
    configs = Enum.map(schemas, &Schema.config/1)

    # Merge with specific rules
    merged = %{
      title: find_first_non_nil(configs, :title),
      description: find_first_non_nil(configs, :description),
      strict: find_last_non_nil(configs, :strict, false),
      post_validate: find_first_non_nil(configs, :post_validate)
    }

    # Convert to keyword list, filtering out nil values
    merged
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.into([])
  end

  # Helper to find first non-nil value for a key across configs
  @spec find_first_non_nil([map()], atom()) :: term() | nil
  defp find_first_non_nil(configs, key) do
    configs
    |> Enum.map(&Map.get(&1, key))
    |> Enum.find(&(not is_nil(&1)))
  end

  # Helper to find last non-nil value for a key across configs, with default
  @spec find_last_non_nil([map()], atom(), term()) :: term()
  defp find_last_non_nil(configs, key, default) do
    configs
    |> Enum.map(&Map.get(&1, key))
    |> Enum.reverse()
    |> Enum.find(&(not is_nil(&1)))
    |> case do
      nil -> default
      value -> value
    end
  end
end
