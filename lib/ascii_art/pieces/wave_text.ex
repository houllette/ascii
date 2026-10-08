defmodule AsciiArt.Pieces.WaveText do
  @moduledoc """
  A swell running through a line of text, left to right.

  A swell rolls into a line of text from the left, lifts and drops each
  letter in turn, runs off the right, and the line settles level again.

  `amp` is rows from the level line to a crest, `wavelength` letters from
  crest to crest, `speed` letters a second the swell travels, `spacing` blank
  columns between letters, and `settle` level water between swells (or one
  endless swell).

  Ported from `src/pieces/wave-text.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.{Grid, Text}

  @meta %AsciiArt.Meta{
    name: "wave text",
    category: :type,
    note: "a swell running through a line of text, left to right",
    cols: 36,
    rows: 5,
    fps: 15,
    options: %{
      text: "making waves",
      amp: 1.25,
      wavelength: 18,
      speed: 8,
      spacing: 0,
      settle: true
    },
    loop: 57
  }

  @impl true
  def meta, do: @meta

  # JS's `Number(x) || fallback`: zero takes the fallback.
  defp or_else(x, fallback) when x == 0, do: fallback
  defp or_else(x, _fallback), do: x

  @impl true
  def init(%{
        text: text,
        amp: amp,
        wavelength: wavelength,
        speed: speed,
        spacing: spacing,
        settle: settle
      }) do
    %{cols: cols, rows: rows} = @meta
    base = (rows - 1) / 2
    a = min(max(or_else(amp, 0), 0), base + 0.45)
    w = max(or_else(wavelength, 18), 4)
    v = max(or_else(speed, 8), 0.5)
    step = 1 + max(0, JSMath.floor(or_else(spacing, 0)))
    chars = text |> Text.chars() |> Enum.take(JSMath.floor((cols - 1) / step) + 1)
    n = length(chars)
    x0 = JSMath.floor((cols - (n - 1) * step - 1) / 2)

    # One pass: half a wavelength to build, a wavelength and a half at full
    # height, half a wavelength to fade, then level water until the tail has
    # cleared the last letter. The envelope is zero at the seam, so the loop
    # never pops.
    rise = w / 2
    top = 1.5 * w
    pass = 2 * rise + top

    # Settling, t = 0 has the front just reaching the first letter, so the line
    # starts level. Endless, it starts with a crest over the middle letter,
    # where the wave is flattest.
    start = if settle, do: 0, else: w / 4 + (n - 1) / 2

    letters =
      for {ch, i} <- Enum.with_index(chars), ch != " ", do: {ch, i, x0 + i * step}

    %{
      letters: letters,
      base: trunc(base),
      start: start,
      v: v,
      wave: %{a: a, w: w, rise: rise, top: top, pass: pass, l: pass + n, settle: settle}
    }
  end

  defp envelope(%{settle: false}, _u), do: 1

  defp envelope(%{rise: rise, top: top, pass: pass}, u) do
    cond do
      u < rise -> sq(:math.sin(:math.pi() / 2 * (u / rise)))
      u < rise + top -> 1
      u < pass -> sq(:math.cos(:math.pi() / 2 * ((u - rise - top) / rise)))
      true -> 0
    end
  end

  defp sq(x), do: x * x

  defp height(%{a: a, w: w, l: l, settle: settle} = wave, u) do
    u = if settle, do: JSMath.mod(JSMath.mod(u, l) + l, l), else: u
    a * envelope(wave, u) * :math.sin(2 * :math.pi() * u / w)
  end

  @impl true
  def frame(%{wave: wave, base: base} = state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    s = state.start + t * state.v

    grid =
      Enum.reduce(state.letters, Grid.new(cols, rows), fn {ch, i, x}, g ->
        u = s - i
        h = height(wave, u)
        lift = JSMath.round(h)
        g = Grid.put(g, x, base - lift, ch)

        # A letter that has only just stepped off the level line leaves a dot
        # where it sat, so the step reads as motion rather than a jump.
        if lift > 0 and h < 0.7 and height(wave, u + 0.5) > h,
          do: Grid.put(g, x, base, "·"),
          else: g
      end)

    {Grid.to_iodata(grid), nil, state}
  end
end
