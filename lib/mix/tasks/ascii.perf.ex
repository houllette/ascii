defmodule Mix.Tasks.Ascii.Perf do
  @shortdoc "Times every piece's frames against upstream's budgets"
  @moduledoc """
  Plays each piece as upstream's `scripts/check.ts` times it, a fresh
  instance stepped every `1/fps` seconds from 0 to 6, and prints the average
  and worst time a frame took (the first frame aside), against upstream's
  budgets: text pieces 4 ms on average and 30 ms at worst, scenes 10 ms on
  average and 40 ms at worst.

      mix ascii.perf                # every piece
      mix ascii.perf donut night-coast

  A piece more than three times over its average budget is marked `SLOW`;
  `mix test --only perf` fails on those.
  """
  use Mix.Task

  @doc "Times a piece: `%{slug, category, avg, max, init, budget, worst}` in ms."
  @spec measure(slug :: String.t(), module :: module()) :: map()
  def measure(slug, mod) do
    meta = mod.meta()
    env = %Ascii.Env{cols: meta.cols, rows: meta.rows, color?: meta.palette != nil}
    {init_us, state} = :timer.tc(fn -> mod.init(meta.options) end)
    step = if meta.fps > 0, do: 1 / meta.fps, else: 0.5

    times =
      0
      |> Stream.iterate(&(&1 + 1))
      |> Stream.map(&(Ascii.JSMath.round(&1 * step * 1.0e6) / 1.0e6))
      |> Enum.take_while(&(&1 <= 6))

    {ms, _} =
      Enum.map_reduce(times, state, fn t, state ->
        {us, {io, _colors, state}} =
          :timer.tc(fn -> mod.frame(state, t, %{env | now: ~U[2026-03-14 15:09:26.535Z]}) end)

        IO.iodata_to_binary(io)
        {us / 1000, state}
      end)

    ms = tl(ms)
    {budget, worst} = if meta.category == :scenes, do: {10, 40}, else: {4, 30}

    %{
      slug: slug,
      category: meta.category,
      avg: if(ms == [], do: 0.0, else: Enum.sum(ms) / length(ms)),
      max: Enum.max(ms, fn -> 0.0 end),
      init: init_us / 1000,
      budget: budget,
      worst: worst
    }
  end

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    pieces =
      if args == [],
        do: Ascii.Registry.all(),
        else: Enum.map(args, &{&1, module!(&1)})

    Mix.shell().info(
      String.pad_trailing("piece", 22) <>
        String.pad_trailing("category", 12) <> "     avg      max     init"
    )

    for {slug, mod} <- pieces do
      r = measure(slug, mod)

      flag =
        if r.avg > 3 * r.budget, do: "  SLOW", else: if(r.avg > r.budget, do: "  over", else: "")

      Mix.shell().info(
        String.pad_trailing(slug, 22) <>
          String.pad_trailing(to_string(r.category), 12) <>
          fmt(r.avg) <> fmt(r.max) <> fmt(r.init) <> flag
      )
    end
  end

  # A registered slug, or a piece not registered yet, by the naming rule
  # (`ruled-mountains` is Ascii.Pieces.RuledMountains).
  defp module!(slug) do
    case Ascii.resolve(slug) do
      {:ok, mod} ->
        mod

      {:error, :unknown_piece} ->
        camel = slug |> String.split("-") |> Enum.map_join(&String.capitalize/1)
        mod = Module.concat(Ascii.Pieces, camel)
        if Code.ensure_loaded?(mod), do: mod, else: Mix.raise("unknown piece #{inspect(slug)}")
    end
  end

  defp fmt(ms), do: String.pad_leading(:erlang.float_to_binary(ms * 1.0, decimals: 2), 9)
end
