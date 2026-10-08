# Writing a piece

The built-in pieces are modules implementing `AsciiArt.Piece`, and yours can
be too. A piece module works everywhere a slug does: `AsciiArt.new/2`,
`AsciiArt.render/3`, `AsciiArt.stream/2`, `AsciiArt.Player`, the renderers
and the `ascii/1` component.

## The contract

A piece has three functions:

  * `meta/0` returns an `AsciiArt.Meta`: its name, what you see, its size in
    cells, its frame rate, the default of every option, and, for a coloured
    piece, its palette (and a ground, for a scene).
  * `init/1` receives the options (the defaults merged with what was asked
    for, already checked) and returns a state. Precompute here.
  * `frame/3` receives the state, the play time `t` in seconds and an
    `AsciiArt.Env`, and returns `{text, colors, state}`.

## A first piece

```elixir
defmodule MyApp.Pieces.Wave do
  @behaviour AsciiArt.Piece

  @cols 48
  @rows 9

  @impl true
  def meta do
    %AsciiArt.Meta{
      name: "wave",
      category: :generative,
      note: "a sine wave rolling by",
      cols: @cols,
      rows: @rows,
      fps: 20,
      options: %{speed: 1.0, crest: "~"},
      bounds: %{speed: {0.1, 10}},
      palette: ["#1d4e89", "#7fd1ff"]
    }
  end

  @impl true
  def init(%{speed: speed, crest: crest}) do
    # Options are checked against the defaults, so crest is a string; keep its
    # first character, so every line stays @cols wide.
    %{speed: speed, crest: crest |> String.codepoints() |> List.first("~")}
  end

  @impl true
  def frame(%{speed: speed, crest: crest} = state, t, env) do
    heights = for x <- 0..(@cols - 1), do: round((@rows - 1) * (1 + :math.sin(x / 5 + t * speed)) / 2)

    text =
      Enum.map_join(0..(@rows - 1), "\n", fn y ->
        for h <- heights, into: "", do: if(h == y, do: crest, else: " ")
      end)

    colors =
      if env.color?,
        do: for(y <- 0..(@rows - 1), _h <- heights, into: <<>>, do: <<if(y < @rows / 2, do: 1, else: 0)>>)

    {text, colors, state}
  end
end

{:ok, anim} = AsciiArt.new(MyApp.Pieces.Wave, options: %{"speed" => "3", "crest" => "≈"})
{frame, _anim} = AsciiArt.frame(anim, 1.0)
{length(frame.lines), frame.lines |> Enum.map(&String.length/1) |> Enum.uniq()}
#=> {9, [48]}
```

Options come in through `AsciiArt.Options` like a built-in piece's: only the
keys in `meta.options`, of the same kind as their defaults, and numbers
clamped to `meta.bounds` (or ±1,000,000 without one). Still, `init/1` should
make any value it is given safe to draw, as `crest` is here.

## Rules every piece keeps

  * **Exact size.** The text is `rows` lines of exactly `cols` characters
    (code points), joined by `"\n"`, with no newline at the end. Every
    renderer relies on it. `text` may be iodata.
  * **Colours only when asked.** Return `nil` colours unless the piece has a
    palette and `env.color?` is true; then a binary of `cols * rows` bytes, row
    by row, each an index into the palette. With `env.color?` false a coloured
    piece draws its one-ink version, as text.
  * **Paper.** On a light page (`env.paper`) dense characters must still mean
    dark, so a shaded piece reads its ramp from the other end:
    `ramp = if env.paper, do: String.reverse(@ramp), else: @ramp`.
  * **A function of its inputs.** A frame depends only on the state, `t` and
    the env: no processes, no process dictionary, no wall clock. Pieces that
    show the time set `clock: true` in their meta and read `env.now`
    (`nil` means the system clock). Random pieces draw from a seeded
    generator kept in the state (or seeded from the options), so the same
    calls give the same frames.
  * **Any `t`.** `t` usually grows by `1/fps`, but a player can pause, skip,
    or start over. A piece that steps a simulation should step by how far `t`
    moved, cap a long jump, and cope with `t` going backwards.
  * **Cheap frames.** Do the expensive work in `init/1`. Upstream's budget is
    4 ms a frame for text pieces, and 10 ms for 200×100 scenes.

