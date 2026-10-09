# Livebook

In a [Livebook](https://livebook.dev) notebook, [Kino](https://hexdocs.pm/kino)
shows a piece as HTML, and `Kino.animate/3` plays it. These examples were
written against Kino 0.19.

```elixir
# needs: a notebook's setup cell
Mix.install([
  {:kino, "~> 0.19"},
  {:ascii, "~> 0.4.0"}
])
```

## A helper

`Ascii.Render.HTML` gives the inside of a `<pre>`, escaped, with coloured
pieces as spans of their palette; wrap it and hand it to `Kino.HTML`:

```elixir
# needs: kino
defmodule Art do
  @style "margin:0;line-height:1.2;letter-spacing:0;white-space:pre;font-family:monospace;font-size:12px"

  def kino(%Ascii.Frame{} = frame) do
    ground = if frame.colors && frame.ground, do: ";background:" <> frame.ground, else: ""
    html = ["<pre style=\"", @style, ground, "\">", Ascii.Render.HTML.render(frame), "</pre>"]
    Kino.HTML.new(IO.iodata_to_binary(html))
  end
end
```

## A still

```elixir
# needs: kino
Ascii.new!("elixir") |> Ascii.frame(0.0) |> elem(0) |> Art.kino()
```

## Playing

`Kino.animate/3` calls a function every interval with the tick number and a
state of your choosing, and shows what it returns. Keep the animation as the
state, so pieces with state between frames play correctly:

```elixir
# needs: kino
{:ok, anim} = Ascii.new("donut")
interval = round(1000 / anim.fps)

Kino.animate(interval, anim, fn i, anim ->
  {frame, anim} = Ascii.frame(anim, i * interval / 1000)
  {:cont, Art.kino(frame), anim}
end)
```

Return `:halt` instead of `{:cont, …}` to stop, for example after a number of
ticks.

## Live data

The UI and data pieces draw your own data (see
[Live data](getting-started.md#live-data)). Take new readings up with
`Ascii.put_options!/2` as the animation plays, here once a second, and
the gauge's needle swings to each:

```elixir
# needs: kino
{:ok, anim} = Ascii.new("gauge", options: %{label: "run queue", max: 20, value: 0})

Kino.animate(100, anim, fn i, anim ->
  anim =
    if rem(i, 10) == 0,
      do: Ascii.put_options!(anim, value: :erlang.statistics(:total_run_queue_lengths)),
      else: anim

  {frame, anim} = Ascii.frame(anim, i * 0.1)
  {:cont, Art.kino(frame), anim}
end)
```

## Options and controls

Kino's inputs make a small explorer. Options typed into a form are checked
against the piece's defaults, so a mistyped key comes back as an error rather
than a crash:

```elixir
# needs: kino
piece = Kino.Input.select("piece", Enum.map(Ascii.pieces(category: :logos), &{&1, &1}))
paper = Kino.Input.checkbox("paper")
Kino.Layout.grid([piece, paper], columns: 2)
```

```elixir
# needs: kino, and the cell above
{:ok, anim} = Ascii.new(Kino.Input.read(piece), paper: Kino.Input.read(paper))

Kino.animate(33, anim, fn i, anim ->
  {frame, anim} = Ascii.frame(anim, i * 0.033)
  {:cont, Art.kino(frame), anim}
end)
```

## Text and terminal output

For a text piece, `Kino.Text` is enough, and with `terminal: true` it renders
ANSI escapes, so `Ascii.Render.ANSI` works too (in 256 colours, to be
safe):

```elixir
# needs: kino
{frame, _} = Ascii.new!("arch-linux") |> Ascii.frame(0.0)
frame |> Ascii.Render.ANSI.render(mode: :ansi256) |> IO.iodata_to_binary() |> Kino.Text.new(terminal: true)
```

Scenes are 200×100 cells: at a small font size they fit a notebook's width.
They take a moment to set up (`Ascii.new/2`), so make the animation once
and keep it in a variable.
