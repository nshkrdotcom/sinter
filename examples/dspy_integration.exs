#!/usr/bin/env elixir

# DSPy Integration Examples for Sinter
# Shows how to use Sinter with DSPy-style dynamic programming patterns

IO.puts("=== Sinter DSPy Integration Examples ===")
IO.puts("")

# Add the compiled beam files to the path
Code.append_path("../_build/dev/lib/sinter/ebin")
Code.append_path("../_build/dev/lib/jason/ebin")

# ============================================================================
# 1. PROGRAM SIGNATURE CREATION
# ============================================================================

IO.puts("1. DSPy Program Signatures")
IO.puts("--------------------------")

# Create a question-answering program signature
qa_signature = Sinter.DSPEx.create_signature(
  # Input fields
  [
    {:question, :string, [required: true]},
    {:context, {:array, :string}, [optional: true]}
  ],
  # Output fields
  [
    {:answer, :string, [required: true]},
    {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]},
    {:reasoning, :string, [optional: true]}
  ],
  title: "QA Program Signature"
)

IO.puts("✓ Created QA signature with #{map_size(qa_signature.fields)} fields")

# Create a chain-of-thought signature
_cot_signature = Sinter.DSPEx.create_signature(
  [
    {:problem, :string, [required: true]},
    {:examples, {:array, :map}, [optional: true]}
  ],
  [
    {:reasoning_steps, {:array, :string}, [required: true]},
    {:final_answer, :string, [required: true]}
  ],
  title: "Chain of Thought Signature"
)

IO.puts("✓ Created Chain-of-Thought signature")
IO.puts("")

# ============================================================================
# 2. LLM OUTPUT VALIDATION
# ============================================================================

IO.puts("2. LLM Output Validation")
IO.puts("------------------------")

# Simulate LLM output validation
llm_output = %{
  "answer" => "The capital of France is Paris.",
  "confidence" => 0.95,
  "reasoning" => "This is a well-known geographical fact."
}

original_prompt = """
Question: What is the capital of France?
Please provide your answer with confidence and reasoning.
"""

case Sinter.DSPEx.validate_llm_output(qa_signature, llm_output, original_prompt) do
  {:ok, validated} ->
    IO.puts("✓ LLM output validated successfully")
    IO.puts("  Answer: #{validated.answer}")
    IO.puts("  Confidence: #{validated.confidence}")
  {:error, errors} ->
    IO.puts("✗ LLM output validation failed:")
    Enum.each(errors, fn error ->
      IO.puts("  - #{error.message}")
      if error.context do
        IO.puts("    Prompt: #{String.slice(error.context.prompt, 0, 50)}...")
      end
    end)
end

# Example with validation failure
bad_llm_output = %{
  "answer" => "Paris",
  "confidence" => 1.5,  # Invalid: > 1.0
  "wrong_field" => "This shouldn't be here"
}

case Sinter.DSPEx.validate_llm_output(qa_signature, bad_llm_output, original_prompt) do
  {:ok, _} -> IO.puts("Unexpected success")
  {:error, errors} ->
    IO.puts("✓ Correctly caught validation errors:")
    Enum.each(errors, fn error ->
      IO.puts("  - Field '#{Enum.join(error.path, ".")}': #{error.message}")
    end)
end
IO.puts("")

# ============================================================================
# 3. SCHEMA INFERENCE FROM EXAMPLES
# ============================================================================

IO.puts("3. Schema Inference from Examples (MIPRO-style)")
IO.puts("-----------------------------------------------")

# Simulate training examples from a DSPy program
training_examples = [
  %{
    "question" => "What is 2+2?",
    "answer" => "4",
    "confidence" => 1.0,
    "steps" => ["Add 2 and 2", "The result is 4"]
  },
  %{
    "question" => "What is the color of the sky?",
    "answer" => "Blue",
    "confidence" => 0.9,
    "steps" => ["Consider typical sky color", "Usually blue during day"]
  },
  %{
    "question" => "Who wrote Hamlet?",
    "answer" => "William Shakespeare",
    "confidence" => 1.0,
    "steps" => ["Recall famous plays", "Hamlet is by Shakespeare"]
  }
]

# Infer schema from examples (perfect for MIPRO optimization)
inferred_schema = Sinter.infer_schema(training_examples,
  title: "Auto-inferred Program Schema",
  min_occurrence_ratio: 0.8  # Field must appear in 80% of examples to be required
)

IO.puts("✓ Schema inferred from #{length(training_examples)} examples")
IO.puts("  Inferred fields: #{inspect(Map.keys(inferred_schema.fields))}")

required_fields = Sinter.Schema.required_fields(inferred_schema)
optional_fields = Sinter.Schema.optional_fields(inferred_schema)
IO.puts("  Required fields: #{inspect(required_fields)}")
IO.puts("  Optional fields: #{inspect(optional_fields)}")
IO.puts("")

# ============================================================================
# 4. SCHEMA OPTIMIZATION FROM FAILURES
# ============================================================================

IO.puts("4. Schema Optimization from Failures")
IO.puts("------------------------------------")

