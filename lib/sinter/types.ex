defmodule Sinter.Types do
  @moduledoc """
  Type system for Sinter schemas.

  This module provides the core type system used throughout Sinter, including:
  - Type definitions and normalization
  - Type validation
  - Type coercion
  - JSON Schema conversion

  ## Type Specifications

  Sinter supports several types of type specifications:

  ### Basic Types
  - `:string` - String values
  - `:integer` - Integer values
  - `:float` - Float values
  - `:boolean` - Boolean values
  - `:atom` - Atom values
  - `:any` - Any value (no validation)

  ### Complex Types
  - `{:array, inner_type}` - Array/list of inner_type
  - `{:map, {key_type, value_type}}` - Map with typed keys and values
  - `{:union, [type1, type2, ...]}` - Union of multiple types
  - `{:tuple, [type1, type2, ...]}` - Tuple with fixed types

  ### Schema References
  - Schema modules that implement validation
  """

  alias Sinter.Error

  @type type_spec ::
    atom() |
    {atom(), type_spec()} |
    {atom(), type_spec(), keyword()} |
    {atom(), [type_spec()]} |
    {atom(), {type_spec(), type_spec()}}

  @type type_definition ::
    {:type, atom(), keyword()} |
    {:array, type_definition(), keyword()} |
    {:map, {type_definition(), type_definition()}, keyword()} |
    {:union, [type_definition()], keyword()} |
    {:tuple, [type_definition()]} |
    {:ref, module()}

  @doc """
  Normalizes a type specification into a canonical type definition.

  This function converts various type specification formats into the internal
  type definition format used throughout Sinter.

  ## Parameters

    * `type_spec` - The type specification to normalize
    * `constraints` - Additional constraints to apply (default: [])

  ## Examples

      iex> Sinter.Types.normalize_type(:string)
      {:type, :string, []}

      iex> Sinter.Types.normalize_type({:array, :integer})
      {:array, {:type, :integer, []}, []}

      iex> Sinter.Types.normalize_type(:string, [min_length: 3])
      {:type, :string, [min_length: 3]}
  """
  @spec normalize_type(type_spec(), keyword()) :: type_definition()
  def normalize_type(type_spec, constraints \\ [])

  # Basic atom types
  def normalize_type(type, constraints) when type in [:string, :integer, :float, :boolean, :atom, :any] do
    {:type, type, constraints}
  end

  # Array types
  def normalize_type({:array, inner_type}, constraints) do
    normalized_inner = normalize_type(inner_type, [])
    {:array, normalized_inner, constraints}
  end

  def normalize_type({:array, inner_type, inner_constraints}, constraints) do
    normalized_inner = normalize_type(inner_type, inner_constraints)
    {:array, normalized_inner, constraints}
  end

  # Map types
  def normalize_type({:map, {key_type, value_type}}, constraints) do
    normalized_key = normalize_type(key_type, [])
    normalized_value = normalize_type(value_type, [])
    {:map, {normalized_key, normalized_value}, constraints}
  end

  # Union types
  def normalize_type({:union, types}, constraints) when is_list(types) do
    normalized_types = Enum.map(types, &normalize_type(&1, []))
    {:union, normalized_types, constraints}
  end

  # Tuple types
  def normalize_type({:tuple, types}, _constraints) when is_list(types) do
    normalized_types = Enum.map(types, &normalize_type(&1, []))
    {:tuple, normalized_types}
  end

  # Schema module references
  def normalize_type(module, _constraints) when is_atom(module) do
    if schema_module?(module) do
      {:ref, module}
    else
      # Treat as literal atom value
      {:type, :atom, [choices: [module]]}
    end
  end

  # Already normalized types
  def normalize_type({:type, type, existing_constraints}, new_constraints) do
    {:type, type, existing_constraints ++ new_constraints}
  end

  def normalize_type({:array, inner, existing_constraints}, new_constraints) do
    {:array, inner, existing_constraints ++ new_constraints}
  end

  def normalize_type({:map, types, existing_constraints}, new_constraints) do
    {:map, types, existing_constraints ++ new_constraints}
  end

  def normalize_type({:union, types, existing_constraints}, new_constraints) do
    {:union, types, existing_constraints ++ new_constraints}
  end

  def normalize_type({:ref, module}, _constraints) do
    {:ref, module}
  end

  @doc """
  Validates a value against a type definition.

  ## Parameters

    * `type_def` - The type definition to validate against
    * `value` - The value to validate
    * `path` - Path for error reporting (default: [])

  ## Returns

    * `{:ok, validated_value}` on success
    * `{:error, errors}` on failure

  ## Examples

      iex> Sinter.Types.validate({:type, :string, []}, "hello")
      {:ok, "hello"}

      iex> Sinter.Types.validate({:type, :integer, [gt: 0]}, 5)
      {:ok, 5}

      iex> Sinter.Types.validate({:type, :string, []}, 123)
      {:error, [%Sinter.Error{...}]}
  """
  @spec validate(type_definition(), term(), [atom()]) ::
    {:ok, term()} | {:error, [Error.t()]}
  def validate(type_def, value, path \\ [])

  # Basic type validation
  def validate({:type, base_type, constraints}, value, path) do
    case validate_base_type(base_type, value, path) do
      {:ok, validated} -> apply_constraints(validated, constraints, path)
      {:error, _} = error -> error
    end
  end

  # Array validation
  def validate({:array, inner_type, constraints}, value, path) when is_list(value) do
    case validate_array_items(value, inner_type, path) do
      {:ok, validated_items} ->
        apply_constraints(validated_items, constraints, path)
      {:error, _} = error ->
        error
    end
  end

  def validate({:array, _inner_type, _constraints}, value, path) do
    error = Error.new(path, :type_mismatch, "expected array, got #{inspect(value)}")
    {:error, [error]}
  end

  # Map validation
  def validate({:map, {key_type, value_type}, constraints}, value, path) when is_map(value) do
    case validate_map_entries(value, key_type, value_type, path) do
      {:ok, validated_map} ->
        apply_constraints(validated_map, constraints, path)
      {:error, _} = error ->
        error
    end
  end

  def validate({:map, _types, _constraints}, value, path) do
    error = Error.new(path, :type_mismatch, "expected map, got #{inspect(value)}")
    {:error, [error]}
  end

  # Union validation
  def validate({:union, types, _constraints}, value, path) do
    # Try each type until one succeeds
    case try_union_types(types, value, path) do
      {:ok, validated} -> {:ok, validated}
      {:error, _} ->
        error = Error.new(path, :type_mismatch, "value does not match any type in union")
        {:error, [error]}
    end
  end

  # Tuple validation
  def validate({:tuple, types}, value, path) when is_tuple(value) do
    if tuple_size(value) == length(types) do
      validate_tuple_elements(Tuple.to_list(value), types, path)
    else
      error = Error.new(path, :type_mismatch,
        "expected tuple of size #{length(types)}, got size #{tuple_size(value)}")
      {:error, [error]}
    end
  end

  def validate({:tuple, _types}, value, path) do
    error = Error.new(path, :type_mismatch, "expected tuple, got #{inspect(value)}")
    {:error, [error]}
  end

  # Schema reference validation
  def validate({:ref, module}, value, path) do
    if function_exported?(module, :validate, 1) do
      case module.validate(value) do
        {:ok, validated} -> {:ok, validated}
        {:error, reason} -> {:error, [Error.new(path, :schema_validation, reason)]}
      end
    else
      error = Error.new(path, :invalid_schema, "#{module} does not implement validate/1")
      {:error, [error]}
    end
  end

  @doc """
  Attempts to coerce a value to the specified type.

  ## Parameters

    * `type_def` - The type definition to coerce to
    * `value` - The value to coerce

  ## Returns

    * `{:ok, coerced_value}` on success
    * `{:error, reason}` on failure

  ## Examples

      iex> Sinter.Types.coerce({:type, :integer, []}, "42")
      {:ok, 42}

      iex> Sinter.Types.coerce({:type, :string, []}, 123)
      {:ok, "123"}
  """
  @spec coerce(type_definition(), term()) :: {:ok, term()} | {:error, String.t()}
  def coerce({:type, base_type, _constraints}, value) do
    coerce_base_type(base_type, value)
  end

  def coerce({:array, inner_type, _constraints}, value) when is_list(value) do
    results = Enum.map(value, &coerce(inner_type, &1))

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {oks, []} ->
        coerced_values = Enum.map(oks, fn {:ok, val} -> val end)
        {:ok, coerced_values}
      {_, _errors} ->
        {:error, "failed to coerce array elements"}
    end
  end

  def coerce({:union, types, _constraints}, value) do
    # Try coercing with each type until one succeeds
    Enum.reduce_while(types, {:error, "no type in union could coerce value"}, fn type, _acc ->
      case coerce(type, value) do
        {:ok, coerced} -> {:halt, {:ok, coerced}}
        {:error, _} -> {:cont, {:error, "coercion failed"}}
      end
    end)
  end

  def coerce(_type_def, value) do
    # For types that don't support coercion, return the value as-is
    {:ok, value}
  end

  @doc """
  Converts a type definition to JSON Schema format.

  ## Parameters

    * `type_def` - The type definition to convert

  ## Returns

    * JSON Schema map

  ## Examples

      iex> Sinter.Types.to_json_schema({:type, :string, [min_length: 3]})
      %{"type" => "string", "minLength" => 3}
  """
  @spec to_json_schema(type_definition()) :: map()
  def to_json_schema({:type, base_type, constraints}) do
    base_type_to_json_schema(base_type)
    |> apply_json_schema_constraints(constraints)
  end

  def to_json_schema({:array, inner_type, constraints}) do
    %{
      "type" => "array",
      "items" => to_json_schema(inner_type)
    }
    |> apply_json_schema_constraints(constraints)
  end

  def to_json_schema({:map, {_key_type, value_type}, constraints}) do
    # JSON Schema maps are always string-keyed
    %{
      "type" => "object",
      "additionalProperties" => to_json_schema(value_type)
    }
    |> apply_json_schema_constraints(constraints)
  end

  def to_json_schema({:union, types, _constraints}) do
    %{
      "oneOf" => Enum.map(types, &to_json_schema/1)
    }
  end

  def to_json_schema({:tuple, types}) do
    %{
      "type" => "array",
      "items" => false,
      "prefixItems" => Enum.map(types, &to_json_schema/1),
      "minItems" => length(types),
      "maxItems" => length(types)
    }
  end

  def to_json_schema({:ref, _module}) do
    # Schema references would need a reference store for full implementation
    # For now, return a generic object
    %{"type" => "object"}
  end

  # Private helper functions

  @spec schema_module?(atom()) :: boolean()
  defp schema_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :validate, 1)
  end

  @spec validate_base_type(atom(), term(), [atom()]) :: {:ok, term()} | {:error, [Error.t()]}
  defp validate_base_type(:string, value, _path) when is_binary(value), do: {:ok, value}
  defp validate_base_type(:integer, value, _path) when is_integer(value), do: {:ok, value}
  defp validate_base_type(:float, value, _path) when is_float(value), do: {:ok, value}
  defp validate_base_type(:boolean, value, _path) when is_boolean(value), do: {:ok, value}
  defp validate_base_type(:atom, value, _path) when is_atom(value), do: {:ok, value}
  defp validate_base_type(:any, value, _path), do: {:ok, value}

  defp validate_base_type(expected_type, value, path) do
    error = Error.new(path, :type_mismatch, "expected #{expected_type}, got #{inspect(value)}")
    {:error, [error]}
  end

  @spec validate_array_items([term()], type_definition(), [atom()]) ::
    {:ok, [term()]} | {:error, [Error.t()]}
  defp validate_array_items(items, inner_type, base_path) do
    results =
      items
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        item_path = base_path ++ [index]
        validate(inner_type, item, item_path)
      end)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {oks, []} ->
        validated_items = Enum.map(oks, fn {:ok, item} -> item end)
        {:ok, validated_items}
      {_, errors} ->
        all_errors = Enum.flat_map(errors, fn {:error, errs} -> errs end)
        {:error, all_errors}
    end
  end

  @spec validate_map_entries(map(), type_definition(), type_definition(), [atom()]) ::
    {:ok, map()} | {:error, [Error.t()]}
  defp validate_map_entries(map, key_type, value_type, base_path) do
    results =
      Enum.map(map, fn {key, value} ->
        key_path = base_path ++ [:key]
        value_path = base_path ++ [key]

        with {:ok, validated_key} <- validate(key_type, key, key_path),
             {:ok, validated_value} <- validate(value_type, value, value_path) do
          {:ok, {validated_key, validated_value}}
        else
          {:error, errors} -> {:error, errors}
        end
      end)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {oks, []} ->
        validated_map =
          oks
          |> Enum.map(fn {:ok, {k, v}} -> {k, v} end)
          |> Map.new()
        {:ok, validated_map}
      {_, errors} ->
        all_errors = Enum.flat_map(errors, fn {:error, errs} -> errs end)
        {:error, all_errors}
    end
  end

  @spec try_union_types([type_definition()], term(), [atom()]) ::
    {:ok, term()} | {:error, [Error.t()]}
  defp try_union_types(types, value, path) do
    Enum.reduce_while(types, {:error, []}, fn type, _acc ->
      case validate(type, value, path) do
        {:ok, validated} -> {:halt, {:ok, validated}}
        {:error, _} -> {:cont, {:error, []}}
      end
    end)
  end

  @spec validate_tuple_elements([term()], [type_definition()], [atom()]) ::
    {:ok, tuple()} | {:error, [Error.t()]}
  defp validate_tuple_elements(values, types, base_path) do
    results =
      values
      |> Enum.zip(types)
      |> Enum.with_index()
      |> Enum.map(fn {{value, type}, index} ->
        element_path = base_path ++ [index]
        validate(type, value, element_path)
      end)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {oks, []} ->
        validated_values = Enum.map(oks, fn {:ok, val} -> val end)
        {:ok, List.to_tuple(validated_values)}
      {_, errors} ->
        all_errors = Enum.flat_map(errors, fn {:error, errs} -> errs end)
        {:error, all_errors}
    end
  end

  @spec apply_constraints(term(), keyword(), [atom()]) :: {:ok, term()} | {:error, [Error.t()]}
  defp apply_constraints(value, constraints, path) do
    Enum.reduce_while(constraints, {:ok, value}, fn constraint, {:ok, val} ->
      case check_constraint(constraint, val, path) do
        :ok -> {:cont, {:ok, val}}
        {:error, error} -> {:halt, {:error, [error]}}
      end
    end)
  end

  @spec check_constraint({atom(), term()}, term(), [atom()]) :: :ok | {:error, Error.t()}
  defp check_constraint({:min_length, min}, value, path) when is_binary(value) do
    if String.length(value) >= min do
      :ok
    else
      {:error, Error.new(path, :min_length, "must be at least #{min} characters")}
    end
  end

  defp check_constraint({:max_length, max}, value, path) when is_binary(value) do
    if String.length(value) <= max do
      :ok
    else
      {:error, Error.new(path, :max_length, "must be at most #{max} characters")}
    end
  end

  defp check_constraint({:min_items, min}, value, path) when is_list(value) do
    if length(value) >= min do
      :ok
    else
      {:error, Error.new(path, :min_items, "must have at least #{min} items")}
    end
  end

  defp check_constraint({:max_items, max}, value, path) when is_list(value) do
    if length(value) <= max do
      :ok
    else
      {:error, Error.new(path, :max_items, "must have at most #{max} items")}
    end
  end

  defp check_constraint({:gt, min}, value, path) when is_number(value) do
    if value > min do
      :ok
    else
      {:error, Error.new(path, :gt, "must be greater than #{min}")}
    end
  end

  defp check_constraint({:lt, max}, value, path) when is_number(value) do
    if value < max do
      :ok
    else
      {:error, Error.new(path, :lt, "must be less than #{max}")}
    end
  end

  defp check_constraint({:gteq, min}, value, path) when is_number(value) do
    if value >= min do
      :ok
    else
      {:error, Error.new(path, :gteq, "must be greater than or equal to #{min}")}
    end
  end

  defp check_constraint({:lteq, max}, value, path) when is_number(value) do
    if value <= max do
      :ok
    else
      {:error, Error.new(path, :lteq, "must be less than or equal to #{max}")}
    end
  end

  defp check_constraint({:format, regex}, value, path) when is_binary(value) and is_struct(regex, Regex) do
    if Regex.match?(regex, value) do
      :ok
    else
      {:error, Error.new(path, :format, "does not match required format")}
    end
  end

  defp check_constraint({:choices, allowed}, value, path) do
    if value in allowed do
      :ok
    else
      {:error, Error.new(path, :choices, "must be one of #{inspect(allowed)}")}
    end
  end

  defp check_constraint(_constraint, _value, _path) do
    # Unknown constraints pass silently
    :ok
  end

  @spec coerce_base_type(atom(), term()) :: {:ok, term()} | {:error, String.t()}
  defp coerce_base_type(:string, value) when is_atom(value), do: {:ok, Atom.to_string(value)}
  defp coerce_base_type(:string, value) when is_integer(value), do: {:ok, Integer.to_string(value)}
  defp coerce_base_type(:string, value) when is_float(value), do: {:ok, Float.to_string(value)}

  defp coerce_base_type(:integer, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, "invalid integer format"}
    end
  end

  defp coerce_base_type(:float, value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, "invalid float format"}
    end
  end

  defp coerce_base_type(:float, value) when is_integer(value), do: {:ok, value * 1.0}

  defp coerce_base_type(:atom, value) when is_binary(value) do
    try do
      {:ok, String.to_existing_atom(value)}
    rescue
      ArgumentError -> {:error, "atom does not exist"}
    end
  end

  defp coerce_base_type(_type, _value), do: {:error, "coercion not supported"}

  @spec base_type_to_json_schema(atom()) :: map()
  defp base_type_to_json_schema(:string), do: %{"type" => "string"}
  defp base_type_to_json_schema(:integer), do: %{"type" => "integer"}
  defp base_type_to_json_schema(:float), do: %{"type" => "number"}
  defp base_type_to_json_schema(:boolean), do: %{"type" => "boolean"}
  defp base_type_to_json_schema(:atom), do: %{"type" => "string", "description" => "Atom value"}
  defp base_type_to_json_schema(:any), do: %{}

  @spec apply_json_schema_constraints(map(), keyword()) :: map()
  defp apply_json_schema_constraints(schema, constraints) do
    Enum.reduce(constraints, schema, fn
      {:min_length, value}, acc -> Map.put(acc, "minLength", value)
      {:max_length, value}, acc -> Map.put(acc, "maxLength", value)
      {:min_items, value}, acc -> Map.put(acc, "minItems", value)
      {:max_items, value}, acc -> Map.put(acc, "maxItems", value)
      {:gt, value}, acc -> Map.put(acc, "exclusiveMinimum", value)
      {:lt, value}, acc -> Map.put(acc, "exclusiveMaximum", value)
      {:gteq, value}, acc -> Map.put(acc, "minimum", value)
      {:lteq, value}, acc -> Map.put(acc, "maximum", value)
      {:format, %Regex{} = regex}, acc -> Map.put(acc, "pattern", Regex.source(regex))
      {:choices, values}, acc -> Map.put(acc, "enum", values)
      _, acc -> acc
    end)
  end
end
