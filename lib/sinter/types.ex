defmodule Sinter.Types do
  @moduledoc """
  Core type system for Sinter validation.

  This module defines the type specifications supported by Sinter and provides
  the fundamental validation and coercion functions that power the unified
  validation engine.

  ## Supported Types

  * **Primitive Types**: `:string`, `:integer`, `:float`, `:boolean`, `:atom`, `:any`, `:map`
  * **Array Types**: `{:array, inner_type}`
  * **Union Types**: `{:union, [type1, type2, ...]}`
  * **Tuple Types**: `{:tuple, [type1, type2, ...]}`
  * **Map Types**: `{:map, key_type, value_type}` or `:map`

  ## Type Validation

  The `validate/3` function is the core validation engine:

      iex> Sinter.Types.validate(:string, "hello", [])
      {:ok, "hello"}

      iex> Sinter.Types.validate(:integer, "not a number", [])
      {:error, [%Sinter.Error{code: :type, ...}]}

  ## Type Coercion

  The `coerce/2` function provides safe type conversion:

      iex> Sinter.Types.coerce(:integer, "42")
      {:ok, 42}

      iex> Sinter.Types.coerce(:integer, "not a number")
      {:error, [%Sinter.Error{code: :coercion, ...}]}
  """

  alias Sinter.Error

  @type primitive_type :: :string | :integer | :float | :boolean | :atom | :any | :map

  @type composite_type ::
          {:array, type_spec()}
          | {:array, type_spec(), keyword()}
          | {:union, [type_spec()]}
          | {:tuple, [type_spec()]}
          | {:map, type_spec(), type_spec()}

  @type type_spec :: primitive_type() | composite_type()

  @type constraint ::
          {:min_length, pos_integer()}
          | {:max_length, pos_integer()}
          | {:min_items, non_neg_integer()}
          | {:max_items, pos_integer()}
          | {:gt, number()}
          | {:gteq, number()}
          | {:lt, number()}
          | {:lteq, number()}
          | {:format, Regex.t()}
          | {:choices, [term()]}

  @doc """
  Validates a value against a type specification.

  This is the core validation function that all other validation ultimately uses.
  It checks if a value matches the expected type and satisfies any constraints.

  ## Parameters

    * `type_spec` - The type specification to validate against
    * `value` - The value to validate
    * `path` - The path for error reporting (default: [])

  ## Returns

    * `{:ok, validated_value}` on success
    * `{:error, [%Sinter.Error{}]}` on validation failure

  ## Examples

      iex> Sinter.Types.validate(:string, "hello", [])
      {:ok, "hello"}

      iex> Sinter.Types.validate(:integer, 42, [])
      {:ok, 42}

      iex> Sinter.Types.validate({:array, :string}, ["a", "b"], [])
      {:ok, ["a", "b"]}

      iex> {:error, [error]} = Sinter.Types.validate(:string, 123, [])
      iex> error.code
      :type
  """
  @spec validate(type_spec(), term(), [atom() | String.t() | integer()]) ::
          {:ok, term()} | {:error, [Error.t()]}
  def validate(type_spec, value, path \\ [])

  # Primitive type validation
  def validate(:string, value, _path) when is_binary(value), do: {:ok, value}
  def validate(:integer, value, _path) when is_integer(value), do: {:ok, value}
  def validate(:float, value, _path) when is_float(value), do: {:ok, value}
  def validate(:boolean, value, _path) when is_boolean(value), do: {:ok, value}
  def validate(:atom, value, _path) when is_atom(value), do: {:ok, value}
  def validate(:any, value, _path), do: {:ok, value}
  def validate(:map, value, _path) when is_map(value), do: {:ok, value}

  # Array validation with constraints
  def validate({:array, inner_type, constraints}, value, path) when is_list(value) do
    # First validate the array structure and elements
    case validate({:array, inner_type}, value, path) do
      {:ok, validated_items} ->
        # Then validate array-level constraints
        case validate_array_constraints(constraints, validated_items, path) do
          :ok -> {:ok, validated_items}
          {:error, errors} -> {:error, errors}
        end

      {:error, errors} ->
        {:error, errors}
    end
  end

  def validate({:array, _inner_type, _constraints}, value, path) do
    error = Error.new(path, :type, "expected array, got #{type_name(value)}")
    {:error, [error]}
  end

  # Array validation
  def validate({:array, inner_type}, value, path) when is_list(value) do
    results =
      value
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        item_path = path ++ [index]
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

  def validate({:array, _}, value, path) do
    error = Error.new(path, :type, "expected array, got #{type_name(value)}")
    {:error, [error]}
  end

  # Union validation - try each type until one succeeds
  def validate({:union, types}, value, path) do
    case try_union_types(types, value, path) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, _} ->
        error = Error.new(path, :type, "value does not match any type in union")
        {:error, [error]}
    end
  end

  # Tuple validation
  def validate({:tuple, types}, value, path) when is_tuple(value) do
    if tuple_size(value) == length(types) do
      validate_tuple_elements(Tuple.to_list(value), types, path)
    else
      error =
        Error.new(
          path,
          :tuple_size,
          "expected tuple of size #{length(types)}, got size #{tuple_size(value)}"
        )

      {:error, [error]}
    end
  end

  def validate({:tuple, _}, value, path) do
    error = Error.new(path, :type, "expected tuple, got #{type_name(value)}")
    {:error, [error]}
  end

  # Map with key/value types
  def validate({:map, key_type, value_type}, value, path) when is_map(value) do
    # Validate all keys and values
    key_errors =
      value
      |> Map.keys()
      |> Enum.with_index()
      |> Enum.flat_map(fn {key, index} ->
        case validate(key_type, key, path ++ ["key_#{index}"]) do
          {:ok, _} -> []
          {:error, errors} -> errors
        end
      end)

    value_errors =
      value
      |> Map.values()
      |> Enum.with_index()
      |> Enum.flat_map(fn {val, index} ->
        case validate(value_type, val, path ++ ["value_#{index}"]) do
          {:ok, _} -> []
          {:error, errors} -> errors
        end
      end)

    all_errors = key_errors ++ value_errors

    case all_errors do
      [] -> {:ok, value}
      errors -> {:error, errors}
    end
  end

  def validate({:map, _, _}, value, path) do
    error = Error.new(path, :type, "expected map, got #{type_name(value)}")
    {:error, [error]}
  end

  # Type mismatch for primitive types
  def validate(expected_type, value, path) when is_atom(expected_type) do
    error = Error.new(path, :type, "expected #{expected_type}, got #{type_name(value)}")
    {:error, [error]}
  end

  @doc """
  Attempts to coerce a value to the specified type.

  Coercion is safe and predictable - it never raises exceptions and only
  performs well-defined conversions.

  ## Parameters

    * `type_spec` - The target type specification
    * `value` - The value to coerce

  ## Returns

    * `{:ok, coerced_value}` on successful coercion
    * `{:error, [%Sinter.Error{}]}` on coercion failure

  ## Examples

      iex> Sinter.Types.coerce(:string, :hello)
      {:ok, "hello"}

      iex> Sinter.Types.coerce(:integer, "42")
      {:ok, 42}

      iex> {:error, [error]} = Sinter.Types.coerce(:integer, "not a number")
      iex> error.code
      :coercion
  """
  @spec coerce(type_spec(), term()) :: {:ok, term()} | {:error, [Error.t()]}
  def coerce(type_spec, value)

  # String coercion
  def coerce(:string, value) when is_atom(value), do: {:ok, Atom.to_string(value)}
  def coerce(:string, value) when is_integer(value), do: {:ok, Integer.to_string(value)}
  def coerce(:string, value) when is_float(value), do: {:ok, Float.to_string(value)}
  def coerce(:string, value) when is_boolean(value), do: {:ok, to_string(value)}
  def coerce(:string, value) when is_binary(value), do: {:ok, value}

  # Integer coercion
  def coerce(:integer, value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> {:ok, int}
      _ -> {:error, [Error.new([], :coercion, "cannot coerce '#{value}' to integer")]}
    end
  end

  def coerce(:integer, value) when is_integer(value), do: {:ok, value}

  def coerce(:integer, value) do
    {:error, [Error.new([], :coercion, "cannot coerce '#{inspect(value)}' to integer")]}
  end

  # Float coercion
  def coerce(:float, value) when is_binary(value) do
    case Float.parse(value) do
      {float, ""} -> {:ok, float}
      _ -> {:error, [Error.new([], :coercion, "cannot coerce '#{value}' to float")]}
    end
  end

  def coerce(:float, value) when is_integer(value), do: {:ok, value * 1.0}
  def coerce(:float, value) when is_float(value), do: {:ok, value}

  def coerce(:float, value) do
    {:error, [Error.new([], :coercion, "cannot coerce '#{inspect(value)}' to float")]}
  end

  # Boolean coercion
  def coerce(:boolean, "true"), do: {:ok, true}
  def coerce(:boolean, "false"), do: {:ok, false}
  def coerce(:boolean, value) when is_boolean(value), do: {:ok, value}

  def coerce(:boolean, value) do
    {:error, [Error.new([], :coercion, "cannot coerce '#{inspect(value)}' to boolean")]}
  end

  # Atom coercion (only existing atoms for safety)
  def coerce(:atom, value) when is_binary(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, [Error.new([], :coercion, "atom '#{value}' does not exist")]}
  end

  def coerce(:atom, value) when is_atom(value), do: {:ok, value}

  def coerce(:atom, value) do
    {:error, [Error.new([], :coercion, "cannot coerce '#{inspect(value)}' to atom")]}
  end

  # Array coercion with constraints
  def coerce({:array, inner_type, _constraints}, value) when is_list(value) do
    # For coercion, we ignore constraints and delegate to basic array coercion
    coerce({:array, inner_type}, value)
  end

  # Array coercion
  def coerce({:array, inner_type}, value) when is_list(value) do
    results =
      value
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        case coerce(inner_type, item) do
          {:ok, coerced} ->
            {:ok, coerced}

          {:error, errors} ->
            # Update error paths to include array index
            updated_errors =
              Enum.map(errors, fn error ->
                %{error | path: [index]}
              end)

            {:error, updated_errors}
        end
      end)

    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {oks, []} ->
        coerced_values = Enum.map(oks, fn {:ok, val} -> val end)
        {:ok, coerced_values}

      {_, errors} ->
        all_errors = Enum.flat_map(errors, fn {:error, errs} -> errs end)
        {:error, all_errors}
    end
  end

  # Union coercion - try each type until one works
  def coerce({:union, types}, value) do
    Enum.reduce_while(
      types,
      {:error, [Error.new([], :coercion, "no type in union could coerce value")]},
      fn type, _acc ->
        case coerce(type, value) do
          {:ok, coerced} -> {:halt, {:ok, coerced}}
          {:error, _} -> {:cont, {:error, [Error.new([], :coercion, "coercion failed")]}}
        end
      end
    )
  end

  # No coercion needed/available
  def coerce(_type, value), do: {:ok, value}

  @doc """
  Converts a type specification to JSON Schema format.

  This function maps Sinter types to their JSON Schema equivalents,
  enabling JSON Schema generation for LLM providers.

  ## Examples

      iex> Sinter.Types.to_json_schema(:string)
      %{"type" => "string"}

      iex> Sinter.Types.to_json_schema({:array, :integer})
      %{"type" => "array", "items" => %{"type" => "integer"}}
  """
  @spec to_json_schema(type_spec()) :: map()
  def to_json_schema(type_spec)

  def to_json_schema(:string), do: %{"type" => "string"}
  def to_json_schema(:integer), do: %{"type" => "integer"}
  def to_json_schema(:float), do: %{"type" => "number"}
  def to_json_schema(:boolean), do: %{"type" => "boolean"}
  def to_json_schema(:atom), do: %{"type" => "string", "description" => "Atom value"}
  def to_json_schema(:any), do: %{}
  def to_json_schema(:map), do: %{"type" => "object"}

  def to_json_schema({:array, inner_type, constraints}) do
    base_schema = %{
      "type" => "array",
      "items" => to_json_schema(inner_type)
    }

    # Add array constraints
    Enum.reduce(constraints, base_schema, fn
      {:min_items, min}, acc -> Map.put(acc, "minItems", min)
      {:max_items, max}, acc -> Map.put(acc, "maxItems", max)
      _other_constraint, acc -> acc
    end)
  end

  def to_json_schema({:array, inner_type}) do
    %{
      "type" => "array",
      "items" => to_json_schema(inner_type)
    }
  end

  def to_json_schema({:union, types}) do
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

  def to_json_schema({:map, key_type, value_type}) do
    base = %{"type" => "object"}

    case {key_type, value_type} do
      {:string, value_type} ->
        Map.put(base, "additionalProperties", to_json_schema(value_type))

      _ ->
        # For non-string keys, we can't represent this directly in JSON Schema
        base
    end
  end

  # Private helper functions

  @spec validate_array_constraints(keyword(), [term()], [atom()]) :: :ok | {:error, [Error.t()]}
  defp validate_array_constraints(constraints, value, path) do
    errors =
      Enum.flat_map(constraints, fn
        {:min_items, min} ->
          if length(value) >= min do
            []
          else
            [Error.new(path, :min_items, "must contain at least #{min} items")]
          end

        {:max_items, max} ->
          if length(value) <= max do
            []
          else
            [Error.new(path, :max_items, "must contain at most #{max} items")]
          end

        _other_constraint ->
          # Skip non-array constraints
          []
      end)

    case errors do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @spec try_union_types([type_spec()], term(), [atom()]) :: {:ok, term()} | {:error, []}
  defp try_union_types(types, value, path) do
    Enum.reduce_while(types, {:error, []}, fn type, _acc ->
      case validate(type, value, path) do
        {:ok, validated} -> {:halt, {:ok, validated}}
        {:error, _} -> {:cont, {:error, []}}
      end
    end)
  end

  @spec validate_tuple_elements([term()], [type_spec()], [atom()]) ::
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

  @spec type_name(term()) :: String.t()
  defp type_name(value) when is_binary(value), do: "string"
  defp type_name(value) when is_integer(value), do: "integer"
  defp type_name(value) when is_float(value), do: "float"
  defp type_name(value) when is_boolean(value), do: "boolean"
  defp type_name(value) when is_atom(value), do: "atom"
  defp type_name(value) when is_list(value), do: "list"
  defp type_name(value) when is_tuple(value), do: "tuple"
  defp type_name(value) when is_map(value), do: "map"
  defp type_name(_), do: "unknown"
end
