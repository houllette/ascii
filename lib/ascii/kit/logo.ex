defmodule Ascii.Kit.Logo do
  @moduledoc """
  A language's logo, glinting now and then: every upstream logo piece.

  A glint crosses the logo's ink, leaning like a slash, every `shine` seconds
  (0 keeps it still). Where it is bright, solid characters turn to slashes,
  and on a canvas the cells it passes take the lifted colours.

  A logo piece holds its meta and drawings (see `Ascii.Kit.Mark`) and
  hands `init/1` and `frame/3` to `init/5` and `frame/3` here.
  """

  alias Ascii.{Env, JSMath, Meta}
  alias Ascii.Kit.Mark

  # Seconds before the first glint, and for one to cross; half its width in
  # cells; cells it shifts left a row down; what it turns to slashes (thin
  # edges keep their shape).
  @start 0.5
  @pass 2
  @half 5
  @lean 0.9
  @solid ~c"8dbqpPYOo0"

  @doc "Precomputes from the piece's meta, its `shine` option and drawings."
  @spec init(
          meta :: Meta.t(),
          shine :: number(),
          mono :: String.t(),
          art :: String.t(),
          ink :: String.t()
        ) :: map()
  def init(%Meta{cols: cols, rows: rows} = meta, shine, mono, art, ink) do
    mono = Mark.picture(mono, cols)
    art = Mark.picture(art, cols)
    every = if shine > 0, do: max(shine, @pass + 0.5), else: 0

    # The glint crosses the logo's ink, edge to edge, rather than the whole frame.
    leans =
      for pic <- [mono, art],
          y <- 0..(rows - 1),
          x <- 0..(cols - 1),
          Mark.at(pic, x, y) != " ",
          do: x + @lean * y

    {lo, hi} = Enum.min_max(leans)

    %{
      meta: meta,
      n: Mark.per_variant(meta),
      mono: mono,
      art: art,
      ink: Mark.picture(ink, cols),
      every: every,
      lo: lo,
      span: hi - lo + 2 * @half
    }
  end

  @doc "The logo at `t`."
  @spec frame(state :: map(), t :: float(), env :: Env.t()) :: {iodata(), binary() | nil, map()}
  def frame(%{meta: %{cols: cols, rows: rows}} = state, t, %Env{paper: paper, color?: color?}) do
    pic = if color?, do: state.art, else: state.mono
    since = t - @start

    at =
      if state.every != 0 and since >= 0,
        do: state.lo - @half + state.span * JSMath.mod(since, state.every) / @pass

    cells =
      for y <- 0..(rows - 1) do
        for x <- 0..(cols - 1) do
          ch = Mark.at(pic, x, y)

          if ch == " ", do: {ch, 0}, else: inked(state, ch, at, x, y, paper, color?)
        end
      end

    text = cells |> Enum.map(fn row -> Enum.map(row, &elem(&1, 0)) end) |> Enum.intersperse(?\n)
    colors = if color?, do: IO.iodata_to_binary(for row <- cells, {_, c} <- row, do: c)
    {text, colors, state}
  end

  defp inked(state, ch, at, x, y, paper, color?) do
    k = glint(at, x, y)
    ch = if k > 0.55 and :binary.first(ch) in @solid, do: "/", else: ch
    level = if k > 0.6, do: 2, else: if(k > 0.25, do: 1, else: 0)
    {ch, if(color?, do: Mark.index(state.n, paper, level, Mark.at(state.ink, x, y)), else: 0)}
  end

  # No glint (upstream's -Infinity) lights nothing.
  defp glint(nil, _x, _y), do: 0

  defp glint(at, x, y) do
    d = abs(x + @lean * y - at)
    k = if d < @half, do: 1 - d / @half, else: 0
    k * k * (3 - 2 * k)
  end
end
