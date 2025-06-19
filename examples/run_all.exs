#!/usr/bin/env elixir

# Run All Sinter Examples
# Executes all example files in sequence with full output display

IO.puts("🚀 Running All Sinter Examples")
IO.puts("===============================")
IO.puts("")

# List of examples in recommended order
examples = [
  {"basic_usage.exs", "Basic Usage Examples"},
  {"readme_comprehensive.exs", "Complete README Coverage"},
  {"json_schema_generation.exs", "JSON Schema Generation"},
  {"advanced_validation.exs", "Advanced Validation Patterns"},
  {"dspy_integration.exs", "DSPy Integration Examples"}
]

# Track results using Agent for state management
{:ok, results_agent} = Agent.start_link(fn -> [] end)

Enum.each(examples, fn {file, description} ->
  IO.puts("\n" <> String.duplicate("=", 80))
  IO.puts("📄 RUNNING: #{description}")
  IO.puts("   File: #{file}")
  IO.puts(String.duplicate("=", 80))

  start_time = System.monotonic_time(:millisecond)

  try do
    # Execute the example file and capture output
    {output, exit_code} = System.cmd("elixir", [file], stderr_to_stdout: true)

    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time

    case exit_code do
      0 ->
        # Show the actual output from the example
        IO.puts(output)
        IO.puts("\n✅ COMPLETED SUCCESSFULLY (#{duration}ms)")
        Agent.update(results_agent, fn results -> results ++ [{file, :success, duration}] end)
      _ ->
        # Show error output for failures
        IO.puts("❌ EXECUTION FAILED (#{duration}ms)")
        IO.puts("\nOutput:")
        IO.puts(output)
        Agent.update(results_agent, fn results -> results ++ [{file, :failed, duration}] end)
    end
  rescue
    error ->
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      IO.puts("💥 SCRIPT CRASHED (#{duration}ms)")
      IO.puts("Exception: #{inspect(error)}")
      Agent.update(results_agent, fn results -> results ++ [{file, :crashed, duration}] end)
  end

  IO.puts(String.duplicate("-", 80))
end)

# Get final results
results = Agent.get(results_agent, & &1)
Agent.stop(results_agent)

# Summary report
IO.puts("\n" <> String.duplicate("=", 80))
IO.puts("📊 FINAL SUMMARY REPORT")
IO.puts(String.duplicate("=", 80))

successful = Enum.count(results, fn {_, status, _} -> status == :success end)
failed = Enum.count(results, fn {_, status, _} -> status == :failed end)
crashed = Enum.count(results, fn {_, status, _} -> status == :crashed end)
total = length(results)

IO.puts("Total examples: #{total}")
IO.puts("✅ Successful: #{successful}")
IO.puts("❌ Failed: #{failed}")
IO.puts("💥 Crashed: #{crashed}")
IO.puts("")

if successful == total do
  IO.puts("🎉 ALL EXAMPLES PASSED!")
  IO.puts("Sinter is working perfectly across all functionality areas.")
else
  IO.puts("⚠️  Results breakdown:")

  Enum.each(results, fn {file, status, duration} ->
    case status do
      :success -> IO.puts("   ✅ #{file} (#{duration}ms)")
      :failed -> IO.puts("   ❌ #{file} (#{duration}ms)")
      :crashed -> IO.puts("   💥 #{file} (#{duration}ms)")
    end
  end)
end

IO.puts("")

# Performance summary
total_time = Enum.sum(Enum.map(results, fn {_, _, duration} -> duration end))
IO.puts("⏱️  Total execution time: #{total_time}ms")

avg_time = if total > 0, do: Float.round(total_time / total, 1), else: 0
IO.puts("📈 Average time per example: #{avg_time}ms")
IO.puts("")

# Next steps
IO.puts("🔗 NEXT STEPS")
IO.puts("=============")
IO.puts("• Review any failed examples above")
IO.puts("• Check individual example files for detailed explanations")
IO.puts("• Read examples/README.md for troubleshooting tips")
IO.puts("• Explore the main project README.md for full documentation")
IO.puts("")

if successful == total do
  System.halt(0)
else
  System.halt(1)
end
