defmodule Sinter.DSPEx do
  @moduledoc """
  Integration helpers specifically designed for DSPEx framework usage.

  This module provides utilities that bridge Sinter's validation capabilities
  with DSPEx's dynamic programming and teleprompter optimization needs.
  """

  alias Sinter.{Error, JsonSchema, Schema, Validator}

  @doc """
  Creates a signature schema for DSPEx programs.

  A signature defines the input and output structure for a DSPEx program,
  combining both into a single schema suitable for validation and optimization.

  ## Parameters

    * `input_fields` - List of input field specifications
    * `output_fields` - List of output field specifications
    * `opts` - Schema options

  ## Returns

    * A schema representing the complete program signature

  ## Examples

      iex> signature = Sinter.DSPEx.create_signature(
      ...>   [
      ...>     {:query, :string, [required: true]},
      ...>     {:context, {:array, :string}, [optional: true]}
      ...>   ],
      ...>   [
      ...>     {:answer, :string, [required: true]},
      ...>     {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]}
      ...>   ],
      ...>   title: "QA Program Signature"
      ...> )
      iex> fields = Sinter.Schema.fields(signature)
      iex> Map.keys(fields)
      [:query, :context, :answer, :confidence]
  """
  @spec create_signature([tuple()], [tuple()], keyword()) :: Schema.t()
  def create_signature(input_fields, output_fields, opts \\ []) do
    all_fields = input_fields ++ output_fields

    # Add metadata to distinguish input vs output fields
    enhanced_fields =
      Enum.map(all_fields, fn {name, type, field_opts} ->
        # Determine if this is an input or output field
        field_type =
          cond do
            {name, type, field_opts} in input_fields -> :input
            {name, type, field_opts} in output_fields -> :output
            true -> :unknown
          end

        # Add metadata to field options
        enhanced_opts = Keyword.put(field_opts, :dspex_field_type, field_type)
        {name, type, enhanced_opts}
      end)

    Schema.define(enhanced_fields, opts)
  end

  @doc """
  Validates LLM output and enhances errors with debugging context.

  This is the primary validation function for DSPEx programs, combining
  standard validation with LLM-specific error enhancement.

  ## Parameters

    * `schema` - The validation schema
    * `llm_output` - Raw output from LLM
    * `original_prompt` - The prompt sent to the LLM
    * `opts` - Validation options

  ## Returns

    * `{:ok, validated_data}` or `{:error, enhanced_errors}`

  ## Examples

      iex> schema = Sinter.Schema.define([{:name, :string, [required: true]}])
      iex> llm_output = %{"age" => 30}  # missing required name
      iex> prompt = "Generate a user profile"
      iex> {:error, errors} = Sinter.DSPEx.validate_llm_output(schema, llm_output, prompt)
      iex> List.first(errors).context.prompt
      "Generate a user profile"
  """
  @spec validate_llm_output(Schema.t(), map(), String.t(), keyword()) ::
          {:ok, map()} | {:error, [Error.t()]}
  def validate_llm_output(schema, llm_output, original_prompt, opts \\ []) do
    case Validator.validate(schema, llm_output, opts) do
      {:ok, validated} ->
        {:ok, validated}

      {:error, errors} ->
        # Enhance all errors with LLM context
        enhanced_errors =
          Enum.map(errors, fn error ->
            Error.with_llm_context(error, llm_output, original_prompt)
          end)

        {:error, enhanced_errors}
    end
  end

  @doc """
  Optimizes a schema based on validation failure patterns.

  Analyzes common validation failures to suggest schema improvements,
  useful for teleprompter optimization loops.

  ## Parameters

    * `original_schema` - The current schema
    * `failure_examples` - List of data that failed validation
    * `opts` - Optimization options

  ## Options

    * `:relaxation_strategy` - How to relax constraints (`:conservative`, `:moderate`, `:aggressive`)
    * `:add_missing_fields` - Whether to add commonly missing fields as optional

  ## Returns

    * `{:ok, optimized_schema, suggestions}` or `{:error, reason}`
  """
  @spec optimize_schema_from_failures(Schema.t(), [map()], keyword()) ::
          {:ok, Schema.t(), [String.t()]} | {:error, String.t()}
  def optimize_schema_from_failures(original_schema, failure_examples, opts \\ []) do
    if Enum.empty?(failure_examples) do
      {:error, "No failure examples provided for optimization"}
    else
      relaxation_strategy = Keyword.get(opts, :relaxation_strategy, :moderate)
      add_missing_fields = Keyword.get(opts, :add_missing_fields, true)

      # Analyze failure patterns
      failure_patterns = analyze_failure_patterns(original_schema, failure_examples)

      # Generate optimization suggestions
      suggestions = generate_optimization_suggestions(failure_patterns)

      # Apply optimizations
      optimized_schema =
        apply_schema_optimizations(
          original_schema,
          failure_patterns,
          relaxation_strategy,
          add_missing_fields
        )

      {:ok, optimized_schema, suggestions}
    end
  end

  @doc """
  Prepares a schema for specific LLM provider optimization.

  Generates both the JSON Schema and metadata needed for optimal
  structured output with different LLM providers.

  ## Parameters

    * `schema` - The Sinter schema
    * `provider` - The target LLM provider
    * `opts` - Provider-specific options

  ## Returns

    * Map with JSON Schema and provider-specific metadata

  ## Examples

      iex> schema = Sinter.Schema.define([{:name, :string, [required: true]}])
      iex> result = Sinter.DSPEx.prepare_for_llm(schema, :openai)
      iex> result.json_schema["additionalProperties"]
      false
      iex> result.provider
      :openai
  """
  @spec prepare_for_llm(Schema.t(), atom(), keyword()) :: map()
  def prepare_for_llm(schema, provider, opts \\ []) do
    json_schema = JsonSchema.for_provider(schema, provider, opts)

    # Add provider-specific metadata
    metadata =
      case provider do
        :openai ->
          %{
            function_calling_compatible: true,
            supports_strict_mode: true,
            recommended_temperature: 0.1
          }

        :anthropic ->
          %{
            tool_use_compatible: true,
            supports_structured_output: true,
            recommended_max_tokens: 4096
          }

        _ ->
          %{generic_provider: true}
      end

    %{
      json_schema: json_schema,
      provider: provider,
      metadata: metadata,
      sinter_schema: schema
    }
  end

  # Private helper functions

  @spec analyze_failure_patterns(Schema.t(), [map()]) :: map()
  defp analyze_failure_patterns(schema, failure_examples) do
    # Validate each failure example to collect error patterns
    all_errors =
      failure_examples
      |> Enum.flat_map(fn example ->
        case Validator.validate(schema, example) do
          {:error, errors} -> errors
          # Skip successful validations
          {:ok, _} -> []
        end
      end)

    # Group errors by type and field
    error_patterns = %{
      missing_fields: collect_missing_field_errors(all_errors),
      type_mismatches: collect_type_mismatch_errors(all_errors),
      constraint_violations: collect_constraint_violation_errors(all_errors),
      common_extra_fields: find_common_extra_fields(failure_examples, schema)
    }

    error_patterns
  end

  @spec collect_missing_field_errors([Error.t()]) :: %{atom() => integer()}
  defp collect_missing_field_errors(errors) do
    errors
    |> Enum.filter(&(&1.code == :required))
    |> Enum.map(fn error -> List.first(error.path) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  @spec collect_type_mismatch_errors([Error.t()]) :: %{atom() => integer()}
  defp collect_type_mismatch_errors(errors) do
    errors
    |> Enum.filter(&(&1.code == :type))
    |> Enum.map(fn error -> List.first(error.path) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  @spec collect_constraint_violation_errors([Error.t()]) :: %{atom() => integer()}
  defp collect_constraint_violation_errors(errors) do
    constraint_codes = [:min_length, :max_length, :gt, :lt, :gteq, :lteq, :format, :choices]

    errors
    |> Enum.filter(&(&1.code in constraint_codes))
    |> Enum.map(fn error -> List.first(error.path) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  @spec find_common_extra_fields([map()], Schema.t()) :: [atom()]
  defp find_common_extra_fields(examples, schema) do
    schema_fields = Schema.fields(schema) |> Map.keys() |> MapSet.new()

    # Find fields that appear in examples but not in schema
    extra_fields =
      examples
      |> Enum.flat_map(&Map.keys/1)
      |> Enum.map(fn key -> if is_binary(key), do: String.to_atom(key), else: key end)
      |> Enum.reject(&(&1 in schema_fields))
      |> Enum.frequencies()
      # Appear in 30%+ of examples
      |> Enum.filter(fn {_field, count} -> count >= length(examples) * 0.3 end)
      |> Enum.map(fn {field, _count} -> field end)

    extra_fields
  end

  @spec generate_optimization_suggestions(map()) :: [String.t()]
  defp generate_optimization_suggestions(patterns) do
    suggestions = []

    # Missing fields suggestions
    suggestions =
      if map_size(patterns.missing_fields) > 0 do
        fields = Map.keys(patterns.missing_fields) |> Enum.join(", ")
        ["Consider making frequently missing fields optional: #{fields}" | suggestions]
      else
        suggestions
      end

    # Type mismatch suggestions
    suggestions =
      if map_size(patterns.type_mismatches) > 0 do
        fields = Map.keys(patterns.type_mismatches) |> Enum.join(", ")
        ["Consider enabling coercion or using union types for: #{fields}" | suggestions]
      else
        suggestions
      end

    # Constraint violation suggestions
    suggestions =
      if map_size(patterns.constraint_violations) > 0 do
        fields = Map.keys(patterns.constraint_violations) |> Enum.join(", ")
        ["Consider relaxing constraints for: #{fields}" | suggestions]
      else
        suggestions
      end

    # Extra fields suggestions
    suggestions =
      if length(patterns.common_extra_fields) > 0 do
        fields = patterns.common_extra_fields |> Enum.join(", ")
        ["Consider adding common extra fields as optional: #{fields}" | suggestions]
      else
        suggestions
      end

    if Enum.empty?(suggestions) do
      ["No clear optimization patterns found"]
    else
      Enum.reverse(suggestions)
    end
  end

  @spec apply_schema_optimizations(Schema.t(), map(), atom(), boolean()) :: Schema.t()
  defp apply_schema_optimizations(schema, patterns, relaxation_strategy, add_missing_fields) do
    current_fields = Schema.fields(schema)

    # Start with current field specifications
    optimized_field_specs =
      Enum.map(current_fields, fn {name, field_def} ->
        {name, field_def.type, build_field_options_from_def(field_def)}
      end)

    # Apply constraint relaxation based on strategy
    optimized_field_specs =
      case relaxation_strategy do
        # No changes
        :conservative -> optimized_field_specs
        :moderate -> relax_constraints_moderate(optimized_field_specs, patterns)
        :aggressive -> relax_constraints_aggressive(optimized_field_specs, patterns)
      end

    # Add missing fields as optional if requested
    optimized_field_specs =
      if add_missing_fields do
        add_commonly_missing_fields(optimized_field_specs, patterns.common_extra_fields)
      else
        optimized_field_specs
      end

    # Create new schema with original config
    original_config = Schema.config(schema)

    config_opts =
      [
        title: original_config.title,
        description: original_config.description,
        strict: original_config.strict,
        post_validate: original_config.post_validate
      ]
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    Schema.define(optimized_field_specs, config_opts)
  end

  @spec build_field_options_from_def(Schema.field_definition()) :: keyword()
  defp build_field_options_from_def(field_def) do
    opts = [required: field_def.required]
    opts = if field_def.description, do: [description: field_def.description] ++ opts, else: opts
    opts = if field_def.example, do: [example: field_def.example] ++ opts, else: opts
    opts = if field_def.default, do: [default: field_def.default] ++ opts, else: opts
    field_def.constraints ++ opts
  end

  @spec relax_constraints_moderate([tuple()], map()) :: [tuple()]
  defp relax_constraints_moderate(field_specs, patterns) do
    # Make frequently missing fields optional
    frequently_missing = Map.keys(patterns.missing_fields)

    Enum.map(field_specs, fn {name, type, opts} ->
      if name in frequently_missing do
        # Change required to optional
        updated_opts = Keyword.put(opts, :required, false)
        {name, type, updated_opts}
      else
        {name, type, opts}
      end
    end)
  end

  @spec relax_constraints_aggressive([tuple()], map()) :: [tuple()]
  defp relax_constraints_aggressive(field_specs, patterns) do
    # First apply moderate relaxation
    field_specs = relax_constraints_moderate(field_specs, patterns)

    # Additionally relax constraints on fields with violations
    problematic_fields = Map.keys(patterns.constraint_violations)

    Enum.map(field_specs, fn {name, type, opts} ->
      if name in problematic_fields do
        # Remove strict constraints
        relaxed_opts =
          opts
          |> Keyword.delete(:min_length)
          |> Keyword.delete(:max_length)
          |> Keyword.delete(:format)

        {name, type, relaxed_opts}
      else
        {name, type, opts}
      end
    end)
  end

  @spec add_commonly_missing_fields([tuple()], [atom()]) :: [tuple()]
  defp add_commonly_missing_fields(field_specs, common_extra_fields) do
    # Add extra fields as optional :any type
    extra_field_specs =
      Enum.map(common_extra_fields, fn field_name ->
        {field_name, :any, [optional: true]}
      end)

    field_specs ++ extra_field_specs
  end
end
