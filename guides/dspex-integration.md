# DSPEx Integration

Sinter serves as the schema engine for [DSPEx](https://github.com/nshkrdotcom/dspex),
the Elixir implementation of DSPy. It handles structured output validation for
LLM programs, providing schema definition, JSON Schema generation tuned for
specific providers, and iterative schema optimization driven by validation
failures.

This guide covers the `Sinter.DSPEx` module and supporting functions from the
core library that are most relevant to DSPEx workflows.

## Creating Signatures

A DSPEx *signature* declares the input and output fields of a program. Use
`Sinter.DSPEx.create_signature/3` to build one from two field lists. Each field
is a `{name, type, options}` tuple -- the same format used by
`Sinter.Schema.define/2`. The function tags every field with a
`:dspex_field_type` metadata value (`:input` or `:output`) so downstream
tooling can distinguish them.

```elixir
signature = Sinter.DSPEx.create_signature(
  # Input fields
  [
    {:question, :string, [required: true]},
    {:context, {:array, :string}, [optional: true]}
  ],
  # Output fields
  [
    {:answer, :string, [required: true, min_length: 1]},
    {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]}
  ],
  title: "QA Signature"
)

# The result is a standard Sinter.Schema.t()
fields = Sinter.Schema.fields(signature)
Map.keys(fields)
# => ["question", "context", "answer", "confidence"]
```

Input and output fields are merged into a single schema. This is intentional --
a DSPEx program validates a complete trace (inputs plus outputs) as one unit.

## Validating LLM Output

After the LLM responds, pipe the parsed output through
`Sinter.DSPEx.validate_llm_output/4`. It runs standard Sinter validation and,
on failure, enriches every error with the original prompt and raw response so
you can inspect what went wrong.

```elixir
schema = Sinter.DSPEx.create_signature(
  [{:query, :string, [required: true]}],
  [{:answer, :string, [required: true]},
   {:sources, {:array, :string}, [required: true]}]
)

llm_output = %{"answer" => "Elixir is a functional language."}
prompt = "Answer the following question and cite your sources."

case Sinter.DSPEx.validate_llm_output(schema, llm_output, prompt) do
  {:ok, validated} ->
    # Use validated data
    validated

  {:error, errors} ->
    # Each error carries LLM context for debugging
    for error <- errors do
      IO.puts(Sinter.Error.format(error))
      IO.inspect(error.context.prompt)
      IO.inspect(error.context.llm_response)
    end
end
```

The `context` map on each `Sinter.Error` struct contains:

| Key              | Value                                |
|------------------|--------------------------------------|
| `:llm_response`  | The raw map returned by the LLM      |
| `:prompt`        | The prompt that produced the response |

This makes it straightforward to log or replay failures during teleprompter
optimization loops.

## Provider Preparation

`Sinter.DSPEx.prepare_for_llm/3` converts a Sinter schema into a
provider-ready payload containing the JSON Schema and provider-specific
metadata. Supported providers are `:openai` and `:anthropic`.

```elixir
schema = Sinter.DSPEx.create_signature(
  [{:topic, :string, [required: true]}],
  [{:summary, :string, [required: true]},
   {:key_points, {:array, :string}, [required: true]}],
  title: "Summarizer"
)

# OpenAI
openai = Sinter.DSPEx.prepare_for_llm(schema, :openai)
openai.provider
# => :openai
openai.json_schema["additionalProperties"]
# => false
openai.metadata.function_calling_compatible
# => true
openai.metadata.supports_strict_mode
# => true

# Anthropic
anthropic = Sinter.DSPEx.prepare_for_llm(schema, :anthropic)
anthropic.metadata.tool_use_compatible
# => true
anthropic.metadata.recommended_max_tokens
# => 4096
```

The returned map has this shape:

```elixir
%{
  json_schema: %{...},        # Provider-optimized JSON Schema
  provider: :openai,           # Target provider atom
  metadata: %{...},            # Provider-specific hints
  sinter_schema: schema        # Original Sinter.Schema.t() for re-validation
}
```

You can also call `Sinter.JsonSchema.for_provider/3` directly when you only
need the JSON Schema without the metadata wrapper:

```elixir
json_schema = Sinter.JsonSchema.for_provider(schema, :openai)
```

## Schema Optimization

When an LLM repeatedly fails validation, `Sinter.DSPEx.optimize_schema_from_failures/3`
analyzes the failure patterns and returns an improved schema along with
human-readable suggestions.

```elixir
schema = Sinter.DSPEx.create_signature(
  [{:query, :string, [required: true]}],
  [{:answer, :string, [required: true]},
   {:reasoning, :string, [required: true, min_length: 10]}]
)

# Collect outputs that failed validation
failures = [
  %{"answer" => "Yes"},                          # missing reasoning
  %{"answer" => "No", "reasoning" => "Short"},   # reasoning too short
  %{"answer" => "Maybe", "explanation" => "..."}  # wrong field name
]

{:ok, optimized, suggestions} =
  Sinter.DSPEx.optimize_schema_from_failures(schema, failures,
    relaxation_strategy: :moderate,
    add_missing_fields: true
  )

IO.inspect(suggestions)
# => [
#   "Consider making frequently missing fields optional: reasoning",
#   "Consider relaxing constraints for: reasoning",
#   "Consider adding common extra fields as optional: explanation"
# ]
```

### Relaxation Strategies

The `:relaxation_strategy` option controls how aggressively the optimizer
modifies the schema:

| Strategy        | Behavior                                                         |
|-----------------|------------------------------------------------------------------|
| `:conservative` | No constraint changes. Only `add_missing_fields` applies.        |
| `:moderate`     | Makes frequently-missing required fields optional.               |
| `:aggressive`   | Applies `:moderate` changes, then removes `min_length`, `max_length`, and `format` constraints on fields with repeated violations. |

### Adding Missing Fields

When `:add_missing_fields` is `true` (the default), fields that appear in at
least 30% of the failure examples but are not in the schema are appended as
optional `:any`-typed fields. This is useful when the LLM consistently produces
extra keys that should be accepted rather than rejected.

### Optimization Loop Example

A typical teleprompter loop feeds failures back iteratively:

```elixir
defmodule MyOptimizer do
  def run(schema, dataset, max_rounds \\ 3) do
    Enum.reduce_while(1..max_rounds, schema, fn round, current_schema ->
      failures =
        dataset
        |> Enum.map(&call_llm(current_schema, &1))
        |> Enum.filter(&match?({:error, _}, &1))
        |> Enum.map(fn {:error, raw} -> raw end)

      if failures == [] do
        {:halt, current_schema}
      else
        {:ok, improved, suggestions} =
          Sinter.DSPEx.optimize_schema_from_failures(
            current_schema,
            failures,
            relaxation_strategy: :moderate
          )

        IO.puts("Round #{round}: #{length(suggestions)} suggestions")
        {:cont, improved}
      end
    end)
  end
end
```

## Dynamic Schema Creation

Two functions in the top-level `Sinter` module support schema creation at
runtime, which is critical for DSPEx teleprompters like MIPRO.

### Inferring Schemas from Examples

`Sinter.infer_schema/2` examines a list of example maps and produces a schema
with inferred types and requirement flags.

```elixir
examples = [
  %{"question" => "What is Elixir?", "answer" => "A language", "score" => 0.95},
  %{"question" => "What is OTP?", "answer" => "A framework", "score" => 0.88},
  %{"question" => "What is BEAM?", "answer" => "A VM"}
]

schema = Sinter.infer_schema(examples, min_occurrence_ratio: 0.6)

fields = Sinter.Schema.fields(schema)
fields["question"].type     # => :string
fields["question"].required # => true   (appears in 3/3 examples)
fields["score"].type        # => :float
fields["score"].required    # => true   (appears in 2/3 >= 0.6 ratio)
```

The algorithm:

1. Discovers all unique field names across examples.
2. Infers the most common Elixir type for each field (`:string`, `:integer`,
   `:float`, `:boolean`, `{:array, inner}`, `:map`, etc.).
3. Marks fields as required when they appear in at least `:min_occurrence_ratio`
   of the examples (default `0.8`).

### Merging Schemas

`Sinter.merge_schemas/2` combines multiple schemas into one. Later schemas take
precedence when field names conflict.

```elixir
input_schema = Sinter.Schema.define([
  {:query, :string, [required: true]},
  {:max_tokens, :integer, [optional: true, gt: 0]}
])

output_schema = Sinter.Schema.define([
  {:answer, :string, [required: true]},
  {:confidence, :float, [optional: true, gteq: 0.0, lteq: 1.0]}
])

program_schema = Sinter.merge_schemas([input_schema, output_schema])

fields = Sinter.Schema.fields(program_schema)
Map.keys(fields)
# => ["query", "max_tokens", "answer", "confidence"]
```

This is equivalent to what `create_signature/3` does internally, but
`merge_schemas/2` is more general -- it works with any number of schemas and
is useful when composing larger programs from sub-components.

## Performance

The `Sinter.Performance` module provides utilities for profiling validation in
high-throughput DSPEx pipelines.

### Benchmarking Validation Throughput

`benchmark_validation/3` measures how fast a schema validates a sample dataset.
It runs warmup iterations first, then collects timing statistics.

```elixir
schema = Sinter.DSPEx.create_signature(
  [{:query, :string, [required: true]}],
  [{:answer, :string, [required: true]},
   {:confidence, :float, [required: true]}]
)

dataset = [
  %{"query" => "Q1", "answer" => "A1", "confidence" => 0.9},
  %{"query" => "Q2", "answer" => "A2", "confidence" => 0.8},
  %{"query" => "Q3", "answer" => "A3", "confidence" => 0.7}
]

stats = Sinter.Performance.benchmark_validation(schema, dataset,
  iterations: 5_000,
  warmup: 500
)

stats.avg_time_microseconds     # Average time per single validation
stats.validations_per_second    # Throughput estimate
stats.total_validations         # iterations * length(dataset)
```

### Analyzing Memory Usage

`analyze_memory_usage/2` reports process-level memory before and after
validating a dataset, helping identify schemas that allocate excessively.

```elixir
mem = Sinter.Performance.analyze_memory_usage(schema, dataset)

mem.memory_used_bytes             # Total bytes allocated during validation
mem.memory_per_validation_bytes   # Bytes per successful validation
mem.successful_validations        # Count of {:ok, _} results
```

### Profiling Schema Complexity

`profile_schema_complexity/1` scores individual fields and the schema as a
whole, returning actionable recommendations.

```elixir
profile = Sinter.Performance.profile_schema_complexity(schema)

profile.field_count                  # Number of fields
profile.total_complexity_score       # Sum of per-field scores
profile.average_field_complexity     # Mean score across fields
profile.complexity_by_field          # %{field_name => score}
profile.optimization_recommendations # List of suggestion strings
```

Complexity scoring accounts for type depth (arrays, unions, maps), number of
constraints, and whether a field is required. Recommendations flag overly
complex fields, excessive union types, and deeply nested structures.

### Practical Tip

Run these utilities during development to establish a baseline, then again after
schema optimization rounds. A typical workflow:

```elixir
# Before optimization
before = Sinter.Performance.benchmark_validation(original_schema, dataset)

# Optimize
{:ok, optimized, _} =
  Sinter.DSPEx.optimize_schema_from_failures(original_schema, failures)

# After optimization
after = Sinter.Performance.benchmark_validation(optimized, dataset)

IO.puts("Speedup: #{before.avg_time_microseconds / after.avg_time_microseconds}x")
```
