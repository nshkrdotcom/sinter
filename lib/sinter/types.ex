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

  alias Sinter.{Error, Schema, Validator}

  @type primitive_type ::
          :string
          | :integer
          | :float
          | :boolean
          | :atom
          | :any
          | :map
          | :date
          | :datetime
          | :uuid
          | :null

  @type composite_type ::
          {:array, type_spec()}
          | {:array, type_spec(), keyword()}
          | {:union, [type_spec()]}
          | {:tuple, [type_spec()]}
          | {:map, type_spec(), type_spec()}
          | {:nullable, type_spec()}
          | {:object, Schema.t() | [Schema.field_spec()]}
          | {:literal, term()}
          | {:discriminated_union, keyword()}

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
  def validate(:null, nil, _path), do: {:ok, nil}

  # Literal type validation - exact value match
  def validate({:literal, expected}, value, _path) when value === expected do
    {:ok, value}
  end

  def validate({:literal, expected}, value, path) do
    error =
      Error.new(
        path,
        :literal_mismatch,
        "expected literal #{inspect(expected)}, got #{inspect(value)}"
      )

    {:error, [error]}
  end

  def validate(:date, value, path) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, _date} -> {:ok, value}
      _ -> {:error, [Error.new(path, :format, "expected ISO8601 date string")]}
    end
  end

  def validate(:date, value, path) do
    error = Error.new(path, :type, "expected date string, got #{type_name(value)}")
    {:error, [error]}
  end

  def validate(:datetime, value, path) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, _datetime, _offset} ->
        {:ok, value}

      _ ->
        case NaiveDateTime.from_iso8601(value) do
          {:ok, _datetime} -> {:ok, value}
          _ -> {:error, [Error.new(path, :format, "expected ISO8601 datetime string")]}
        end
    end
  end

  def validate(:datetime, value, path) do
    error = Error.new(path, :type, "expected datetime string, got #{type_name(value)}")
    {:error, [error]}
  end

  def validate(:uuid, value, path) when is_binary(value) do
    if String.match?(
         value,
         ~r/^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/
       ) do
      {:ok, value}
    else
      {:error, [Error.new(path, :format, "expected UUID string")]}
    end
  end

  def validate(:uuid, value, path) do
    error = Error.new(path, :type, "expected UUID string, got #{type_name(value)}")
    {:error, [error]}
  end

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

  # Nullable types
  def validate({:nullable, _inner_type}, nil, _path), do: {:ok, nil}

  def validate({:nullable, inner_type}, value, path) do
    validate(inner_type, value, path)
  end

  # Object schema type
  def validate({:object, schema_or_fields}, value, path) when is_map(value) do
    schema = normalize_object_schema(schema_or_fields)

    case Validator.validate(schema, value, path: path) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, errors}
    end
  end

  def validate({:object, _schema}, value, path) do
    error = Error.new(path, :type, "expected object, got #{type_name(value)}")
    {:error, [error]}
  end

  # Discriminated union validation - uses discriminator field to select variant
  def validate({:discriminated_union, opts}, value, path) when is_map(value) do
    discriminator = Keyword.fetch!(opts, :discriminator)
    variants = Keyword.fetch!(opts, :variants)

    # Get discriminator value (support both string and atom keys)
    disc_value = get_discriminator_value(value, discriminator)

    case disc_value do
      nil ->
        error =
          Error.new(
            path ++ [to_string(discriminator)],
            :missing_discriminator,
            "missing discriminator field '#{discriminator}'",
            %{discriminator: discriminator}
          )

        {:error, [error]}

      disc_val ->
        # Look up variant schema - try exact match first, then string conversion
        variant_schema = find_variant_schema(variants, disc_val)

        case variant_schema do
          nil ->
            valid_values = Map.keys(variants)

            error =
              Error.new(
                path ++ [to_string(discriminator)],
                :unknown_discriminator,
                "unknown discriminator value '#{disc_val}', expected one of: #{inspect(valid_values)}",
                %{value: disc_val, valid_values: valid_values}
              )

            {:error, [error]}

          schema ->
            # Validate against the variant schema
            Validator.validate(schema, value, path: path)
        end
    end
  end

  def validate({:discriminated_union, _opts}, value, path) do
    error = Error.new(path, :type, "expected map for discriminated union, got #{type_name(value)}")
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

  # Null coercion
  def coerce(:null, nil), do: {:ok, nil}

  def coerce(:null, value) do
    {:error, [Error.new([], :coercion, "cannot coerce '#{inspect(value)}' to null")]}
  end

  # Nullable coercion
  def coerce({:nullable, _inner_type}, nil), do: {:ok, nil}

  def coerce({:nullable, inner_type}, value) do
    coerce(inner_type, value)
  end

  # Date/time coercion
  def coerce(:date, %Date{} = value), do: {:ok, Date.to_iso8601(value)}
  def coerce(:date, value) when is_binary(value), do: {:ok, value}

  def coerce(:date, value) do
    {:error, [Error.new([], :coercion, "cannot coerce '#{inspect(value)}' to date")]}
  end

  def coerce(:datetime, %DateTime{} = value), do: {:ok, DateTime.to_iso8601(value)}
  def coerce(:datetime, %NaiveDateTime{} = value), do: {:ok, NaiveDateTime.to_iso8601(value)}
  def coerce(:datetime, value) when is_binary(value), do: {:ok, value}

  def coerce(:datetime, value) do
    {:error, [Error.new([], :coercion, "cannot coerce '#{inspect(value)}' to datetime")]}
  end

  def coerce(:uuid, value) when is_binary(value), do: {:ok, value}

  def coerce(:uuid, value) do
    {:error, [Error.new([], :coercion, "cannot coerce '#{inspect(value)}' to uuid")]}
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

  # Object coercion
  def coerce({:object, schema_or_fields}, value) when is_map(value) do
    schema = normalize_object_schema(schema_or_fields)

    case Validator.validate(schema, value, coerce: true) do
      {:ok, validated} -> {:ok, validated}
      {:error, errors} -> {:error, errors}
    end
  end

  def coerce({:object, _schema}, value) do
    {:error, [Error.new([], :coercion, "cannot coerce '#{inspect(value)}' to object")]}
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
  def to_json_schema(:null), do: %{"type" => "null"}
  def to_json_schema(:date), do: %{"type" => "string", "format" => "date"}
  def to_json_schema(:datetime), do: %{"type" => "string", "format" => "date-time"}
  def to_json_schema(:uuid), do: %{"type" => "string", "format" => "uuid"}
  def to_json_schema(:atom), do: %{"type" => "string", "description" => "Atom value"}
  def to_json_schema(:any), do: %{}
  def to_json_schema(:map), do: %{"type" => "object", "additionalProperties" => true}

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
      {:string, :any} ->
        # For :any values, use true instead of empty map
        Map.put(base, "additionalProperties", true)

      {:string, value_type} ->
        Map.put(base, "additionalProperties", to_json_schema(value_type))

      _ ->
        # For non-string keys, we can't represent this directly in JSON Schema
        Map.put(base, "additionalProperties", true)
    end
  end

  def to_json_schema({:nullable, inner_type}) do
    %{
      "anyOf" => [
        to_json_schema(inner_type),
        %{"type" => "null"}
      ]
    }
  end

  def to_json_schema({:object, _schema}) do
    %{"type" => "object"}
  end

  def to_json_schema({:literal, value}) do
    %{"const" => value}
  end

  def to_json_schema({:discriminated_union, opts}) do
    discriminator = Keyword.fetch!(opts, :discriminator)
    variants = Keyword.fetch!(opts, :variants)

    variant_schemas =
      Enum.map(variants, fn {_key, schema} ->
        generate_variant_json_schema(schema)
      end)

    mapping =
      Enum.map(variants, fn {key, _schema} ->
        {to_string(key), "#/definitions/#{key}"}
      end)
      |> Map.new()

    %{
      "oneOf" => variant_schemas,
      "discriminator" => %{
        "propertyName" => to_string(discriminator),
        "mapping" => mapping
      }
    }
  end

  # Private helper functions

  @spec validate_array_constraints(keyword(), [term()], [atom() | String.t() | integer()]) ::
          :ok | {:error, [Error.t()]}
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

  @spec try_union_types([type_spec()], term(), [atom() | String.t() | integer()]) ::
          {:ok, term()} | {:error, []}
  defp try_union_types(types, value, path) do
    Enum.reduce_while(types, {:error, []}, fn type, _acc ->
      case validate(type, value, path) do
        {:ok, validated} -> {:halt, {:ok, validated}}
        {:error, _} -> {:cont, {:error, []}}
      end
    end)
  end

  @spec validate_tuple_elements([term()], [type_spec()], [atom() | String.t() | integer()]) ::
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
  defp type_name(nil), do: "null"
  defp type_name(value) when is_binary(value), do: "string"
  defp type_name(value) when is_integer(value), do: "integer"
  defp type_name(value) when is_float(value), do: "float"
  defp type_name(value) when is_boolean(value), do: "boolean"
  defp type_name(value) when is_atom(value), do: "atom"
  defp type_name(value) when is_list(value), do: "list"
  defp type_name(value) when is_tuple(value), do: "tuple"
  defp type_name(value) when is_map(value), do: "map"
  defp type_name(_), do: "unknown"

  @spec normalize_object_schema(Schema.t() | [Schema.field_spec()]) :: Schema.t()
  defp normalize_object_schema(%Schema{} = schema), do: schema

  defp normalize_object_schema(field_specs) when is_list(field_specs),
    do: Schema.define(field_specs)

  # Helper to get discriminator value from map with support for both string and atom keys
  @spec get_discriminator_value(map(), atom() | String.t()) :: term() | nil
  defp get_discriminator_value(map, discriminator) when is_binary(discriminator) do
    case Map.get(map, discriminator) do
      nil ->
        # Try atom key
        try do
          Map.get(map, String.to_existing_atom(discriminator))
        rescue
          ArgumentError -> nil
        end

      value ->
        value
    end
  end

  defp get_discriminator_value(map, discriminator) when is_atom(discriminator) do
    case Map.get(map, discriminator) do
      nil -> Map.get(map, to_string(discriminator))
      value -> value
    end
  end

  # Helper to find variant schema by discriminator value
  @spec find_variant_schema(map(), term()) :: Schema.t() | nil
  defp find_variant_schema(variants, disc_val) do
    # Try exact match first
    case Map.get(variants, disc_val) do
      nil -> find_variant_by_conversion(variants, disc_val)
      schema -> schema
    end
  end

  defp find_variant_by_conversion(variants, disc_val) when is_atom(disc_val) do
    Map.get(variants, to_string(disc_val))
  end

  defp find_variant_by_conversion(variants, disc_val) when is_binary(disc_val) do
    # Try to find an atom key that matches the string
    Enum.find_value(variants, fn
      {key, schema} when is_atom(key) ->
        if to_string(key) == disc_val, do: schema

      _ ->
        nil
    end)
  end

  defp find_variant_by_conversion(_variants, _disc_val), do: nil

  # Helper to generate JSON Schema for a variant (simplified version)
  @spec generate_variant_json_schema(Schema.t()) :: map()
  defp generate_variant_json_schema(%Schema{} = schema) do
    properties =
      Enum.map(schema.fields, fn {name, field_def} ->
        {to_string(name), to_json_schema(field_def.type)}
      end)
      |> Map.new()

    required =
      schema.fields
      |> Enum.filter(fn {_name, field_def} -> field_def.required end)
      |> Enum.map(fn {name, _} -> to_string(name) end)

    base = %{
      "type" => "object",
      "properties" => properties
    }

    if required == [] do
      base
    else
      Map.put(base, "required", required)
    end
  end
end
