defmodule Sinter.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/your-org/sinter"

  def project do
    [
      app: :sinter,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),

      # Documentation
      name: "Sinter",
      description: description(),
      package: package(),
      docs: docs(),

      # Testing and Analysis
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ],

      # Dialyzer
      dialyzer: dialyzer(),

      # ExDoc
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      # Core libraries for enhanced functionality
      {:jason, "~> 1.4"},                 # Fast JSON parsing (using jason instead of simdjsone for now)
      {:ex_json_schema, "~> 0.10.2"},     # Robust JSON Schema validation

      # Optional integration libraries (commented out for now)
      # {:estructura, "~> 1.8", optional: true},  # Advanced nested patterns

      # Development and Testing
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # Testing utilities
      {:stream_data, "~> 1.0", only: [:dev, :test]},
      {:benchee, "~> 1.3", only: :dev}
    ]
  end

  defp description do
    """
    Unified schema definition, validation, and JSON generation for Elixir.

    Sinter is a focused, high-performance schema validation library designed
    specifically for dynamic frameworks like DSPy. It distills complex validation
    APIs into a single, powerful, and unified engine.
    """
  end

  defp package do
    [
      name: "sinter",
      maintainers: ["Your Name"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @source_url <> "/blob/main/CHANGELOG.md",
        "Sponsor" => @source_url <> "/sponsors"
      },
      files: ~w[
        lib
        priv
        mix.exs
        README.md
        CHANGELOG.md
        LICENSE
      ]
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      formatters: ["html"],
      extras: [
        "README.md",
        "CHANGELOG.md": [title: "Changelog"],
        "docs/getting_started.md": [title: "Getting Started"],
        "docs/migration.md": [title: "Migration from Elixact"],
        "docs/dspy_integration.md": [title: "DSPy Integration"],
        "docs/performance.md": [title: "Performance Guide"]
      ],
      groups_for_extras: [
        "Guides": ~r/docs\/.*/
      ],
      groups_for_modules: [
        "Core": [
          Sinter,
          Sinter.Schema,
          Sinter.Validator,
          Sinter.JsonSchema
        ],
        "Types and Errors": [
          Sinter.Types,
          Sinter.Error,
          Sinter.ValidationError
        ],
        "Internals": [
          Sinter.Schema.Compiler,
          Sinter.Validator.Engine,
          Sinter.JsonSchema.Generator
        ]
      ]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_unit, :mix],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      flags: [
        :error_handling,
        :race_conditions,
        :underspecs,
        :unknown,
        :unmatched_returns
      ],
      ignore_warnings: ".dialyzer_ignore.exs",
      list_unused_filters: true
    ]
  end
end
