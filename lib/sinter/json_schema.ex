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

  ## Usage

      schema = Sinter.Schema.define([
        {:name, :string, [required: true, min_length: 2]},
        {:age, :integer, [optional: true, gt: 0]}
      ])

      # Basic JSON Schema generation
      json_schema = Sinter.JsonSchema.generate(schema)

      # Provider-specific optimization
      openai_schema = Sinter.JsonSchema.generate(schema, optimize_for_provider: :openai)

      # For specific providers
      anthropic_schema = Sinter.JsonSchema.for_provider(schema, :anthropic)
  """

  alias Sinter.{Schema, Types}

  @type draft :: :draft2020_12 | :draft7

  @type generation_opts :: [
          optimize_for_provider: :openai | :anthropic | :generic,
          draft: draft(),
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
    draft = determine_draft(opts, provider)
    strict_override? = Keyword.has_key?(opts, :strict)
    strict = Keyword.get(opts, :strict, Schema.strict?(schema))

    builder_opts =
      opts
      |> Keyword.put(:draft, draft)
      |> Keyword.put(:strict, strict)
      |> Keyword.put(:strict_override?, strict_override?)

    # Build base JSON Schema
    base_schema =
      build_base_schema(schema, include_descriptions, builder_opts)

    # Apply provider optimizations
    optimized_schema = apply_provider_optimizations(base_schema, provider)

    # Apply recursive strictness for provider optimizations or explicit strict mode
    final_schema =
      if provider in [:openai, :anthropic] or strict do
        apply_recursive_strictness(optimized_schema)
      else
        optimized_schema
      end

    # Flatten if requested
    final_schema =
      if flatten do
        flatten_schema(final_schema)
      else
        final_schema
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

  Uses `JSV` to validate against the JSON Schema meta-schema.

  ## Parameters

    * `json_schema` - The JSON Schema to validate
    * `opts` - Validation options

  ## Options

    * `:draft` - Override default meta-schema (`:draft2020_12` or `:draft7`)

  ## Returns

    * `:ok` if schema is valid
    * `{:error, issues}` if problems are found
  """
  @spec validate_schema(map(), keyword()) :: :ok | {:error, [String.t()]}
  def validate_schema(json_schema, opts \\ []) do
    build_opts =
      case Keyword.get(opts, :draft) do
        nil -> []
        draft -> [default_meta: draft_schema_uri(draft)]
      end

    case JSV.build(json_schema, build_opts) do
      {:ok, _root} -> :ok
      {:error, error} -> {:error, [Exception.message(error)]}
    end
  end

  # Private helper functions

  @spec build_base_schema(Schema.t(), boolean(), keyword()) :: map()
  defp build_base_schema(schema, include_descriptions, opts) do
    config = Schema.config(schema)
    strict = Keyword.get(opts, :strict, config.strict)
    draft = Keyword.get(opts, :draft, :draft2020_12)

    base = %{
      "$schema" => draft_schema_uri(draft),
      "type" => "object",
      "properties" => build_properties(schema, include_descriptions, opts),
      "required" => build_required_list(schema),
      "additionalProperties" => not strict
    }

    # Add optional top-level metadata
    base
    |> maybe_add_title(config.title)
    |> maybe_add_description(config.description)
    |> add_sinter_metadata(schema)
  end

  @spec build_properties(Schema.t(), boolean(), keyword()) :: map()
  defp build_properties(schema, include_descriptions, opts) do
    schema.fields
    |> Enum.map(fn {field_name, field_def} ->
      property_schema = build_property_schema(field_def, include_descriptions, opts)
      {to_string(field_name), property_schema}
    end)
    |> Map.new()
  end

  @spec build_property_schema(Schema.field_definition(), boolean(), keyword()) :: map()
  defp build_property_schema(field_def, include_descriptions, opts) do
    # Convert type to JSON Schema
    type_schema = build_type_schema(field_def.type, include_descriptions, opts)

    # Add constraints
    constrained_schema = add_constraints(type_schema, field_def.constraints)

    # Add field metadata
    constrained_schema
    |> maybe_add_description(field_def.description, include_descriptions)
    |> maybe_add_example(field_def.example)
    |> maybe_add_default(field_def.default)
  end

  defp build_type_schema({:array, inner_type, constraints}, include_descriptions, opts) do
    base = %{
      "type" => "array",
      "items" => build_type_schema(inner_type, include_descriptions, opts)
    }

    Enum.reduce(constraints, base, fn
      {:min_items, min}, acc -> Map.put(acc, "minItems", min)
      {:max_items, max}, acc -> Map.put(acc, "maxItems", max)
      _other, acc -> acc
    end)
  end

  defp build_type_schema({:array, inner_type}, include_descriptions, opts) do
    %{
      "type" => "array",
      "items" => build_type_schema(inner_type, include_descriptions, opts)
    }
  end

  defp build_type_schema({:union, types}, include_descriptions, opts) do
    %{"oneOf" => Enum.map(types, &build_type_schema(&1, include_descriptions, opts))}
  end

  defp build_type_schema({:tuple, types}, include_descriptions, opts) do
    %{
      "type" => "array",
      "items" => false,
      "prefixItems" => Enum.map(types, &build_type_schema(&1, include_descriptions, opts)),
      "minItems" => length(types),
      "maxItems" => length(types)
    }
  end

  defp build_type_schema({:map, key_type, value_type}, include_descriptions, opts) do
    base = %{"type" => "object"}

    case {key_type, value_type} do
      {:string, :any} ->
        Map.put(base, "additionalProperties", true)

      {:string, value_type} ->
        Map.put(
          base,
          "additionalProperties",
          build_type_schema(value_type, include_descriptions, opts)
        )

      _ ->
        Map.put(base, "additionalProperties", true)
    end
  end

  defp build_type_schema({:nullable, inner_type}, include_descriptions, opts) do
    %{
      "anyOf" => [
        build_type_schema(inner_type, include_descriptions, opts),
        %{"type" => "null"}
      ]
    }
  end

  defp build_type_schema({:object, %Schema{} = nested_schema}, include_descriptions, opts) do
    build_object_schema(nested_schema, include_descriptions, opts)
  end

  defp build_type_schema({:object, nested_fields}, include_descriptions, opts)
       when is_list(nested_fields) do
    nested_schema = Schema.define(nested_fields)
    build_object_schema(nested_schema, include_descriptions, opts)
  end

  defp build_type_schema(type_spec, _include_descriptions, _opts) do
    Types.to_json_schema(type_spec)
  end

  defp build_object_schema(%Schema{} = schema, include_descriptions, opts) do
    config = Schema.config(schema)
    strict_override? = Keyword.get(opts, :strict_override?, false)
    strict_value = Keyword.get(opts, :strict, config.strict)
    strict = if strict_override?, do: strict_value, else: config.strict

    base = %{
      "type" => "object",
      "properties" => build_properties(schema, include_descriptions, opts),
      "required" => build_required_list(schema),
      "additionalProperties" => not strict
    }

    base
    |> maybe_add_title(config.title)
    |> maybe_add_description(config.description, include_descriptions)
  end

  @spec add_constraints(map(), keyword()) :: map()
  defp add_constraints(schema, constraints) do
    Enum.reduce(constraints, schema, fn constraint, acc ->
      add_single_constraint(acc, constraint)
    end)
  end

  @spec add_single_constraint(map(), Types.constraint()) :: map()
  defp add_single_constraint(schema, {:min_length, min}), do: Map.put(schema, "minLength", min)
  defp add_single_constraint(schema, {:max_length, max}), do: Map.put(schema, "maxLength", max)
  defp add_single_constraint(schema, {:min_items, min}), do: Map.put(schema, "minItems", min)
  defp add_single_constraint(schema, {:max_items, max}), do: Map.put(schema, "maxItems", max)

  defp add_single_constraint(schema, {:gt, threshold}),
    do: Map.put(schema, "exclusiveMinimum", threshold)

  defp add_single_constraint(schema, {:gteq, threshold}), do: Map.put(schema, "minimum", threshold)

  defp add_single_constraint(schema, {:lt, threshold}),
    do: Map.put(schema, "exclusiveMaximum", threshold)

  defp add_single_constraint(schema, {:lteq, threshold}), do: Map.put(schema, "maximum", threshold)

  defp add_single_constraint(schema, {:format, regex}) when is_struct(regex, Regex) do
    # Convert Regex to string pattern
    pattern = Regex.source(regex)
    Map.put(schema, "pattern", pattern)
  end

  defp add_single_constraint(schema, {:choices, choices}) when is_list(choices) do
    Map.put(schema, "enum", choices)
  end

  # Skip unknown constraints gracefully
  defp add_single_constraint(schema, _unknown_constraint), do: schema

  @spec build_required_list(Schema.t()) :: [String.t()]
  defp build_required_list(schema) do
    schema
    |> Schema.required_fields()
    |> Enum.map(&to_string/1)
  end

  @spec apply_provider_optimizations(map(), atom()) :: map()
  defp apply_provider_optimizations(schema, :openai) do
    schema
    # OpenAI requires this
    |> Map.put("additionalProperties", false)
    |> ensure_required_array()
    |> optimize_for_function_calling()
  end

  defp apply_provider_optimizations(schema, :anthropic) do
    schema
    # Anthropic prefers this
    |> Map.put("additionalProperties", false)
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
    |> remove_unsupported_formats(["date", "time", "email"])
    |> simplify_complex_unions()
  end

  @spec optimize_for_tool_use(map()) :: map()
  defp optimize_for_tool_use(schema) do
    # Anthropic tool use optimizations
    schema
    |> remove_unsupported_formats(["uri", "uuid"])
    |> ensure_object_properties()
  end

  @spec remove_unsupported_formats(map(), [String.t()]) :: map()
  defp remove_unsupported_formats(schema, unsupported_formats) do
    case Map.get(schema, "properties") do
      nil ->
        schema

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

  @spec remove_format_if_unsupported(map(), [String.t()]) :: map()
  defp remove_format_if_unsupported(property_schema, unsupported_formats) do
    case Map.get(property_schema, "format") do
      format when is_binary(format) ->
        if format in unsupported_formats do
          Map.delete(property_schema, "format")
        else
          property_schema
        end

      _ ->
        property_schema
    end
  end

  @spec simplify_complex_unions(map()) :: map()
  defp simplify_complex_unions(schema) do
    # Simplify oneOf/anyOf with more than 3 options
    case Map.get(schema, "properties") do
      nil ->
        schema

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

  defp apply_recursive_strictness(schema) when is_map(schema) do
    schema =
      case schema do
        %{"type" => "object", "properties" => _props} ->
          Map.put(schema, "additionalProperties", false)

        _ ->
          schema
      end

    Enum.reduce(schema, %{}, fn {key, value}, acc ->
      Map.put(acc, key, apply_recursive_strictness(value))
    end)
  end

  defp apply_recursive_strictness(schema) when is_list(schema) do
    Enum.map(schema, &apply_recursive_strictness/1)
  end

  defp apply_recursive_strictness(schema), do: schema

  @spec flatten_schema(map()) :: map()
  defp flatten_schema(schema) do
    # For now, just return as-is since we're not using $ref in base implementation
    # Future enhancement: implement full reference resolution
    schema
  end

  defp determine_draft(opts, provider) do
    case Keyword.get(opts, :draft) do
      nil ->
        if provider in [:openai, :anthropic] do
          :draft7
        else
          :draft2020_12
        end

      draft ->
        draft
    end
  end

  defp draft_schema_uri(:draft7), do: "http://json-schema.org/draft-07/schema#"
  defp draft_schema_uri(:draft2020_12), do: "https://json-schema.org/draft/2020-12/schema"

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

  defp maybe_add_description(schema, description, true),
    do: Map.put(schema, "description", description)

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
end
