defmodule AsciiArt.Pieces.FormControls do
  @moduledoc """
  A terminal style form being filled in, field by field.

  A settings form drawn the way a terminal app draws one. A focus marker
  tabs down through a text input, a select, radio buttons, a checkbox, a
  switch and a slider, changes each, saves, then changes them back.

  Ported from `src/pieces/form-controls.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.{Grid, Text}

  @meta %AsciiArt.Meta{
    name: "form controls",
    category: :ui,
    note: "a terminal style form being filled in, field by field",
    cols: 54,
    rows: 16,
    fps: 15,
    options: %{title: "preferences"}
  }

  @emails {"you@example.com", "team@example.com"}
  @units {"metric", "imperial"}
  @themes ["light", "dark", "system"]
  @volume {40, 75}
  # Columns: labels, controls, input width inside its brackets.
  @label 4
  @field 14
  @wide 32
  # One past the right edge every control lines up on.
  @right @field + @wide + 4
  # Slider cells.
  @track 30
  @fields ["email", "units", "theme", "notify", "sync", "volume"]
  @keys " tab next · space change · enter save "

  @initial %{
    focus: 6,
    email: "you@example.com",
    typed: -9,
    unit: 0,
    open: false,
    hi: 0,
    theme: 0,
    mentions: false,
    knob: 0,
    volume: 40,
    pressed: false,
    saved: false
  }

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{title: title}) do
    {events, total, start} = script()
    %{title: " #{title} ", events: events, total: total, start: start}
  end

  # The tour of the form as timed changes to its state. Two passes, the
  # second undoing the first, so the loop closes on the starting state.
  defp script do
    {at, events, start} =
      Enum.reduce([1, 0], {0, [], 0}, fn b, {at, events, start} ->
        a = 1 - b
        email = elem(@emails, b)
        acc = {at, events}
        acc = acc |> ev(0.35, %{focus: 0}) |> ev(0.3, %{email: "", typed: :final})

        acc =
          Enum.reduce(1..Text.length(email), acc, fn i, {at, _} = acc ->
            ev(acc, 0.07, %{email: Text.slice(email, 0, i), typed: at + 0.07})
          end)

        start = if b == 1, do: elem(acc, 0) + 0.2, else: start

        acc =
          acc
          |> ev(0.9, %{focus: 1})
          |> ev(0.3, %{open: true, hi: a})
          |> ev(0.4, %{hi: b})
          |> ev(0.35, %{unit: b, open: false})
          |> ev(0.45, %{focus: 2})
          |> ev(0.35, %{theme: if(b == 1, do: 1, else: 0)})
          |> ev(0.45, %{focus: 3})
          |> ev(0.35, %{mentions: b == 1})
          |> ev(0.45, %{focus: 4})

        acc =
          Enum.reduce(1..4, acc, fn k, acc ->
            ev(acc, if(k == 1, do: 0.35, else: 0.07), %{knob: if(b == 1, do: k, else: 4 - k)})
          end)

        acc = ev(acc, 0.45, %{focus: 5})

        acc =
          Enum.reduce(1..7, acc, fn k, acc ->
            v = elem(@volume, a) + (elem(@volume, b) - elem(@volume, a)) * k / 7
            ev(acc, if(k == 1, do: 0.35, else: 0.07), %{volume: v})
          end)

        {at, events} =
          acc
          |> ev(0.45, %{focus: 6})
          |> ev(0.4, %{pressed: true})
          |> ev(0.18, %{pressed: false, saved: true})
          |> ev(1.3, %{saved: false})

        {at, events, start}
      end)

    # Clearing the input stamps it with the script's clock as it stands when
    # the frame runs, which is the end of the script.
    events =
      events
      |> Enum.reverse()
      |> Enum.map(fn
        {w, %{typed: :final} = c} -> {w, %{c | typed: at}}
        e -> e
      end)

    {events, at + 0.4, start}
  end

  defp ev({at, events}, dt, changes) do
    at = at + dt
    {at, [{at, changes} | events]}
  end

  @impl true
  def frame(%{events: events, total: total, start: start, title: name} = state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    p = JSMath.mod(t + start, total)

    s =
      Enum.reduce_while(events, @initial, fn {w, changes}, s ->
        if w > p, do: {:halt, s}, else: {:cont, Map.merge(s, changes)}
      end)

    grid =
      cols
      |> Grid.new(rows)
      |> border()
      |> text(0, 2, name)
      |> text(rows - 1, cols - 2 - Text.length(@keys), @keys)

    grid =
      @fields
      |> Enum.with_index()
      |> Enum.reduce(grid, fn {f, i}, grid ->
        grid = text(grid, 2 + 2 * i, @label, f)
        if s.focus == i, do: text(grid, 2 + 2 * i, @label - 2, ">"), else: grid
      end)

    grid = grid |> controls(s, p) |> buttons(s) |> select(s)
    {Grid.to_iodata(grid), nil, state}
  end

  defp border(grid) do
    %{cols: cols, rows: rows} = @meta

    grid =
      Enum.reduce(1..(cols - 2), grid, fn c, g ->
        g |> Grid.put(c, 0, "─") |> Grid.put(c, rows - 1, "─")
      end)

    grid =
      Enum.reduce(1..(rows - 2), grid, fn r, g ->
        g |> Grid.put(0, r, "│") |> Grid.put(cols - 1, r, "│")
      end)

    grid
    |> Grid.put(0, 0, "╭")
    |> Grid.put(cols - 1, 0, "╮")
    |> Grid.put(0, rows - 1, "╰")
    |> Grid.put(cols - 1, rows - 1, "╯")
  end

  defp text(grid, r, c, s) do
    limit = @meta.cols - 1

    s
    |> String.codepoints()
    |> Enum.with_index(c)
    |> Enum.reduce_while(grid, fn {ch, x}, g ->
      if x < limit, do: {:cont, Grid.put(g, x, r, ch)}, else: {:halt, g}
    end)
  end

  defp controls(grid, s, p) do
    # The caret holds while keys are coming, then blinks.
    since = p - s.typed

    caret =
      if s.focus == 0 and (since < 0.4 or rem(floor((since - 0.4) / 0.5), 2) == 1),
        do: "█",
        else: " "

    grid = text(grid, 2, @field, "[ " <> Text.pad_end(s.email <> caret, @wide) <> " ]")

    grid =
      text(
        grid,
        4,
        @field,
        "[ " <>
          Text.pad_end(elem(@units, s.unit), @wide - 1) <> if(s.open, do: "^", else: "v") <> " ]"
      )

    themes =
      @themes
      |> Enum.with_index()
      |> Enum.map_join("   ", fn {th, i} -> if(s.theme == i, do: "(*) ", else: "( ) ") <> th end)

    grid = text(grid, 6, @field, themes)

    grid =
      text(
        grid,
        8,
        @field,
        "[x] replies   " <> if(s.mentions, do: "[x]", else: "[ ]") <> " mentions"
      )

    # A switch: the knob slides along a shaded track, filling it behind.
    knob = s.knob

    sw =
      for i <- 0..5, into: "▕" do
        cond do
          i < knob -> "▒"
          i < knob + 2 -> "█"
          true -> "░"
        end
      end

    grid = text(grid, 10, @field, sw <> "▏ " <> if(knob == 4, do: "on", else: "off"))

    k = JSMath.round(s.volume / 100 * (@track - 1))

    track =
      for i <- 0..(@track - 1), into: "" do
        cond do
          i < k -> "━"
          i == k -> "█"
          true -> "─"
        end
      end

    pct = Text.pad_start(Integer.to_string(JSMath.round(s.volume)), 5)
    text(grid, 12, @field, track <> pct <> "%")
  end

  # Buttons at the right, the last one pressed with a fill.
  defp buttons(grid, s) do
    save = if s.pressed, do: "[▒▒save▒▒]", else: "[  save  ]"
    bc = @right - 10
    grid = grid |> text(14, bc - 13, "[ cancel ]") |> text(14, bc, save)
    grid = if s.focus == 6, do: text(grid, 14, bc - 1, ">"), else: grid
    if s.saved, do: text(grid, 14, @label, "saved"), else: grid
  end

  # The select's list drops over the rows beneath it.
  defp select(grid, %{open: false}), do: grid

  defp select(grid, s) do
    w = @right - @field
    rule = String.duplicate("─", w - 2)
    grid = text(grid, 5, @field, "┌" <> rule <> "┐")

    grid =
      Enum.reduce(0..1, grid, fn i, g ->
        item = if(s.hi == i, do: " > ", else: "   ") <> elem(@units, i)
        text(g, 6 + i, @field, "│" <> Text.pad_end(item, w - 2) <> "│")
      end)

    text(grid, 8, @field, "└" <> rule <> "┘")
  end
end
