# Drawing frames yourself

Every renderer in this library takes an `AsciiArt.Frame`, and so can yours.
A frame is plain data with no processes or resources behind it, so it can be
stored, sent between nodes, or turned into anything that can show a grid of
characters.

## Cells

`lines` holds `rows` lines of exactly `cols` characters (code points: count
and split them with `String.codepoints/1`, not by bytes). A coloured piece
drawn in colour also has `colors`, one byte a cell, row by row, indexing
`palette`. Walk them together:

```elixir
{frame, _} = AsciiArt.new!("ubuntu") |> AsciiArt.frame(0.0)

cells =
  for {line, y} <- Enum.with_index(frame.lines),
      {char, x} <- Enum.with_index(String.codepoints(line)) do
    {x, y, char, Enum.at(frame.palette, :binary.at(frame.colors, y * frame.cols + x))}
  end

length(cells) == frame.cols * frame.rows
#=> true
```

`AsciiArt.Frame.color_at/3` does the lookup for one cell. For speed, turn the
palette into a tuple once a frame and read colours a row at a time with
`:binary.bin_to_list(colors, y * cols, cols)`.

A few rules every renderer here follows:

  * `colors` is `nil` for text pieces, and for coloured ones made with
    `color: false`: draw `text` in a single ink of your choice. Given an
    `:ink` or `:parts` (see `AsciiArt.Ink` and `AsciiArt.Parts`), they have
    colours too.
  * A palette entry can be `nil`: those cells are in your own ink, as a
    piece's parts are when only some of them have colours.
  * `ground` is the colour behind a scene. Fill it behind a coloured frame;
    blank cells show it.
  * A space is blank, whatever its colour index. Merging spaces into the run
    around them makes far fewer runs of colour.
  * `cell` is a cell's height in cell widths: 2 for most pieces, the shape of
    a character, and 1 for scenes, whose cells are square.

## Runs of colour

Most outputs want runs of one colour rather than single cells. This groups
each row, letting spaces join the run they are in:

```elixir
defmodule MyApp.Runs do
  @doc "Each row as `[{hex_colour, text}]`."
  def rows(%AsciiArt.Frame{colors: colors, palette: palette} = frame) when is_binary(colors) do
    palette = List.to_tuple(palette)

    for {line, y} <- Enum.with_index(frame.lines) do
      line
      |> String.codepoints()
      |> Enum.zip(:binary.bin_to_list(colors, y * frame.cols, frame.cols))
      |> Enum.reduce([], fn
        {" ", _}, [{color, text} | runs] -> [{color, text <> " "} | runs]
        {char, i}, [{color, text} | runs] when color == elem(palette, i) -> [{color, text <> char} | runs]
        {char, i}, runs -> [{elem(palette, i), char} | runs]
      end)
      |> Enum.reverse()
    end
  end
end

{frame, _} = AsciiArt.new!("elixir") |> AsciiArt.frame(0.0)
row = MyApp.Runs.rows(frame) |> Enum.at(14)
String.length(Enum.map_join(row, &elem(&1, 1))) == frame.cols
#=> true
```

## What changed

Between one frame and the next most pieces change a few cells in a hundred.
`AsciiArt.Frame.changes/3` gives just those, as runs along a row,
`{y, x, text, colors}`, the colours being the run's palette indices; a
display that already shows the frame before needs nothing else. With `nil`
before, it gives every row whole.

```elixir
anim = AsciiArt.new!("night-coast")
{a, anim} = AsciiArt.frame(anim, 1.0)
{b, _anim} = AsciiArt.frame(anim, 1.1)

runs = AsciiArt.Frame.changes(a, b)
cells = runs |> Enum.map(fn {_y, _x, text, _colors} -> String.length(text) end) |> Enum.sum()
cells < b.cols * b.rows / 5
#=> true
```

`AsciiArt.Render.ANSI.changes/3` writes them to a terminal, and the LiveView
player sends them to the browser.

