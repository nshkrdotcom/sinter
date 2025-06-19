defmodule Sinter.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/nshkrdotcom/sinter"

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
      aliases: aliases(),

      # Testing and Analysis
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "test.watch": :test,
        check: :test,
        qa: :test
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
      # Gift libraries (as specified in design docs)
      # Fast JSON parsing - the blazing fast gift library
      {:simdjsone, "~> 0.5.0"},
      # JSON Schema validation engine - the heavy lifting gift library
      {:ex_json_schema, "~> 0.10.2"},
      #      # Struct transformation library - for client app transformations
      #      {:estructura, "~> 1.9.0"},

      # Fallback JSON parser for environments where NIFs cause issues
      {:jason, "~> 1.4"},

      # Development and testing dependencies
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},

      # Property testing and benchmarking
      {:stream_data, "~> 1.1", only: [:dev, :test]},
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
      maintainers: ["nshkrdotcom"],
      licenses: ["MIT"],
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
        Guides: ~r/docs\/.*/
      ],
      groups_for_modules: [
        Core: [
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
        Internals: [
          Sinter.Schema.Compiler,
          Sinter.Validator.Engine,
          Sinter.JsonSchema.Generator
        ]
      ]
    ]
  end

  defp aliases do
    [
      # Quick checks
      check: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --strict",
        "test"
      ],

      # Quality assurance (fast check without Dialyzer)
      qa: ["check"],

      # Full QA with type checking (Dialyzer warnings allowed)
      "qa.full": ["check", "cmd echo 'Running Dialyzer (warnings allowed)...'"],

      # Test variations
      "test.watch": ["test.watch --clear"],
      "test.quick": ["test --exclude slow"],
      "test.all": ["test --include slow"]
    ]
  end

  defp dialyzer do
    [
      plt_add_apps: [:ex_unit, :mix],
      plt_core_path: "priv/plts",
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      flags: [
        :error_handling,
        :underspecs,
        :unknown,
        :unmatched_returns
      ],
      ignore_warnings: "dialyzer.ignore-warnings",
      list_unused_filters: true
    ]
  end
end
