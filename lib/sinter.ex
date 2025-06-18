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

  ## Convenience Helpers

  This module provides convenient helper functions for common validation tasks
  that internally use the core unified engine.
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

      iex> Sinter.validate_type(:string, 123)
      {:error, [%Sinter.Error{code: :type_mismatch, ...}]}
  """
  @spec validate_type(Sinter.Types.type_spec(), term(), validation_opts()) :: validation_result()
  def validate_type(type_spec, value, opts \\ []) do
    constraints = Keyword.get(opts, :constraints, [])
    validation_opts = Keyword.drop(opts, [:constraints])

    # Create temporary single-field schema
    temp_schema = Schema.define([{:__temp__, type_spec, constraints}])

    case Validator.validate(temp_schema, %{__temp__: value}, validation_opts) do
      {:ok, %{__temp__: validated_value}} -> {:ok, validated_value}
      {:error, errors} -> {:error, errors}
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
    constraints = Keyword.get(opts, :constraints, [])
    validation_opts = Keyword.drop(opts, [:constraints])

    # Create temporary schema with named field
    temp_schema = Schema.define([{field_name, type_spec, constraints}])

    case Validator.validate(temp_schema, %{field_name => value}, validation_opts) do
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
  @spec validate_many([
    {Sinter.Types.type_spec(), term()} |
    {atom(), Sinter.Types.type_spec(), term()} |
    {atom(), Sinter.Types.type_spec(), term(), keyword()}
  ], validation_opts()) :: {:ok, [term()]} | {:error, %{integer() => [Sinter.Error.t()]}}
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
      iex> email_validator.("invalid")
      {:error, [%Sinter.Error{...}]}
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

    * `type_specs` - List of type specifications or `{name, type_spec}` tuples
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
    fields = Enum.map(field_specs, fn
      {name, type_spec} -> {name, type_spec, []}
      {name, type_spec, constraints} -> {name, type_spec, constraints}
    end)

    schema = Schema.define(fields)

    fn data ->
      Validator.validate(schema, data, base_opts)
    end
  end
end
