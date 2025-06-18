defmodule Sinter.JsonSchema do
  @moduledoc """
  Unified JSON Schema generation for Sinter.

  This module provides the single JSON Schema generation engine that handles
  all JSON Schema creation in Sinter. It converts Sinter schemas into standard
  JSON Schema format with optional provider-specific optimizations.

  ## Features

  - Standard JSON Schema generation
  - Provider-specific optimizations (OpenAI, Anthropic, etc.)
  - Reference resolution and flattening
  - Constraint mapping
  - Metadata preservation
  """

  alias Sinter.{Schema, Types}

  @type generation_opts :: [
    optimize_for_provider: :openai | :anthropic | :generic,
    flatten: boolean(),
    include_descriptions: boolean(),
    strict: boolean()
  ]

  @doc """
  Generates a JSON Schema from a Sinter schema.

  This is the core JSON Schema generation function that converts Sinter schemas
  into standard JSON Schema format.

  ## Parameters

    * `schema` - A Sinter schema created by `Sinter.Schema.define/2`
    * `opts` - Generation options

  ## Options

    * `:optimize_for_provider` - Apply provider-specific optimizations
      - `:openai` - Optimize for OpenAI function calling
      - `:anthropic` - Optimize for Anthropic tool use
      - `:generic` - Standard JSON Schema (default)
    * `:flatten` - Resolve all references inline (default: false)
    * `:include_descriptions` - Include field descriptions (default: true)
    * `:strict` - Override schema's strict setting for additionalProperties

  ## Returns

    * JSON Schema map

  ## Examples

      iex> schema = Sinter.Schema.define([
      ...>   {:name, :string, [required: true, min_length: 2]},
      ...>   {:age, :integer, [optional: true, gt: 0]}
      ...> ], title: "User Schema")
      iex> Sinter.JsonSchema.generate(schema)
      %{
        "type" => "object",
        "title" => "User Schema",
        "properties" => %{
          "name" => %{"type" => "string", "minLength" => 2},
          "age" => %{"type" => "integer", "exclusiveMinimum" => 0}
        },
        "required" => ["name"],
        "additionalProperties" => false
      }

      # Provider-specific optimization
      iex> Sinter.JsonSchema.generate(schema, optimize_for_provider: :openai)
      %{
        "type" => "object",
        "properties" => %{...},
        "additionalProperties" => false,
        "required" => ["name"]
      }
  """
  @spec generate(Schema.t(), generation_opts()) :: map()
  def generate(%Schema{} = schema, opts \\ []) do
    include_descriptions = Keyword.get(opts, :include_descriptions, true)
    provider = Keyword.get(opts, :optimize_for_provider, :generic)
    flatten = Keyword.get(opts, :flatten, false)

    # Build base JSON Schema
    base_schema = build_base_schema(schema, include_descriptions, opts)

    # Apply provider optimizations
    optimized_schema = apply_provider_optimizations(base_schema, provider)

    # Flatten if requested
    final_schema =
      if flatten do
        flatten_schema(optimized_schema)
      else
        optimized_schema
      end

    final_schema
  end

  @doc """
  Generates a JSON Schema optimized for a specific LLM provider.

  This is a convenience function that applies provider-specific optimizations
  and returns a schema ready for use with that provider's API.

  ## Examples

      iex> openai_schema = Sinter.JsonSchema.for_provider(schema, :openai)
      iex> anthropic_schema = Sinter.JsonSchema.for_provider(schema, :anthropic)
  """
  @spec for_provider(Schema.t(), :openai | :anthropic | :generic, keyword()) :: map()
  def for_provider(schema, provider, additional_opts \\ []) do
    opts = Keyword.put(additional_opts, :optimize_for_provider, provider)
    generate(schema, opts)
  end

  @doc """
  Validates a JSON Schema for correctness and compatibility.

  ## Parameters

    * `json_schema` - The JSON Schema to validate
    * `opts` - Validation options

  ## Returns

    * `:ok` if schema is valid
    * `{:error, issues}` if problems are found
  """
  @spec validate_schema(map(), keyword()) :: :ok | {:error, [String.t()]}
  def validate_schema(json_schema, opts \\ []) do
    issues = []

    # Check required structure
    issues = check_basic_structure(json_schema, issues)

    # Check type consistency
    issues = check_type_consistency(json_schema, issues)

    # Check constraint validity
    issues = check_constraint_validity(json_schema, issues)

    case issues do
      [] -> :ok
      problems -> {:error, Enum.reverse(problems)}
    end
  end

  # Private helper functions

  @spec build_base_schema(Schema.t(), boolean(), keyword()) :: map()
  defp build_base_schema(schema, include_descriptions, opts) do
    config = Schema.config(schema)
    strict = Keyword.get(opts, :strict, config.strict)

    base = %{
      "type" => "object",
      "properties" => build_properties(schema, include_descriptions),
      "required" => build_required_list(schema),
      "additionalProperties" => not strict
    }

    # Add optional top-level metadata
    base
    |> maybe_add_title(config.title)
    |> maybe_add_description(config.description)
    |> add_sinter_metadata(schema)
  end

  @spec build_properties(Schema.t(), boolean()) :: map()
  defp build_properties(schema, include_descriptions) do
    schema.fields
    |> Enum.map(fn {field_name, field_def} ->
      property_schema = build_property_schema(field_def, include_descriptions)
      {to_string(field_name), property_schema}
    end)
    |> Map.new()
  end

  @spec build_property_schema(Schema.field_definition(), boolean()) :: map()
  defp build_property_schema(field_def, include_descriptions) do
    # Convert type to JSON Schema
    type_schema = Types.to_json_schema(field_def.type)

    # Add field metadata
    type_schema
    |> maybe_add_description(field_def.description, include_descriptions)
    |> maybe_add_example(field_def.example)
    |> maybe_add_default(field_def.default)
  end

  @spec build_required_list(Schema.t()) :: [String.t()]
  defp build_required_list(schema) do
    schema
    |> Schema.required_fields()
    |> Enum.map(&to_string/1)
  end

  @spec apply_provider_optimizations(map(), atom()) :: map()
  defp apply_provider_optimizations(schema, :openai) do
    schema
    |> Map.put("additionalProperties", false)  # OpenAI requires this
    |> ensure_required_array()
    |> optimize_for_function_calling()
  end

  defp apply_provider_optimizations(schema, :anthropic) do
    schema
    |> Map.put("additionalProperties", false)  # Anthropic prefers this
    |> ensure_required_array()
    |> optimize_for_tool_use()
  end

  defp apply_provider_optimizations(schema, :generic), do: schema
  defp apply_provider_optimizations(schema, _unknown), do: schema

  @spec ensure_required_array(map()) :: map()
  defp ensure_required_array(schema) do
    case Map.get(schema, "required") do
      nil -> Map.put(schema, "required", [])
      [] -> schema
      _list -> schema
    end
  end

  @spec optimize_for_function_calling(map()) :: map()
  defp optimize_for_function_calling(schema) do
    # OpenAI function calling optimizations
    schema
    |> remove_unsupported_formats([:date, :time, :email])
    |> simplify_complex_unions()
  end

  @spec optimize_for_tool_use(map()) :: map()
  defp optimize_for_tool_use(schema) do
    # Anthropic tool use optimizations
    schema
    |> remove_unsupported_formats([:uri, :uuid])
    |> ensure_object_properties()
  end

  @spec remove_unsupported_formats(map(), [atom()]) :: map()
  defp remove_unsupported_formats(schema, unsupported_formats) do
    case Map.get(schema, "properties") do
      nil -> schema
      properties ->
        cleaned_properties =
          properties
          |> Enum.map(fn {key, prop_schema} ->
            cleaned_prop = remove_format_if_unsupported(prop_schema, unsupported_formats)
            {key, cleaned_prop}
          end)
          |> Map.new()

        Map.put(schema, "properties", cleaned_properties)
    end
  end

  @spec remove_format_if_unsupported(map(), [atom()]) :: map()
  defp remove_format_if_unsupported(property_schema, unsupported_formats) do
    case Map.get(property_schema, "format") do
      format when is_binary(format) ->
        if String.to_atom(format) in unsupported_formats do
          Map.delete(property_schema, "format")
        else
          property_schema
        end
      _ -> property_schema
    end
  end

  @spec simplify_complex_unions(map()) :: map()
  defp simplify_complex_unions(schema) do
    # Simplify oneOf/anyOf with more than 3 options
    case Map.get(schema, "properties") do
      nil -> schema
      properties ->
        simplified_properties =
          properties
          |> Enum.map(fn {key, prop_schema} ->
            simplified_prop = simplify_union_property(prop_schema)
            {key, simplified_prop}
          end)
          |> Map.new()

        Map.put(schema, "properties", simplified_properties)
    end
  end

  @spec simplify_union_property(map()) :: map()
  defp simplify_union_property(%{"oneOf" => schemas} = property) when length(schemas) > 3 do
    # Keep only first 3 options
    simplified_schemas = Enum.take(schemas, 3)
    Map.put(property, "oneOf", simplified_schemas)
  end

  defp simplify_union_property(property), do: property

  @spec ensure_object_properties(map()) :: map()
  defp ensure_object_properties(%{"type" => "object"} = schema) do
    if Map.has_key?(schema, "properties") do
      schema
    else
      Map.put(schema, "properties", %{})
    end
  end

  defp ensure_object_properties(schema), do: schema

  @spec flatten_schema(map()) :: map()
  defp flatten_schema(schema) do
    # For now, just return as-is since we're not using $ref in base implementation
    # Future enhancement: implement full reference resolution
    schema
  end

  # Metadata and utility functions

  @spec maybe_add_title(map(), String.t() | nil) :: map()
  defp maybe_add_title(schema, nil), do: schema
  defp maybe_add_title(schema, title), do: Map.put(schema, "title", title)

  @spec maybe_add_description(map(), String.t() | nil) :: map()
  defp maybe_add_description(schema, nil), do: schema
  defp maybe_add_description(schema, description), do: Map.put(schema, "description", description)

  @spec maybe_add_description(map(), String.t() | nil, boolean()) :: map()
  defp maybe_add_description(schema, _description, false), do: schema
  defp maybe_add_description(schema, nil, _include), do: schema
  defp maybe_add_description(schema, description, true), do: Map.put(schema, "description", description)

  @spec maybe_add_example(map(), term() | nil) :: map()
  defp maybe_add_example(schema, nil), do: schema
  defp maybe_add_example(schema, example), do: Map.put(schema, "examples", [example])

  @spec maybe_add_default(map(), term() | nil) :: map()
  defp maybe_add_default(schema, nil), do: schema
  defp maybe_add_default(schema, default), do: Map.put(schema, "default", default)

  @spec add_sinter_metadata(map(), Schema.t()) :: map()
  defp add_sinter_metadata(schema, sinter_schema) do
    metadata = %{
      "x-sinter-version" => sinter_schema.metadata.sinter_version,
      "x-sinter-field-count" => sinter_schema.metadata.field_count,
      "x-sinter-created-at" => DateTime.to_iso8601(sinter_schema.metadata.created_at)
    }

    Map.merge(schema, metadata)
  end

  # Validation helper functions

  @spec check_basic_structure(map(), [String.t()]) :: [String.t()]
  defp check_basic_structure(schema, issues) do
    case Map.get(schema, "type") do
      "object" ->
        if Map.has_key?(schema, "properties") do
          issues
        else
          ["Object schema missing 'properties'" | issues]
        end
      nil ->
        ["Schema missing 'type' field" | issues]
      _ ->
        issues
    end
  end

  @spec check_type_consistency(map(), [String.t()]) :: [String.t()]
  defp check_type_consistency(schema, issues) do
    # Check that type field has valid value
    case Map.get(schema, "type") do
      type when type in ["object", "array", "string", "number", "integer", "boolean", "null"] ->
        issues
      type when is_binary(type) ->
        ["Invalid type: #{type}" | issues]
      _ ->
        issues
    end
  end

  @spec check_constraint_validity(map(), [String.t()]) :: [String.t()]
  defp check_constraint_validity(schema, issues) do
    # Check numeric constraints
    issues = check_numeric_constraints(schema, issues)

    # Check string constraints
    issues = check_string_constraints(schema, issues)

    # Check array constraints
    check_array_constraints(schema, issues)
  end

  @spec check_numeric_constraints(map(), [String.t()]) :: [String.t()]
  defp check_numeric_constraints(schema, issues) do
    case {Map.get(schema, "minimum"), Map.get(schema, "maximum")} do
      {min, max} when is_number(min) and is_number(max) and min > max ->
        ["minimum (#{min}) cannot be greater than maximum (#{max})" | issues]
      _ ->
        issues
    end
  end

  @spec check_string_constraints(map(), [String.t()]) :: [String.t()]
  defp check_string_constraints(schema, issues) do
    case {Map.get(schema, "minLength"), Map.get(schema, "maxLength")} do
      {min, max} when is_integer(min) and is_integer(max) and min > max ->
        ["minLength (#{min}) cannot be greater than maxLength (#{max})" | issues]
      _ ->
        issues
    end
  end

  @spec check_array_constraints(map(), [String.t()]) :: [String.t()]
  defp check_array_constraints(schema, issues) do
    case {Map.get(schema, "minItems"), Map.get(schema, "maxItems")} do
      {min, max} when is_integer(min) and is_integer(max) and min > max ->
        ["minItems (#{min}) cannot be greater than maxItems (#{max})" | issues]
      _ ->
        issues
    end
  end
end
