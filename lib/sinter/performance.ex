defmodule Sinter.Performance do
  @moduledoc """
  Performance monitoring and optimization utilities for Sinter.

  This module provides tools for monitoring validation performance and
  optimizing schemas for high-throughput scenarios common in DSPEx.
  """

  alias Sinter.{Schema, Validator}

  @doc """
  Benchmarks validation performance for a schema and dataset.

  Returns timing information useful for optimizing DSPEx programs.

  ## Parameters

    * `schema` - The schema to benchmark
    * `dataset` - Sample data for benchmarking
    * `opts` - Benchmark options

  ## Options

    * `:iterations` - Number of iterations to run (default: 1000)
    * `:warmup` - Number of warmup iterations (default: 100)

  ## Returns

    * Map with timing statistics

  ## Examples

      iex> schema = Sinter.Schema.define([{:id, :integer, [required: true]}])
      iex> dataset = [%{"id" => 1}, %{"id" => 2}, %{"id" => 3}]
      iex> stats = Sinter.Performance.benchmark_validation(schema, dataset)
      iex> is_number(stats.avg_time_microseconds)
      true
  """
  @spec benchmark_validation(Schema.t(), [map()], keyword()) :: map()
  def benchmark_validation(schema, dataset, opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 1000)
    warmup = Keyword.get(opts, :warmup, 100)

    # Warmup
    Enum.each(1..warmup, fn _ ->
      Enum.each(dataset, &Validator.validate(schema, &1))
    end)

    # Benchmark
    {total_time, _} =
      :timer.tc(fn ->
        Enum.each(1..iterations, fn _ ->
          Enum.each(dataset, &Validator.validate(schema, &1))
        end)
      end)

    total_validations = iterations * length(dataset)
    avg_time_per_validation = total_time / total_validations

    %{
      total_time_microseconds: total_time,
      total_validations: total_validations,
      avg_time_microseconds: avg_time_per_validation,
      validations_per_second: trunc(1_000_000 / avg_time_per_validation)
    }
  end

  @doc """
  Analyzes memory usage during validation.

  Useful for optimizing memory consumption in long-running DSPEx programs.

  ## Parameters

    * `schema` - The schema to analyze
    * `dataset` - Sample data for analysis

  ## Returns

    * Map with memory usage statistics
  """
  @spec analyze_memory_usage(Schema.t(), [map()]) :: map()
  def analyze_memory_usage(schema, dataset) do
    # Force garbage collection before measurement
    :erlang.garbage_collect()
    {_, initial_memory} = :erlang.process_info(self(), :memory)

    # Perform validations
    results = Enum.map(dataset, &Validator.validate(schema, &1))

    # Measure memory after validation
    :erlang.garbage_collect()
    {_, final_memory} = :erlang.process_info(self(), :memory)

    memory_used = final_memory - initial_memory
    successful_validations = Enum.count(results, &match?({:ok, _}, &1))

    %{
      initial_memory_bytes: initial_memory,
      final_memory_bytes: final_memory,
      memory_used_bytes: memory_used,
      memory_per_validation_bytes:
        if(successful_validations > 0, do: memory_used / successful_validations, else: 0),
      successful_validations: successful_validations,
      total_validations: length(dataset)
    }
  end

  @doc """
  Profiles schema complexity for optimization recommendations.

  Analyzes a schema to identify potential performance bottlenecks and
  suggests optimizations for DSPEx usage.

  ## Parameters

    * `schema` - The schema to profile

  ## Returns

    * Map with complexity analysis and optimization suggestions
  """
  @spec profile_schema_complexity(Schema.t()) :: map()
  def profile_schema_complexity(schema) do
    fields = Schema.fields(schema)
    field_count = map_size(fields)

    # Analyze field complexity
    complexity_scores =
      Enum.map(fields, fn {name, field_def} ->
        {name, calculate_field_complexity(field_def)}
      end)

    total_complexity = Enum.sum(Enum.map(complexity_scores, fn {_, score} -> score end))
    avg_complexity = if field_count > 0, do: total_complexity / field_count, else: 0

    # Generate recommendations
    recommendations = generate_optimization_recommendations(fields, complexity_scores)

    %{
      field_count: field_count,
      total_complexity_score: total_complexity,
      average_field_complexity: avg_complexity,
      complexity_by_field: Map.new(complexity_scores),
      optimization_recommendations: recommendations
    }
  end

  # Private helper functions

  @spec calculate_field_complexity(Schema.field_definition()) :: number()
  defp calculate_field_complexity(field_def) do
    base_score = 1.0

    # Type complexity scoring
    type_score =
      case field_def.type do
        atom when atom in [:string, :integer, :float, :boolean, :atom, :any] -> 1.0
        {:array, _inner} -> 2.0
        {:union, types} -> 2.0 + length(types) * 0.5
        {:tuple, types} -> 2.0 + length(types) * 0.3
        {:map, _, _} -> 3.0
        :map -> 2.5
        _ -> 1.5
      end

    # Constraint complexity scoring
    constraint_score = length(field_def.constraints) * 0.5

    # Required fields are slightly more complex due to validation
    required_score = if field_def.required, do: 0.2, else: 0.0

    base_score + type_score + constraint_score + required_score
  end

  @spec generate_optimization_recommendations(map(), [{atom(), number()}]) :: [String.t()]
  defp generate_optimization_recommendations(fields, complexity_scores) do
    recommendations = []

    # Check for overly complex fields
    complex_fields =
      complexity_scores
      |> Enum.filter(fn {_, score} -> score > 5.0 end)
      |> Enum.map(fn {name, _} -> name end)

    recommendations =
      if length(complex_fields) > 0 do
        ["Consider simplifying complex fields: #{inspect(complex_fields)}" | recommendations]
      else
        recommendations
      end

    # Check for too many union types
    union_count =
      fields
      |> Enum.count(fn {_, field_def} -> match?({:union, _}, field_def.type) end)

    recommendations =
      if union_count > 3 do
        [
          "Consider reducing union types (found #{union_count}) for better performance"
          | recommendations
        ]
      else
        recommendations
      end

    # Check for deeply nested structures
    nested_count =
      fields
      |> Enum.count(fn {_, field_def} ->
        match?({:array, {:array, _}}, field_def.type) or
          match?({:map, _, {:map, _, _}}, field_def.type)
      end)

    recommendations =
      if nested_count > 2 do
        ["Consider flattening deeply nested structures (found #{nested_count})" | recommendations]
      else
        recommendations
      end

    # Default recommendation if schema looks good
    if Enum.empty?(recommendations) do
      ["Schema is well-optimized for performance"]
    else
      Enum.reverse(recommendations)
    end
  end
end
