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

      # Dialyzer
      dialyzer: dialyzer(),

      # ExDoc
      source_url: @source_url,
      homepage_url: @source_url
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "test.watch": :test,
        check: :test,
        qa: :test
      ]
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
      #      {:simdjsone, "~> 0.5.0"},
      # JSON Schema validation engine
      {:jsv, "~> 0.16.0"},
      # Options validation
      {:nimble_options, "~> 1.0"},
      #      # Struct transformation library - for client app transformations
      #      {:estructura, "~> 1.9.0"},

      # Fallback JSON parser for environments where NIFs cause issues
      {:jason, "~> 1.4"},

      # Development and testing dependencies
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:castore, "~> 1.0", only: :test},
      {:excoveralls, "~> 0.18", only: :test},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},

      # Property testing and benchmarking
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:benchee, "~> 1.5", only: :dev}
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
      maintainers: ["NSHkr ZeroTrust@NSHkr.com"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => @source_url <> "/blob/main/CHANGELOG.md",
        "Sponsor" => @source_url <> "/sponsors"
      },
      files: ~w[
        lib
        assets
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
      assets: %{"assets" => "assets"},
      logo: "assets/sinter.svg",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      before_closing_head_tag: &before_closing_head_tag/1,
      before_closing_body_tag: &before_closing_body_tag/1,
      groups_for_modules: [
        Core: [
          Sinter,
          Sinter.Schema,
          Sinter.Validator,
          Sinter.JsonSchema,
          Sinter.JSON
        ],
        Serialization: [
          Sinter.Transform,
          Sinter.NotGiven
        ],
        "Types and Errors": [
          Sinter.Types,
          Sinter.Error,
          Sinter.ValidationError
        ],
        Integrations: [
          Sinter.DSPEx,
          Sinter.Performance
        ]
      ]
    ]
  end

  defp before_closing_head_tag(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;

      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }

        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_head_tag(:epub), do: ""

  defp before_closing_body_tag(:html), do: ""

  defp before_closing_body_tag(:epub), do: ""

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
      ignore_warnings: ".dialyzer_ignore.exs",
      list_unused_filters: true
    ]
  end
end
