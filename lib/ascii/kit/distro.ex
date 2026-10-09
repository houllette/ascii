defmodule Ascii.Kit.Distro do
  @moduledoc """
  A Linux distribution's logo with a scan line running down it now and then:
  every upstream distro piece.

  Every `scan` seconds (0 keeps it still) a line two rows deep runs from the
  logo's first row to past its last, scrambling the characters it covers,
  with five rows of afterglow behind it; on a canvas those rows take the
  lifted colours.

  A distro piece holds its meta and drawings (see `Ascii.Kit.Mark`) and
  hands `init/1` and `frame/3` to `init/5` and `frame/3` here.
  """

  alias Ascii.{Env, Int32, JSMath, Meta}
  alias Ascii.Kit.Mark

  # Seconds before the first scan, and for one to run top to bottom; rows the
  # line scrambles, and rows of afterglow behind it; what it scrambles into.
  @start 0.5
  @pass 2
  @head 2
  @trail 5
  @noise {"#", "$", "%", "&", "*", "+", "<", "=", ">", "?", "@", "[", "]", "{", "}"}

  @doc "Precomputes from the piece's meta, its `scan` option and drawings."
  @spec init(
          meta :: Meta.t(),
          scan :: number(),
          mono :: String.t(),
          art :: String.t(),
          ink :: String.t()
        ) :: map()
  def init(%Meta{cols: cols, rows: rows} = meta, scan, mono, art, ink) do
    mono = Mark.picture(mono, cols)
    art = Mark.picture(art, cols)

    # The line runs from the logo's first row to past its last, rather than the whole frame.
    inked =
      for pic <- [mono, art],
          y <- 0..(rows - 1),
          Enum.any?(Tuple.to_list(elem(pic, y)), &(String.trim(&1) != "")),
          do: y

    {first, last} = Enum.min_max(inked, fn -> {rows, -1} end)

    %{
      meta: meta,
      n: Mark.per_variant(meta),
      mono: mono,
      art: art,
      ink: Mark.picture(ink, cols),
      every: if(scan > 0, do: max(scan, @pass + 0.5), else: 0),
      first: first,
      span: last - first + 1 + @head + @trail
    }
  end

  defp hash(x, y, k) do
    h =
      Int32.bxor(
        Int32.bxor(Int32.imul(x, 73_856_093), Int32.imul(y, 19_349_663)),
        Int32.imul(k, 83_492_791)
      )

    h = Int32.imul(Int32.bxor(h, Int32.ushr(h, 13)), 1_274_126_177)
    Int32.to_uint32(Int32.bxor(h, Int32.ushr(h, 16)))
  end

  @doc "The logo at `t`."
  @spec frame(state :: map(), t :: float(), env :: Env.t()) :: {iodata(), binary() | nil, map()}
  def frame(%{meta: %{cols: cols, rows: rows, fps: fps}} = state, t, %Env{
        paper: paper,
        color?: color?
      }) do
    pic = if color?, do: state.art, else: state.mono
    since = t - @start

    at =
      if state.every != 0 and since >= 0,
        do: state.first + state.span * JSMath.mod(since, state.every) / @pass

    # The noise changes every other frame.
    tick = JSMath.floor(t * fps / 2)

    cells =
      for y <- 0..(rows - 1) do
        level = level(at, y)

        for x <- 0..(cols - 1) do
          ch = Mark.at(pic, x, y)

          if ch == " " do
            {ch, 0}
          else
            ch = if level == 2, do: scramble(ch, x, y, tick), else: ch

            {ch,
             if(color?, do: Mark.index(state.n, paper, level, Mark.at(state.ink, x, y)), else: 0)}
          end
        end
      end

    text = cells |> Enum.map(fn row -> Enum.map(row, &elem(&1, 0)) end) |> Enum.intersperse(?\n)
    colors = if color?, do: IO.iodata_to_binary(for row <- cells, {_, c} <- row, do: c)
    {text, colors, state}
  end

  # Rows since the line reached this one: under the line, in its afterglow,
  # or untouched. No scan (upstream's -Infinity) touches nothing.
  defp level(nil, _y), do: 0

  defp level(at, y) do
    d = at - y

    cond do
      d >= 0 and d < @head -> 2
      d >= @head and d < @head + @trail -> 1
      true -> 0
    end
  end

  defp scramble(ch, x, y, tick) do
    h = hash(x, y, tick)
    if rem(h, 4) != 0, do: elem(@noise, rem(Bitwise.bsr(h, 2), tuple_size(@noise))), else: ch
  end
end
