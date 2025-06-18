#!/usr/bin/env elixir

# Simple development workflow script
# Usage: elixir dev.exs [check|watch|help]

defmodule DevRunner do
  @moduledoc """
  Simple development workflow with visual feedback.
  """

  # ANSI colors for output
  @green "\e[32m"
  @red "\e[31m"
  @yellow "\e[33m"
  @blue "\e[34m"
  @reset "\e[0m"
  @bold "\e[1m"

  def main(args) do
    case args do
      [] -> run_check()
      ["check"] -> run_check()
      ["watch"] -> run_watch()
      ["help"] -> show_help()
      _ -> show_help()
    end
  end

  def run_check do
    print_header("🔍 Running Development Checks")

    checks = [
      {"Format", "mix format --check-formatted", &format_check/1},
      {"Compile", "mix compile", &compile_check/1},
      {"Credo", "mix credo --format=oneline", &credo_check/1},
      {"Tests", "mix test", &test_check/1},
      {"Dialyzer", "mix dialyzer --quiet", &dialyzer_check/1}
    ]

    results = Enum.map(checks, fn {name, cmd, parser} ->
      result = run_command(cmd)
      status = parser.(result)
      print_result(name, status)
      {name, status}
    end)

    print_summary(results)
  end

  def run_watch do
    print_header("👀 Starting Development Watcher")
    IO.puts("#{@blue}Watching for file changes... Press Ctrl+C to stop#{@reset}")
    IO.puts("")

    # Use mix test.watch with custom runner
    System.cmd("mix", ["test.watch", "--clear"], into: IO.stream())
  end

  defp run_command(cmd) do
    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _} -> {:error, output}
    end
  end

  defp format_check({:ok, ""}), do: :ok
  defp format_check({:ok, _}), do: :warning  # Some output means formatting issues
  defp format_check({:error, _output}), do: :warning  # Format issues are warnings, not errors

  defp compile_check({:ok, output}) do
    cond do
      String.contains?(output, "warning:") -> :warning
      true -> :ok
    end
  end
  defp compile_check({:error, _}), do: :error

  defp credo_check({:ok, output}) do
    cond do
      String.contains?(output, "found no issues") -> :ok
      String.contains?(output, "found") -> :warning
      true -> :ok
    end
  end
  defp credo_check({:error, _}), do: :error

  defp test_check({:ok, output}) do
    cond do
      String.contains?(output, "0 failures") -> :ok
      String.contains?(output, " failures") -> :error
      String.contains?(output, "failure") -> :error
      String.contains?(output, "Finished") -> :ok  # Tests completed successfully
      true -> :ok
    end
  end
  defp test_check({:error, _}), do: :error

  defp dialyzer_check({:ok, output}) do
    cond do
      String.contains?(output, "done in") -> :ok
      String.contains?(output, "warnings were emitted") -> :warning
      true -> :ok
    end
  end
  defp dialyzer_check({:error, output}) do
    if String.contains?(output, "warnings were emitted") do
      :warning  # Dialyzer warnings are non-critical
    else
      :error
    end
  end

  defp print_header(title) do
    IO.puts("")
    IO.puts("#{@bold}#{@blue}#{title}#{@reset}")
    IO.puts("#{String.duplicate("=", String.length(title))}")
    IO.puts("")
  end

  defp print_result(name, status) do
    {color, icon, message} = case status do
      :ok -> {@green, "✅", "PASS"}
      :warning -> {@yellow, "⚠️ ", "WARN"}
      :error -> {@red, "❌", "FAIL"}
    end

    padded_name = String.pad_trailing(name, 10)
    IO.puts("#{color}#{icon} #{padded_name} #{message}#{@reset}")
  end

  defp print_summary(results) do
    IO.puts("")

    passed = Enum.count(results, fn {_, status} -> status == :ok end)
    warned = Enum.count(results, fn {_, status} -> status == :warning end)
    failed = Enum.count(results, fn {_, status} -> status == :error end)

    overall_status = cond do
      failed > 0 -> :error
      warned > 0 -> :warning
      true -> :ok
    end

    {color, icon, message} = case overall_status do
      :ok -> {@green, "🎉", "All checks passed!"}
      :warning -> {@yellow, "⚠️", "Some warnings found"}
      :error -> {@red, "💥", "Some checks failed"}
    end

    IO.puts("#{@bold}Summary:#{@reset}")
    IO.puts("#{color}#{icon} #{message}#{@reset}")
    IO.puts("#{@green}Passed: #{passed}#{@reset} | #{@yellow}Warned: #{warned}#{@reset} | #{@red}Failed: #{failed}#{@reset}")
    IO.puts("")

    if overall_status != :ok do
      IO.puts("#{@blue}💡 Quick fixes:#{@reset}")
      if failed > 0 or warned > 0 do
        IO.puts("  • Format code: #{@bold}mix format#{@reset}")
        IO.puts("  • Check details: #{@bold}mix credo#{@reset}")
        IO.puts("  • Run tests: #{@bold}mix test#{@reset}")
      end
      IO.puts("")
    end
  end

  defp show_help do
    IO.puts("""
    #{@bold}#{@blue}Sinter Development Workflow#{@reset}

    #{@bold}Usage:#{@reset}
      elixir dev.exs [command]

    #{@bold}Commands:#{@reset}
      #{@green}check#{@reset}    Run all development checks (default)
      #{@green}watch#{@reset}    Start file watcher with auto-testing
      #{@green}help#{@reset}     Show this help message

    #{@bold}What gets checked:#{@reset}
      ✅ Code formatting (mix format)
      ✅ Compilation (mix compile)
      ✅ Code quality (mix credo)
      ✅ Tests (mix test)

    #{@bold}Examples:#{@reset}
      elixir dev.exs           # Run all checks
      elixir dev.exs check     # Run all checks
      elixir dev.exs watch     # Start watcher
    """)
  end
end

# Run the main function
DevRunner.main(System.argv())
