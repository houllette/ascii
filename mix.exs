defmodule Ascii.MixProject do
  use Mix.Project

  def project do
    [
      app: :ascii,
      version: "0.4.1",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      test_ignore_filters: [&String.starts_with?(&1, "test/fixtures/")],
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:ex_unit, :mix]
      ],
      usage_rules: [file: "AGENTS.md", usage_rules: :all],
      name: "Ascii",
      description:
        "ASCII-art components for Elixir: native diagrams, live-data widgets and " <>
          "exact ascii.rest animations for Phoenix LiveView, terminal UIs and Nerves.",
      source_url: "https://github.com/houllette/ascii",
      package: package(),
      docs: docs()
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/houllette/ascii",
        "ascii.rest" => "https://ascii.rest"
      },
      files:
        ~w(lib priv/static/ascii_hook.js mix.exs README.md guides LICENSE THIRD_PARTY_NOTICES.md PORTING.md PORT_STATUS.md UPSTREAM.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/migrating-to-ascii.md",
        "guides/components.md",
        "guides/diagrams.md",
        "guides/phoenix.md",
        "guides/terminal.md",
        "guides/ex_ratatui.md",
        "guides/livebook.md",
        "guides/nerves.md",
        "guides/custom-rendering.md",
        "guides/writing-pieces.md",
        "PORTING.md",
        "PORT_STATUS.md",
        "UPSTREAM.md",
        "THIRD_PARTY_NOTICES.md",
        "LICENSE"
      ],
      groups_for_extras: [
        Guides: ~r"^guides/",
        "About the port": ~w(PORTING.md PORT_STATUS.md UPSTREAM.md THIRD_PARTY_NOTICES.md LICENSE)
      ],
      groups_for_modules:
        [
          Core: [
            Ascii,
            Ascii.Piece,
            Ascii.Meta,
            Ascii.Env,
            Ascii.Frame,
            Ascii.Ink,
            Ascii.Parts,
            Ascii.Animation,
            Ascii.Options
          ],
          Renderers: [
            Ascii.Render.Text,
            Ascii.Render.ANSI,
            Ascii.Render.HTML,
            Ascii.Render.SVG,
            Ascii.Compose,
            Ascii.Player
          ],
          "Live data": [Ascii.BEAM, Ascii.Telemetry],
          Diagrams: [Ascii.Diagram, Ascii.Diagram.Layout, Ascii.Diagram.Viewport, Ascii.Mermaid],
          Phoenix: [
            Ascii.Phoenix,
            Ascii.Phoenix.Components,
            Ascii.Phoenix.PlayerLive,
            Ascii.Phoenix.PlayerComponent
          ],
          ExRatatui: [Ascii.ExRatatui, Ascii.ExRatatui.Viewer]
        ] ++
          piece_groups() ++
          [Internals: [Ascii.JSMath, Ascii.Int32, Ascii.Registry, ~r/^Ascii\.Kit\./]],
      nest_modules_by_prefix: [
        Ascii.Pieces,
        Ascii.Kit,
        Ascii.Render,
        Ascii.Phoenix,
        Ascii.ExRatatui
      ]
    ]
  end

  # One group of pieces a category, in upstream's order, read from each
  # piece's meta in its source.
  @categories ~w(scenes shapes space physics nature creatures objects generative effects ui data type logos distros)
  defp piece_groups do
    pieces =
      for file <- Path.wildcard("lib/ascii/pieces/*.ex"),
          source = File.read!(file),
          [_, mod] <- [Regex.run(~r/defmodule ([\w.]+) do/, source)],
          [_, category] <- [Regex.run(~r/category: :(\w+)/, source)],
          do: {category, Module.concat([mod])}

    by_category = Enum.group_by(pieces, &elem(&1, 0), &elem(&1, 1))

    for category <- @categories, mods = Map.get(by_category, category, []), mods != [] do
      {:"Pieces: #{category}", Enum.sort(mods)}
    end
  end

  def cli do
    [preferred_envs: [precommit: :test]]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger] ++ test_applications(Mix.env())
    ]
  end

  # The SVG tests read what they draw back as XML.
  defp test_applications(:test), do: [:xmerl]
  defp test_applications(_env), do: []

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:tidewave, "~> 0.8", only: :dev},
      {:bandit, "~> 1.0", only: :dev},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40", only: [:dev, :test], runtime: false},
      {:usage_rules, "~> 1.2", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:phoenix_live_view, "~> 1.1", optional: true},
      {:telemetry, "~> 1.0", optional: true},
      {:ex_ratatui, "~> 0.17", optional: true},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp aliases do
    [
      tidewave:
        "run --no-halt -e 'Agent.start(fn -> Bandit.start_link(plug: Tidewave, port: 4000) end)'",
      precommit: [
        "deps.unlock --check-unused",
        # The audits read mix.lock only; they MUST precede compile.
        "hex.audit",
        "deps.audit",
        "compile --warnings-as-errors",
        "format",
        "credo --strict",
        "usage_rules.sync --yes",
        "xref graph --label compile-connected --fail-above 0",
        "docs --warnings-as-errors",
        "test --warnings-as-errors"
      ]
    ]
  end
end
