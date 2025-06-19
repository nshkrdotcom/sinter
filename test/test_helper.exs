ExUnit.start()

# Configure ExUnit for comprehensive testing
ExUnit.configure(
  exclude: [:skip, :pending, :benchmark, :memory],
  formatters: [ExUnit.CLIFormatter],
  max_failures: 10,
  seed: 0,
  timeout: 30_000,
  trace: false
)

# Custom test helpers
defmodule SinterTestHelpers do
  @moduledoc """
  Helper functions for Sinter tests.
  """

  import ExUnit.Assertions
  alias Sinter.{Error, Schema, Validator}

  @doc """
  Creates a simple test schema for common test scenarios.
  """
  def simple_schema(opts \\ []) do
    fields =
      Keyword.get(opts, :fields, [
        {:name, :string, [required: true, min_length: 2]},
        {:age, :integer, [optional: true, gt: 0, lt: 150]},
        {:email, :string, [optional: true, format: ~r/.+@.+/]}
      ])

    schema_opts = Keyword.drop(opts, [:fields])
    Schema.define(fields, schema_opts)
  end

  @doc """
  Asserts that validation fails and returns the first error with given code.
  """
  def assert_validation_error(schema, data, expected_code, opts \\ []) do
    case Validator.validate(schema, data, opts) do
      {:ok, _} ->
        flunk("Expected validation to fail with #{expected_code}, but it succeeded")

      {:error, errors} ->
        matching_error = Enum.find(errors, &(&1.code == expected_code))

        if matching_error do
          matching_error
        else
          codes = Enum.map(errors, & &1.code)
          flunk("Expected error code #{expected_code}, got: #{inspect(codes)}")
        end
    end
  end

  @doc """
  Asserts that a validation succeeds and returns the validated data.
  """
  def assert_validation_success(schema, data, opts \\ []) do
    case Validator.validate(schema, data, opts) do
      {:ok, validated} ->
        validated

      {:error, errors} ->
        formatted_errors = Error.format_errors(errors)
        flunk("Expected validation to succeed, but got errors:\n#{formatted_errors}")
    end
  end

  @doc """
  Creates test data for performance benchmarks.
  """
  def create_benchmark_data(size, schema_fields \\ nil) do
    fields =
      schema_fields ||
        [
          {:id, :integer, [required: true]},
          {:name, :string, [required: true]},
          {:active, :boolean, [optional: true, default: true]}
        ]

    schema = Schema.define(fields)

    data =
      Enum.map(1..size, fn i ->
        %{
          "id" => i,
          "name" => "item_#{i}",
          "active" => rem(i, 2) == 0
        }
      end)

    {schema, data}
  end

  @doc """
  Measures execution time of a function in microseconds.
  """
  def measure_time(fun) do
    start_time = System.monotonic_time(:microsecond)
    result = fun.()
    end_time = System.monotonic_time(:microsecond)

    {result, end_time - start_time}
  end

  @doc """
  Checks if the current test is tagged for benchmark or memory testing.
  """
  def benchmark_test? do
    ExUnit.configuration()[:exclude]
    |> Enum.any?(&(&1 in [:benchmark, :memory]))
    |> Kernel.not()
  end
end

# Make helpers available in all test files
# Note: Import SinterTestHelpers in individual test files as needed
