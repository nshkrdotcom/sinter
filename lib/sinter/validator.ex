defmodule Sinter.Validator do
  @moduledoc """
  The unified validation engine for Sinter.

  This module provides the single validation pipeline that handles all types
  of validation in Sinter. It processes schemas created by `Sinter.Schema.define/2`
  and runs a clean, predictable validation process.

  ## Validation Pipeline

  1. **Input Validation** - Ensure input is valid format
  2. **Required Field Check** - Verify all required fields are present
  3. **Field Validation** - Validate each field against its type and constraints
  4. **Strict Mode Check** - Reject unknown fields if strict mode enabled
  5. **Post Validation** - Run custom cross-field validation if configured

  ## Design Philosophy

  The validator focuses purely on validation - it does NOT perform data transformation.
  Any data transformation should be explicit in your application code, keeping
  your validation logic pure and your transformations visible.
  """

  alias Sinter.{Schema, Types, Error}

  @type validation_opts :: [
    coerce: boolean(),
    strict: boolean(),
    path: [atom() | String.t() | integer()]
  ]

  @type validation_result :: {:ok, map()} | {:error, [Error.t()]}

  @doc """
  Validates data against a Sinter schema.

  This is the core validation function that all other validation in Sinter
  ultimately uses. It implements a clean, predictable pipeline.

  ## Parameters

    * `schema` - A schema created by `Sinter.Schema.define/2`
    * `data` - The data to validate (must be a map)
    * `opts` - Validation options

  ## Options

    * `:coerce` - Enable type coercion (default: false)
    * `:strict` - Override schema's strict setting
    * `:path` - Base path for error reporting (default: [])

  ## Returns

    * `{:ok, validated_data}` - Validation succeeded
    * `{:error, errors}` - List of validation errors

  ## Examples

      iex> schema = Sinter.Schema.define([
      ...>   {:name, :string, [required: true]},
      ...>   {:age, :integer, [optional: true, gt: 0]}
      ...> ])
      iex> Sinter.Validator.validate(schema, %{name: "Alice", age: 30})
      {:ok, %{name: "Alice", age: 30}}

      iex> Sinter.Validator.validate(schema, %{age: 30})
      {:error, [%Sinter.Error{path: [:name], code: :required, ...}]}
  """
  @spec validate(Schema.t(), map(), validation_opts()) :: validation_result()
  def validate(%Schema{} = schema, data, opts \\ []) do
    path = Keyword.get(opts, :path, [])

    with :ok <- validate_input_format(data, path),
         :ok <- validate_required_fields(schema, data, path),
         {:ok, validated_fields} <- validate_fields(schema, data, opts),
         :ok <- validate_strict_mode(schema, validated_fields, data, opts),
         {:ok, final_data} <- apply_post_validation(schema, validated_fields, path) do
      {:ok, final_data}
    end
  end

  @doc """
  Validates data against a schema, raising an exception on failure.

  ## Examples

      iex> validated = Sinter.Validator.validate!(schema, data)
      %{name: "Alice", age: 30}

      # Raises Sinter.ValidationError on failure
  """
  @spec validate!(Schema.t(), map(), validation_opts()) :: map() | no_return()
  def validate!(schema, data, opts \\ []) do
    case validate(schema, data, opts) do
      {:ok, validated} -> validated
      {:error, errors} -> raise Sinter.ValidationError, errors: errors
    end
  end

  @doc """
  Validates multiple data items against the same schema efficiently.

  ## Parameters

    * `schema` - Schema to validate against
    * `data_list` - List of data maps to validate
    * `opts` - Validation options

  ## Returns

    * `{:ok, validated_list}` if all validations succeed
    * `{:error, errors_by_index}` if any validation fails

  ## Examples

      iex> data_list = [
      ...>   %{name: "Alice", age: 30},
      ...>   %{name: "Bob", age: 25}
      ...> ]
      iex> Sinter.Validator.validate_many(schema, data_list)
      {:ok, [%{name: "Alice", age: 30}, %{name: "Bob", age: 25}]}
  """
  @spec validate_many(Schema.t(), [map()], validation_opts()) ::
    {:ok, [map()]} | {:error, %{integer() => [Error.t()]}}
  def validate_many(%Schema{} = schema, data_list, opts \\ []) when is_list(data_list) do
    results =
      data_list
      |> Enum.with_index()
      |> Enum.map(fn {data, index} ->
        # Add index to base path for error reporting
        index_opts = Keyword.update(opts, :path, [index], &([index | &1]))

        case validate(schema, data, index_opts) do
          {:ok, validated} -> {:ok, {index, validated}}
          {:error, errors} -> {:error, {index, errors}}
        end
      end)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {oks, []} ->
        validated_list =
          oks
          |> Enum.sort_by(fn {:ok, {index, _}} -> index end)
          |> Enum.map(fn {:ok, {_index, data}} -> data end)
        {:ok, validated_list}

      {_, errors} ->
        error_map =
          errors
          |> Enum.map(fn {:error, {index, errs}} -> {index, errs} end)
          |> Map.new()
        {:error, error_map}
    end
  end

  # Private helper functions implementing the validation pipeline

  @spec validate_input_format(term(), [atom()]) :: :ok | {:error, [Error.t()]}
  defp validate_input_format(data, path) when is_map(data), do: :ok
  defp validate_input_format(data, path) do
    error = Error.new(path, :invalid_input, "Expected map, got: #{inspect(data)}")
    {:error, [error]}
  end

  @spec validate_required_fields(Schema.t(), map(), [atom()]) :: :ok | {:error, [Error.t()]}
  defp validate_required_fields(schema, data, path) do
    required_fields = Schema.required_fields(schema)

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(data, field) and not Map.has_key?(data, to_string(field))
      end)

    case missing_fields do
      [] -> :ok
      fields ->
        errors =
          Enum.map(fields, fn field ->
            Error.new(path ++ [field], :required, "field is required")
          end)
        {:error, errors}
    end
  end

  @spec validate_fields(Schema.t(), map(), validation_opts()) ::
    {:ok, map()} | {:error, [Error.t()]}
  defp validate_fields(schema, data, opts) do
    path = Keyword.get(opts, :path, [])
    coerce = Keyword.get(opts, :coerce, false)

    results =
      schema.fields
      |> Enum.map(fn {field_name, field_def} ->
        validate_single_field(field_name, field_def, data, path, coerce)
      end)

    case collect_field_results(results) do
      {:ok, validated_map} -> {:ok, validated_map}
      {:error, errors} -> {:error, errors}
    end
  end

  @spec validate_single_field(atom(), Schema.field_definition(), map(), [atom()], boolean()) ::
    {atom(), {:ok, term()} | {:error, [Error.t()]} | :skip}
  defp validate_single_field(field_name, field_def, data, base_path, coerce) do
    field_path = base_path ++ [field_name]
    field_value = get_field_value(data, field_name)

    case {field_value, field_def} do
      # Field missing but has default
      {:missing, %{default: default}} when not is_nil(default) ->
        {field_name, {:ok, default}}

      # Field missing and optional
      {:missing, %{required: false}} ->
        {field_name, :skip}

      # Field missing and required
      {:missing, %{required: true}} ->
        error = Error.new(field_path, :required, "field is required")
        {field_name, {:error, [error]}}

      # Field present - validate it
      {value, field_def} ->
        result = validate_field_value(field_def, value, field_path, coerce)
        {field_name, result}
    end
  end

  @spec get_field_value(map(), atom()) :: term() | :missing
  defp get_field_value(data, field_name) do
    cond do
      Map.has_key?(data, field_name) -> Map.get(data, field_name)
      Map.has_key?(data, to_string(field_name)) -> Map.get(data, to_string(field_name))
      true -> :missing
    end
  end

  @spec validate_field_value(Schema.field_definition(), term(), [atom()], boolean()) ::
    {:ok, term()} | {:error, [Error.t()]}
  defp validate_field_value(field_def, value, path, coerce) do
    # First apply coercion if enabled
    value_to_validate =
      if coerce do
        case Types.coerce(field_def.type, value) do
          {:ok, coerced} -> coerced
          {:error, _} -> value  # Keep original on coercion failure
        end
      else
        value
      end

    # Then validate the type
    case Types.validate(field_def.type, value_to_validate, path) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, List.wrap(errors)}
    end
  end

  @spec collect_field_results([{atom(), {:ok, term()} | {:error, [Error.t()]} | :skip}]) ::
    {:ok, map()} | {:error, [Error.t()]}
  defp collect_field_results(results) do
    {successes, errors} =
      Enum.reduce(results, {%{}, []}, fn
        {field_name, {:ok, value}}, {acc_map, acc_errors} ->
          {Map.put(acc_map, field_name, value), acc_errors}

        {_field_name, :skip}, {acc_map, acc_errors} ->
          {acc_map, acc_errors}

        {_field_name, {:error, field_errors}}, {acc_map, acc_errors} ->
          {acc_map, field_errors ++ acc_errors}
      end)

    case errors do
      [] -> {:ok, successes}
      _ -> {:error, Enum.reverse(errors)}
    end
  end

  @spec validate_strict_mode(Schema.t(), map(), map(), validation_opts()) ::
    :ok | {:error, [Error.t()]}
  defp validate_strict_mode(schema, validated_data, original_data, opts) do
    # Check if strict mode is enabled (schema setting or option override)
    strict = Keyword.get(opts, :strict, Schema.strict?(schema))
    path = Keyword.get(opts, :path, [])

    if strict do
      check_extra_fields(validated_data, original_data, path)
    else
      :ok
    end
  end

  @spec check_extra_fields(map(), map(), [atom()]) :: :ok | {:error, [Error.t()]}
  defp check_extra_fields(validated_data, original_data, path) do
    validated_keys = Map.keys(validated_data) |> Enum.map(&to_string/1) |> MapSet.new()
    original_keys = Map.keys(original_data) |> Enum.map(&to_string/1) |> MapSet.new()

    extra_keys = MapSet.difference(original_keys, validated_keys) |> MapSet.to_list()

    case extra_keys do
      [] -> :ok
      keys ->
        error = Error.new(path, :extra_fields, "unexpected fields: #{inspect(keys)}")
        {:error, [error]}
    end
  end

  @spec apply_post_validation(Schema.t(), map(), [atom()]) ::
    {:ok, map()} | {:error, [Error.t()]}
  defp apply_post_validation(schema, validated_data, path) do
    case Schema.post_validate_fn(schema) do
      nil ->
        {:ok, validated_data}

      post_validate_fn when is_function(post_validate_fn, 1) ->
        try do
          case post_validate_fn.(validated_data) do
            {:ok, final_data} when is_map(final_data) ->
              {:ok, final_data}

            {:error, message} when is_binary(message) ->
              error = Error.new(path, :post_validation, message)
              {:error, [error]}

            {:error, %Error{} = error} ->
              {:error, [error]}

            other ->
              error = Error.new(path, :post_validation,
                "Post-validation function returned invalid format: #{inspect(other)}")
              {:error, [error]}
          end
        rescue
          e ->
            error = Error.new(path, :post_validation,
              "Post-validation function failed: #{Exception.message(e)}")
            {:error, [error]}
        end
    end
  end
end
