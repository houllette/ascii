defmodule Ascii.Pieces.WaveText do
  @moduledoc """
  A swell running through a line of text, left to right.

  A swell rolls into a line of text from the left, lifts and drops each
  letter in turn, runs off the right, and the line settles level again.
  Give it your own text, and shape its swell; its letters take colours one
  by one, for a heading in your palette.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): the line
  starts afresh with them, the swell where play time puts it.

    * `text` - the line, centred; as many characters as fit in the 36
      columns (with `spacing`, fewer). Default `"making waves"`.
    * `amp` - rows from the level line to a crest, up to 2.45; 0 is a level
      line. Default 1.25.
    * `wavelength` - letters from crest to crest, at least 4 (0 takes the
      default). Default 18.
    * `speed` - letters a second the swell travels, at least 0.5 (0 takes
      the default). Default 8.
    * `spacing` - blank columns between letters, a whole number. Default 0.
    * `settle` - `true` (the default) lets the line lie level between
      swells; `false` runs one endless swell.

  The line is always 36 by 5.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `letter`, and `letter.<n>` - the letters, and each by its place in
      the text from 1, counting every character, spaces too: `letter.1`,
      `letter.2` and on, so `w` is `letter.7` in "making waves". Wherever
      the swell has carried a letter, it keeps its colour. `letter` colours
      every one without a colour of its own.
    * `trail` - the dot a letter leaves on the level line as it lifts off,
      grey.

  ## Keys and clicks

  It takes none: it is a heading, and `Ascii.handle_event/2` ignores
  every event. A Phoenix player given `interactive` and `notify` still
  tells your LiveView where it was clicked, and on which part
  (`Ascii.part_at/4`): which letter, as `letter.3`.

  ## Screen readers

  `Ascii.describe/1` reads the text: "wave text: hello". Without text,
  it gives the piece's name and note.

  ## Example

  ```elixir
  colours = %{"letter" => "#58a6ff", "letter.1" => "#ff5f6d", "trail" => "#8b949e"}
  heading = Ascii.new!("wave-text", options: %{text: "hello", amp: 2, speed: 6}, parts: colours)
  {frame, heading} = Ascii.frame(heading, 0.0)

  # The first letter in its own colour, the rest in the letters'.
  Ascii.part_at(heading, frame, 15, 2)
  #=> {"letter.1", "h"}
  Ascii.Frame.color_at(frame, 15, 2)
  #=> "#ff5f6d"
  Ascii.Frame.color_at(frame, 16, 2)
  #=> "#58a6ff"

  Ascii.describe(heading)
  #=> "wave text: hello"
  ```

  ```heex
  <Ascii.Phoenix.live_player id="heading" piece="wave-text" options={%{text: @title}} parts={%{"letter" => "var(--brand)"}} />
  ```

  Ported from `src/pieces/wave-text.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{JSMath, Parts}
  alias Ascii.Kit.{Grid, Text}

  @meta %Ascii.Meta{
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
    loop: 57,
    parts: [{"letter", nil}, {"trail", "#8b949e"}]
  }

  @impl true
  def meta, do: @meta

  # JS's `Number(x) || fallback`: zero takes the fallback.
  defp or_else(x, fallback) when x == 0, do: fallback
  defp or_else(x, _fallback), do: x

  @impl true
  def init(%{amp: amp, wavelength: wavelength, speed: speed, settle: settle} = options) do
    %{rows: rows} = @meta
    base = (rows - 1) / 2
    a = min(max(or_else(amp, 0), 0), base + 0.45)
    w = max(or_else(wavelength, 18), 4)
    v = max(or_else(speed, 8), 0.5)
    {letters, n} = letters(options)

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

    %{
      letters: letters,
      base: trunc(base),
      start: start,
      v: v,
      wave: %{a: a, w: w, rise: rise, top: top, pass: pass, l: pass + n, settle: settle}
    }
  end

  # The letters that fit, each with its place in the text from 0 and its
  # column, spaces left out; and how many characters fit, spaces and all.
  defp letters(%{text: text, spacing: spacing}) do
    %{cols: cols} = @meta
    step = 1 + max(0, JSMath.floor(or_else(spacing, 0)))
    chars = text |> Text.chars() |> Enum.take(JSMath.floor((cols - 1) / step) + 1)
    n = length(chars)
    x0 = JSMath.floor((cols - (n - 1) * step - 1) / 2)
    {for({ch, i} <- Enum.with_index(chars), ch != " ", do: {ch, i, x0 + i * step}), n}
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

  # This port's own: the parts of a frame, read off its columns. Each
  # letter keeps a column of its own, where it is the only mark but for the
  # dot it may leave on the level line beneath it.

  @impl true
  def parts(%{lines: lines}, options) do
    {letters, _n} = letters(options)
    base = trunc((@meta.rows - 1) / 2)
    names = Map.new(letters, fn {_ch, i, x} -> {x, "letter.#{i + 1}"} end)
    grid = lines |> Enum.map(&(&1 |> Text.chars() |> List.to_tuple())) |> List.to_tuple()

    # A column with two marks: the one on the level line is the trail.
    trails =
      for {x, _name} <- names,
          marks = for(r <- 0..(tuple_size(grid) - 1), elem(elem(grid, r), x) != " ", do: r),
          length(marks) > 1,
          into: MapSet.new(),
          do: {x, base}

    for {line, r} <- Enum.with_index(lines) do
      Parts.cells(line, fn
        ?\s, _x -> nil
        _cp, x when is_map_key(names, x) -> if({x, r} in trails, do: "trail", else: names[x])
        _cp, _x -> nil
      end)
    end
  end

  @impl true
  def describe(%{text: text}) do
    case String.split(text) do
      [] -> nil
      words -> "wave text: " <> Enum.join(words, " ")
    end
  end
end