# Simulate failure examples that would come from teleprompter optimization
failure_examples = [
  %{
    "question" => "Complex physics question",
    "answer" => "Detailed answer",
    "confidence" => 0.7,
    "sources" => ["Physics textbook"],  # New field not in original schema
    "uncertainty_score" => 0.3          # Another new field
  },
  %{
    "question" => "Another question",
    "answer" => "Another answer",
    "confidence" => 0.85,
    "sources" => ["Academic paper", "Wikipedia"],
    "verification_status" => "checked"  # Yet another new field
  }
]

# Optimize schema based on failures
case Sinter.DSPEx.optimize_schema_from_failures(qa_signature, failure_examples,
  relaxation_strategy: :moderate,
  add_missing_fields: true
) do
  {:ok, optimized_schema, suggestions} ->
    IO.puts("✓ Schema optimized based on failures")
    IO.puts("  Original fields: #{map_size(qa_signature.fields)}")
    IO.puts("  Optimized fields: #{map_size(optimized_schema.fields)}")
    IO.puts("  Suggestions:")
    Enum.each(suggestions, fn suggestion ->
      IO.puts("    - #{suggestion}")
    end)
  {:error, reason} ->
    IO.puts("✗ Optimization failed: #{reason}")
end
IO.puts("")

# ============================================================================
# 5. SCHEMA MERGING FOR COMPLEX PROGRAMS
# ============================================================================

IO.puts("5. Schema Merging for Complex Programs")
IO.puts("--------------------------------------")

# Create component schemas for a complex DSPy program
retrieval_schema = Sinter.Schema.define([
  {:query, :string, [required: true]},
  {:retrieved_docs, {:array, :string}, [required: true]},
  {:retrieval_score, :float, [required: true, gteq: 0.0, lteq: 1.0]}
], title: "Retrieval Component")

reasoning_schema = Sinter.Schema.define([
  {:context, {:array, :string}, [required: true]},
  {:reasoning_steps, {:array, :string}, [required: true]},
  {:intermediate_conclusions, {:array, :string}, [optional: true]}
], title: "Reasoning Component")

generation_schema = Sinter.Schema.define([
  {:final_answer, :string, [required: true]},
  {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]},
  {:supporting_evidence, {:array, :string}, [optional: true]}
], title: "Generation Component")

# Merge into a complete RAG pipeline schema
rag_pipeline_schema = Sinter.merge_schemas([
  retrieval_schema,
  reasoning_schema,
  generation_schema
], title: "RAG Pipeline Schema", strict: true)

IO.puts("✓ Merged RAG pipeline schema")
IO.puts("  Total fields: #{map_size(rag_pipeline_schema.fields)}")
IO.puts("  Schema title: #{rag_pipeline_schema.config.title}")
IO.puts("  Strict mode: #{rag_pipeline_schema.config.strict}")

# Validate a complete RAG pipeline output
rag_output = %{
  query: "What is machine learning?",
  retrieved_docs: ["ML is a subset of AI...", "Algorithms learn patterns..."],
  retrieval_score: 0.87,
  context: ["ML is a subset of AI...", "Algorithms learn patterns..."],
  reasoning_steps: [
    "Retrieved relevant documents about ML",
    "Identified key concepts",
    "Synthesized comprehensive answer"
  ],
  final_answer: "Machine learning is a subset of artificial intelligence...",
  confidence: 0.92,
  supporting_evidence: ["Academic definition", "Multiple sources confirm"]
}

{:ok, validated_rag} = Sinter.Validator.validate(rag_pipeline_schema, rag_output)
IO.puts("✓ RAG pipeline output validated")
IO.puts("  Confidence: #{validated_rag.confidence}")
IO.puts("  Steps: #{length(validated_rag.reasoning_steps)}")
IO.puts("")

# ============================================================================
# 6. LLM PROVIDER OPTIMIZATION
# ============================================================================

IO.puts("6. LLM Provider Optimization")
IO.puts("----------------------------")

# Prepare schema for different LLM providers
openai_config = Sinter.DSPEx.prepare_for_llm(qa_signature, :openai)
IO.puts("✓ OpenAI configuration prepared")
IO.puts("  Function calling compatible: #{openai_config.metadata.function_calling_compatible}")
IO.puts("  Supports strict mode: #{openai_config.metadata.supports_strict_mode}")

anthropic_config = Sinter.DSPEx.prepare_for_llm(qa_signature, :anthropic)
IO.puts("✓ Anthropic configuration prepared")
IO.puts("  Provider: #{anthropic_config.provider}")

# Show the actual JSON schemas
IO.puts("\n📋 OpenAI JSON Schema sample:")
openai_json = Jason.encode!(openai_config.json_schema, pretty: true)
IO.puts(String.slice(openai_json, 0, 200) <> "...")

IO.puts("\n📋 Anthropic JSON Schema sample:")
anthropic_json = Jason.encode!(anthropic_config.json_schema, pretty: true)
IO.puts(String.slice(anthropic_json, 0, 200) <> "...")
IO.puts("")

IO.puts("=== DSPy Integration Examples Complete ===")