The built-in pieces use `:math` too, and `AsciiArt.JSMath` only where
JavaScript's numbers behave differently from Elixir's (`Math.round` rounds
halves up, `%` keeps the dividend's sign), to match upstream. Your own piece
has no upstream to match, so it needs neither.

## Options from outside, a size, and live data

A few more things a piece can say, all optional:

  * **`bounds`** in its meta: the range a numeric option is clamped to when
    it comes from outside, such as `%{speed: {0.1, 10}}`.
  * **`shapes`** in its meta: for an option whose default cannot show what
    it takes, an example of what it does. An empty list takes strings
    unless told otherwise, so a list of numbers says `%{values: [0.0]}`.
  * **`size/1`**: the frame's size for the options, `{cols, rows}`, for a
    piece that fits its data or a width. Every frame must be that size.
  * **`update/2`**: the state for new options while it plays (see
    `AsciiArt.put_options/2`), keeping what it can, so a needle swings on
    from where it was. Without it, `init/1` starts afresh.

```elixir
defmodule MyApp.Pieces.Level do
  @behaviour AsciiArt.Piece

  @impl true
  def meta do
    %AsciiArt.Meta{
      name: "level",
      category: :data,
      note: "a bar that eases to its value",
      cols: 20,
      rows: 1,
      fps: 20,
      options: %{value: 0, width: 20},
      bounds: %{value: {0, 100}, width: {4, 200}}
    }
  end

  @impl true
  def size(%{width: width}), do: {trunc(width), 1}

  @impl true
  def init(%{value: value} = options), do: Map.merge(options, %{shown: value * 1.0, at: nil})

  # A new value: ease to it from what was shown, when it was shown.
  @impl true
  def update(state, options), do: options |> init() |> Map.merge(Map.take(state, [:shown, :at]))

  # Eases toward the value by how far play time moved since the last frame.
  @impl true
  def frame(%{value: value, shown: shown, width: width} = state, t, _env) do
    step = min(1.0, max(0.0, t - (state.at || t)) * 6)
    shown = shown + (value - shown) * step
    full = round(trunc(width) * shown / 100)
    text = [String.duplicate("█", full), String.duplicate("░", trunc(width) - full)]
    {text, nil, %{state | shown: shown, at: t}}
  end
end

anim = AsciiArt.new!(MyApp.Pieces.Level, options: %{value: 100, width: 10})
{frame, anim} = AsciiArt.frame(anim, 0.0)
frame.text
#=> "██████████"

anim = AsciiArt.put_options!(anim, value: 0)
{frame, _anim} = AsciiArt.frame(anim, 0.05)
frame.text
#=> "███████░░░"
```

## Testing it

Check the contract over a run of times, in colour and not, on paper and not,
including a step backwards:

```elixir
# needs: your test suite
defmodule MyApp.Pieces.WaveTest do
  use ExUnit.Case, async: true

  for color <- [true, false], paper <- [false, true] do
    test "frames fit the meta (color: #{color}, paper: #{paper})" do
      {:ok, anim} = AsciiArt.new(MyApp.Pieces.Wave, color: unquote(color), paper: unquote(paper))
      meta = anim.meta

      Enum.reduce([0.0, 0.5, 1.0, 2.5, 10.0, 1.0], anim, fn t, anim ->
        {frame, anim} = AsciiArt.frame(anim, t)
        assert length(frame.lines) == meta.rows
        assert Enum.all?(frame.lines, &(length(String.codepoints(&1)) == meta.cols))
        if unquote(color), do: assert(byte_size(frame.colors) == meta.cols * meta.rows), else: assert(frame.colors == nil)
        anim
      end)
    end
  end
end
```

## Using it

```elixir
alias MyApp.Pieces.Wave

AsciiArt.render!(Wave, 0.5) |> String.split("\n") |> length()
#=> 9

AsciiArt.stream!(Wave) |> Enum.take(3) |> Enum.map(& &1.t)
#=> [0.0, 0.05, 0.1]
```

Pass the module wherever a slug goes, in a template:

```heex
<AsciiArt.Phoenix.Components.ascii piece={MyApp.Pieces.Wave} />
<AsciiArt.Phoenix.player socket={@socket} id="wave" piece={MyApp.Pieces.Wave} />
```

or by name to the mix task, which looks for it among the modules of your
project and its dependencies:

```sh
mix ascii_art.play MyApp.Pieces.Wave --option speed=3
```

A piece module reaches the player's LiveView in its session, which only your
code writes. A string there, as from params, is always a slug: nothing from
outside can name a module.