## SVG

An SVG keeps the characters as text, so it scales and can be copied: for a
README, an Open Graph image, or an email that allows SVG.
`AsciiArt.Render.SVG` writes one: each row a `<text>`, each run of one
colour a `<tspan>` placed at its column and held to its width, so the
columns line up in whatever monospace font the reader has.

```elixir
{frame, _} = AsciiArt.new!("elixir") |> AsciiArt.frame(0.0)
svg = frame |> AsciiArt.Render.SVG.render(title: "the Elixir logo") |> IO.iodata_to_binary()
String.starts_with?(svg, "<svg") and svg =~ "<title>the Elixir logo</title>"
#=> true
```

`File.write!("elixir.svg", svg)` and open it in a browser, or from the
command line, `mix ascii_art.svg elixir`. Text pieces take `:foreground`
(the colour of the text around an inline SVG by default) and anything
`:background`; a CSS variable in a palette stays one, so an SVG inlined in a
page takes the page's colours. Frames put together with `AsciiArt.Compose`
are frames like any other: a dashboard as one picture.

## A terminal recording

[asciinema](https://asciinema.org)'s `.cast` format is a JSON header and a
JSON line per burst of output, so `AsciiArt.Render.ANSI` makes a recording
anyone can replay in a terminal or embed with asciinema's web player:

```elixir
defmodule MyApp.Cast do
  alias AsciiArt.Render.ANSI

  def record(piece, seconds) do
    anim = AsciiArt.new!(piece)
    step = 1 / max(anim.fps, 1)
    header = JSON.encode!(%{version: 2, width: anim.meta.cols, height: anim.meta.rows})

    {events, _anim} =
      Enum.map_reduce(0..round(seconds / step), anim, fn i, anim ->
        t = i * step
        {frame, anim} = AsciiArt.frame(anim, t)
        # A terminal's newline returns the cursor too; a recording must say so.
        out = [ANSI.home(), ANSI.render(frame)] |> IO.iodata_to_binary() |> String.replace("\n", "\r\n")
        {JSON.encode!([Float.round(t, 3), "o", out]), anim}
      end)

    Enum.join([header | events], "\n") <> "\n"
  end
end

cast = MyApp.Cast.record("spinners", 2)
cast |> String.split("\n", trim: true) |> length()
#=> 26
```

`File.write!("spinners.cast", cast)`, then `asciinema play spinners.cast`.

## Over the wire

To draw frames somewhere else, a browser, another service, a microcontroller,
send the data and let the other side draw. The palette is fixed for an
animation, so send it once; each frame is then its text and its colours:

```elixir
{frame, _} = AsciiArt.new!("elixir") |> AsciiArt.frame(0.0)

once = JSON.encode!(%{cols: frame.cols, rows: frame.rows, cell: frame.cell, palette: frame.palette, ground: frame.ground})
each = JSON.encode!(%{text: frame.text, colors: Base.encode64(frame.colors)})

byte_size(each) < 5_000
#=> true
```

A logo's frame is a few kilobytes. A scene's is 20,000 cells, about 70 kB as
JSON: at 15 frames a second, a megabyte a second to each viewer. Two things
cut that down, and `AsciiArt.Phoenix.PlayerLive` does both: a scene changes
a few cells in a hundred a frame, so send only the runs of cells that
changed; and a piece that closes a loop (`AsciiArt.loop/1`) can be sent one
cycle, once, for the other side to repeat.

Between BEAM nodes, send the `%AsciiArt.Frame{}` itself. To share one
animation between many viewers, play it once and let them subscribe (see
the [Phoenix guide](phoenix.md#one-player-many-viewers)).

## Other displays

The [Nerves guide](nerves.md#on-a-display) turns frames into pixels for a
framebuffer or an SPI panel, and the [ExRatatui guide](ex_ratatui.md) into
ratatui spans; both are the walk above with a different output.
