defmodule Sinter.Integration.DSPExTest do
  use ExUnit.Case, async: true

  alias Sinter.{JsonSchema, Schema, Validator}

  @moduletag :integration

  describe "DSPEx teleprompter scenarios" do
    test "MIPRO-style optimization workflow" do
      # Simulate MIPRO analyzing failed examples
      failed_examples = [
        %{"name" => "Alice", "age" => 30, "score" => 85.5},
        %{"name" => "Bob", "age" => 25, "score" => 92.1},
        %{"name" => "Charlie", "age" => 35, "score" => 78.9}
      ]

      # Step 1: Infer optimized schema
      optimized_schema = Sinter.infer_schema(failed_examples)

      # Step 2: Generate LLM-compatible JSON Schema
      openai_schema = JsonSchema.for_provider(optimized_schema, :openai)

      # Step 3: Validate that schema works with new data
      new_llm_output = %{"name" => "Diana", "age" => 28, "score" => 88.7}

      assert {:ok, validated} = Validator.validate(optimized_schema, new_llm_output)
      assert validated[:name] == "Diana"
      assert validated[:age] == 28
      assert validated[:score] == 88.7

      # Verify JSON Schema is LLM-ready
      assert openai_schema["additionalProperties"] == false
      assert "name" in openai_schema["required"]
      assert "age" in openai_schema["required"]
      assert "score" in openai_schema["required"]
    end

    test "signature composition for complex programs" do
      # Define component signatures
      input_schema =
        Schema.define([
          {:query, :string, [required: true, min_length: 1]},
          {:context, {:array, :string}, [optional: true]}
        ])

      output_schema =
        Schema.define([
          {:answer, :string, [required: true]},
          {:confidence, :float, [required: true, gteq: 0.0, lteq: 1.0]},
          {:sources, {:array, :string}, [optional: true]}
        ])

      # Compose into program signature
      program_schema = Sinter.merge_schemas([input_schema, output_schema])

      # Test full program validation
      program_data = %{
        "query" => "What is the capital of France?",
        "context" => ["France is a country in Europe"],
        "answer" => "Paris",
        "confidence" => 0.95,
        "sources" => ["encyclopedia"]
      }

      assert {:ok, validated} = Validator.validate(program_schema, program_data)
      assert validated[:query] == "What is the capital of France?"
      assert validated[:answer] == "Paris"
      assert validated[:confidence] == 0.95
    end

    test "batch optimization with streaming validation" do
      # Simulate teleprompter optimizing multiple examples
      base_schema =
        Schema.define([
          {:input, :string, [required: true]},
          {:output, :string, [required: true]}
        ])

      # Large batch of training examples
      training_examples =
        Stream.map(1..1_000, fn i ->
          %{"input" => "prompt_#{i}", "output" => "response_#{i}"}
        end)

      # Stream validation for memory efficiency
      validation_results = Validator.validate_stream(base_schema, training_examples)

      # Count successful validations
      success_count =
        validation_results
        |> Stream.filter(&match?({:ok, _}, &1))
        |> Enum.count()

      assert success_count == 1_000
    end

    test "error handling with LLM context" do
      schema =
        Schema.define([
          {:name, :string, [required: true, min_length: 2]},
          {:email, :string, [required: true, format: ~r/@/]}
        ])

      # Simulate bad LLM response
      bad_llm_response = %{"name" => "A", "email" => "invalid-email"}
      original_prompt = "Generate a user profile with valid name and email"

      {:error, errors} = Validator.validate(schema, bad_llm_response)

      # Enhance errors with LLM context for debugging
      enhanced_errors =
        Enum.map(errors, fn error ->
          Sinter.Error.with_llm_context(error, bad_llm_response, original_prompt)
        end)

      # Verify context is available for debugging
      name_error = Enum.find(enhanced_errors, &(&1.path == [:name]))
      email_error = Enum.find(enhanced_errors, &(&1.path == [:email]))

      assert name_error.context.llm_response == bad_llm_response
      assert name_error.context.prompt == original_prompt
      assert email_error.context.llm_response == bad_llm_response
      assert email_error.context.prompt == original_prompt
    end
  end
end
