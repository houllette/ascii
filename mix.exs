defmodule AsciiArt.MixProject do
  use Mix.Project

  def project do
    [
      app: :ascii_art,
      version: "0.2.2",
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
      name: "AsciiArt",
      description:
        "ASCII-art UI components for Elixir: live-data widgets and animated art for " <>
          "Phoenix LiveView, terminal UIs and Nerves. An exact port of ascii.rest.",
      source_url: "https://github.com/houllette/ascii_art",
      package: package(),
      docs: docs()
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => "https://github.com/houllette/ascii_art",
        "ascii.rest" => "https://ascii.rest"
      },
      files:
        ~w(lib priv/static/ascii_art_hook.js mix.exs README.md LICENSE THIRD_PARTY_NOTICES.md PORTING.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "guides/getting-started.md",
        "guides/components.md",
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
            AsciiArt,
            AsciiArt.Piece,
            AsciiArt.Meta,
            AsciiArt.Env,
            AsciiArt.Frame,
            AsciiArt.Ink,
            AsciiArt.Parts,
            AsciiArt.Animation,
            AsciiArt.Options
          ],
          Renderers: [
            AsciiArt.Render.Text,
            AsciiArt.Render.ANSI,
            AsciiArt.Render.HTML,
            AsciiArt.Render.SVG,
            AsciiArt.Compose,
            AsciiArt.Player
          ],
          "Live data": [AsciiArt.BEAM, AsciiArt.Telemetry],
          Phoenix: [
            AsciiArt.Phoenix,
            AsciiArt.Phoenix.Components,
            AsciiArt.Phoenix.PlayerLive,
            AsciiArt.Phoenix.PlayerComponent
          ],
          ExRatatui: [AsciiArt.ExRatatui, AsciiArt.ExRatatui.Viewer]
        ] ++
          piece_groups() ++
          [Internals: [AsciiArt.JSMath, AsciiArt.Int32, AsciiArt.Registry, ~r/^AsciiArt\.Kit\./]],
      nest_modules_by_prefix: [
        AsciiArt.Pieces,
        AsciiArt.Kit,
        AsciiArt.Render,
        AsciiArt.Phoenix,
        AsciiArt.ExRatatui
      ]
    ]
  end

  # One group of pieces a category, in upstream's order, read from each
  # piece's meta in its source.
  @categories ~w(scenes shapes space physics nature creatures objects generative effects ui data type logos distros)
  defp piece_groups do
    pieces =
      for file <- Path.wildcard("lib/ascii_art/pieces/*.ex"),
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
