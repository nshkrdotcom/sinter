defmodule Sinter.Performance.BatchValidationTest do
  use ExUnit.Case, async: true

  alias Sinter.{Schema, Validator}

  @moduletag :performance

  describe "batch validation performance" do
    test "validates large datasets efficiently" do
      schema =
        Schema.define([
          {:id, :integer, [required: true]},
          {:name, :string, [required: true, min_length: 1]},
          {:score, :float, [required: true, gteq: 0.0, lteq: 100.0]}
        ])

      # Create large dataset
      large_dataset =
        Enum.map(1..10_000, fn i ->
          %{
            "id" => i,
            "name" => "item_#{i}",
            "score" => :rand.uniform() * 100
          }
        end)

      {time_microseconds, {:ok, results}} =
        :timer.tc(fn ->
          Validator.validate_many(schema, large_dataset)
        end)

      # Performance assertions
      assert length(results) == 10_000
      # Under 1 second
      assert time_microseconds < 1_000_000

      # Verify average time per item
      avg_time_per_item = time_microseconds / 10_000
      # Under 100 microseconds per item
      assert avg_time_per_item < 100

      IO.puts(
        "Validated 10,000 items in #{time_microseconds / 1000}ms (#{Float.round(avg_time_per_item, 2)}μs per item)"
      )
    end

    test "stream validation memory efficiency" do
      schema = Schema.define([{:val, :integer, [required: true]}])

      # Monitor memory usage during stream processing
      :erlang.garbage_collect()
      {_, initial_memory} = :erlang.process_info(self(), :memory)

      # Process large stream
      result_count =
        1..50_000
        |> Stream.map(&%{"val" => &1})
        |> then(&Validator.validate_stream(schema, &1))
        |> Stream.filter(&match?({:ok, _}, &1))
        |> Enum.count()

      :erlang.garbage_collect()
      {_, final_memory} = :erlang.process_info(self(), :memory)

      memory_growth = final_memory - initial_memory
      memory_growth_mb = memory_growth / (1024 * 1024)

      assert result_count == 50_000
      # Less than 50MB growth
      assert memory_growth_mb < 50

      IO.puts(
        "Stream processed 50,000 items with #{Float.round(memory_growth_mb, 2)}MB memory growth"
      )
    end
  end

  describe "schema inference performance" do
    test "infers schema from large example sets efficiently" do
      # Create varied examples
      examples =
        Enum.map(1..1_000, fn i ->
          %{
            "id" => "item_#{i}",
            "score" => :rand.uniform() * 100,
            "active" => rem(i, 2) == 0,
            "tags" => Enum.map(1..3, &"tag_#{&1}")
          }
        end)

      {time_microseconds, schema} =
        :timer.tc(fn ->
          Sinter.infer_schema(examples)
        end)

      assert %Schema{} = schema
      # Under 500ms
      assert time_microseconds < 500_000

      fields = Schema.fields(schema)
      assert Map.has_key?(fields, :id)
      assert Map.has_key?(fields, :score)
      assert Map.has_key?(fields, :active)
      assert Map.has_key?(fields, :tags)

      IO.puts("Inferred schema from 1,000 examples in #{time_microseconds / 1000}ms")
    end
  end
end
