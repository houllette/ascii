defmodule AsciiArt.Pieces.FormControls do
  @moduledoc """
  A terminal style form being filled in, field by field.

  A settings form drawn the way a terminal app draws one. As upstream
  draws it, a focus marker tabs down through a text input, a select, radio
  buttons, a checkbox, a switch and a slider, changes each, saves, then
  changes them back. Give it `fields` and it draws your form instead, for
  a reader to fill in with keys and clicks.

  ## Options

  Give them to `AsciiArt.new/2` as `options:`, and new ones while it plays
  with `AsciiArt.put_options/2` (or a Phoenix player's `options`): the form
  is drawn anew from them. Give only what you mean to change: what a reader
  has filled in is in its options already, and giving back older values
  would undo keys typed since.

    * `fields` - your form, a list of maps, each with a `type` and a
      `label`, and its type's own keys. Default `[]`: upstream's tour.
      * `"text"` - an input holding `text`.
      * `"select"` - one of `choices`, the one at index `choice`.
      * `"radio"` - `choices` as radio buttons, `choice` the one set.
      * `"checkbox"` - `choices` as checkboxes, `checked` a boolean for
        each; with no `choices`, one box.
      * `"switch"` - `on` or off.
      * `"slider"` - `value` from `min` to `max` (0 to 100 by default), in
        steps of `step` (1; 0 for a hundredth of the range), with its
        `unit` after it (`"%"`, `" ms"`).

      A field with no `type` is a text field; one of a type it does not
      know is its label alone.
    * `buttons` - the buttons' names, at the right under the fields.
      Default `["cancel", "save"]`.
    * `focus` - the field, or after them the button, in focus, from 0;
      `-1` for none. Default `0`.
    * `status` - a note at the left of the buttons, such as `"saved"`.
      Default `""`.
    * `title` - the form's name, in its top edge. Default `"preferences"`.
    * `cols` - the frame's width, 32 to 200; 54 by default.

  All but `title` are for a form of your own: the tour is always 54 by 16.
  A form's fields take two rows each, so its frame is
  `2 * length(fields) + 4` rows. Controls are cut at the right edge, and
  buttons that do not fit left out; a focused text field shows the end of
  its text, so the caret stays in view. Control characters in its strings
  are shown as spaces.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `AsciiArt.Ink`); part by part with `:parts` (see `AsciiArt.Parts`),
  `parts: true` taking the colours suggested here:

    * `frame` - the border, grey; and the controls' own, `frame.input`,
      `frame.select` (with its arrow) and `frame.menu`, the tour's open
      list.
    * `title` - the form's name in the border.
    * `focus` - the marker at the focused field or button (or the list's
      chosen item, or a row's checkbox that keys tick), yellow.
    * `label` - a field's name; `label.focus`, the focused one's, yellow.
    * `field` - what a field holds: its text, the choices' names, on or
      off.
    * `cursor` - a text field's caret, yellow.
    * `checked`, `unchecked` - radio buttons' and checkboxes' marks, green
      and grey.
    * `bar`, `knob`, `track` - a switch's and a slider's filled cells,
      blue; the knob; and the empty cells and the switch's ends, grey.
    * `value`, `unit` - a slider's reading.
    * `button` - a button; `button.focus`, the focused one, yellow.
    * `status` - a form's note; `status.ok`, the tour's saved note, green.
    * `key`, `hint` - the keys along the bottom, yellow, and what they do,
      grey.

  ## Keys and clicks

  A form of your own takes keys and clicks with
  `AsciiArt.handle_event/2`, changing `fields` and `focus`, from which the
  app reads what was filled in and where the focus is:

    * Tab and back tab move the focus round the fields and buttons; up and
      down move it and stop at the ends; home and end go to the first and
      last; enter on a field goes on to the next.
    * A text field in focus takes printable characters, up to 256, and
      backspace.
    * Space steps a select or radio buttons on, flips a switch, and ticks
      the checkbox marked `>`.
    * Left and right step a select or radio buttons, move the checkbox
      mark, turn a switch off and on, move a slider a step (page up and
      page down, ten), and move along the buttons.
    * Enter or space on a button is the app's: it is ignored, and `focus`
      says which button.
    * A click takes the focus to the field or button it lands on, and
      picks the radio button, ticks the checkbox, flips the switch or sets
      the slider where it lands; on a select already in focus, it steps it
      on.

  The tour takes none. In Phoenix, give the player `interactive` (and
  `notify` to be told of each key and click); there Tab is the page's, to
  move on from the form, so up and down move between fields. In
  ExRatatui, `AsciiArt.ExRatatui.handle_event/3`; in a terminal,
  `mix ascii_art.play form-controls --option 'fields=[{"label": "name"}]' --interactive`.

  ## Screen readers

  `AsciiArt.describe/1` reads the form, each field's label and value and
  where the focus is, as "account: email ada@example.com, plan free,
  volume 40%; focus on plan"; past 160 characters it ends ", and N more".
  Playing its tour, it gives the piece's name and note.

  ## Example

  ```elixir
  fields = [
    %{type: "text", label: "email", text: "ada@example.com"},
    %{type: "radio", label: "plan", choices: ["free", "team"], choice: 1},
    %{type: "slider", label: "volume", value: 40, unit: "%"}
  ]

  form = AsciiArt.new!("form-controls", options: %{title: "account", fields: fields}, parts: true)
  {:ok, form} = AsciiArt.handle_event(form, {:key, "tab"})
  {:ok, form} = AsciiArt.handle_event(form, {:key, "left"})
  Enum.at(form.options.fields, 1).choice
  #=> 0

  AsciiArt.describe(form)
  #=> "account: email ada@example.com, plan free, volume 40%; focus on plan"
  ```

  ```heex
  <AsciiArt.Phoenix.live_player id="account" piece="form-controls" options={%{title: "account", fields: @fields}} parts interactive notify />
  ```

  Ported from `src/pieces/form-controls.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{JSMath, Parts}
  alias AsciiArt.Kit.{Grid, Text}

  @meta %AsciiArt.Meta{
    name: "form controls",
    category: :ui,
    note: "a terminal style form being filled in, field by field",
    cols: 54,
    rows: 16,
    fps: 15,
    options: %{
      title: "preferences",
      fields: [],
      buttons: ["cancel", "save"],
      focus: 0,
      status: "",
      cols: 54
    },
    bounds: %{
      focus: {-1, 512},
      cols: {32, 200},
      fields: %{
        choice: {0, 255},
        value: {-1.0e12, 1.0e12},
        min: {-1.0e12, 1.0e12},
        max: {-1.0e12, 1.0e12},
        step: {0, 1.0e12}
      }
    },
    shapes: %{
      fields: [
        %{
          type: "text",
          label: "",
          text: "",
          choices: [""],
          choice: 0,
          checked: [false],
          on: false,
          value: 0.0,
          min: 0.0,
          max: 100.0,
          step: 1.0,
          unit: ""
        }
      ]
    },
    parts: [
      {"frame", "#8b949e"},
      {"frame.input", nil},
      {"frame.select", nil},
      {"frame.menu", nil},
      {"title", nil},
      {"focus", "#d29922"},
      {"label", nil},
      {"label.focus", "#d29922"},
      {"field", nil},
      {"cursor", "#d29922"},
      {"checked", "#3fb950"},
      {"unchecked", "#8b949e"},
      {"bar", "#58a6ff"},
      {"knob", nil},
      {"track", "#8b949e"},
      {"value", nil},
      {"unit", nil},
      {"button", nil},
      {"button.focus", "#d29922"},
      {"status", nil},
      {"status.ok", "#3fb950"},
      {"key", "#d29922"},
      {"hint", "#8b949e"}
    ]
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
  def size(%{fields: []}), do: {@meta.cols, @meta.rows}
  def size(%{fields: fields, cols: cols}), do: {trunc(cols), 2 * length(fields) + 4}

  @impl true
  def init(%{fields: [], title: title}) do
    {events, total, start} = script()
    %{title: " #{title} ", events: events, total: total, start: start}
  end

  # A form of the app's own: drawn once with the caret and once without,
  # its clock starting at the first frame.
  def init(options) do
    form = layout(options)
    %{form: form, pictures: {draw(form, false), draw(form, true)}, since: nil}
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
  def frame(%{form: _, pictures: {off, on}} = state, t, _env) do
    since = state.since || t
    {if(caret?(t - since), do: on, else: off), nil, %{state | since: since}}
  end

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

  defp border(%Grid{cols: cols, rows: rows} = grid) do
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
    limit = grid.cols - 1

    s
    |> String.codepoints()
    |> Enum.with_index(c)
    |> Enum.reduce_while(grid, fn {ch, x}, g ->
      if x < limit, do: {:cont, Grid.put(g, x, r, ch)}, else: {:halt, g}
    end)
  end

  # The caret holds while keys are coming, then blinks.
  defp caret?(since), do: since < 0.4 or rem(floor((since - 0.4) / 0.5), 2) == 1

  defp controls(grid, s, p) do
    caret = if s.focus == 0 and caret?(p - s.typed), do: "█", else: " "

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

  # This port's own: the parts of a frame, by the places the frame draws
  # each thing at, and what is drawn there where the state shows: the focus
  # marker, the list open over the rows beneath the select, the saved note.
  # Spans are {column, cells, part}, a part being a name or a function
  # labelling the span's text.

  @input ~r/^([^ █]*)(█?)( *)$/u
  @word ~r/^(\S*)( *)$/
  @item ~r/^( )(>?)( +)(\S+)( *)$/
  @value ~r/^( *)(\d+)$/
  @choice ~r/\(\*\)|\( \)|\[x\]|\[ \]|\S+/
  @hints [
    {nil, " "},
    {"key", "tab"},
    {"hint", " next · "},
    {"key", "space"},
    {"hint", " change · "},
    {"key", "enter"},
    {"hint", " save "}
  ]

  @impl true
  def parts(%{lines: lines}, %{fields: [_ | _]} = options) do
    form = layout(options)
    for {line, y} <- Enum.with_index(lines), do: spans(line, form_row(form, y))
  end

  def parts(%{lines: lines}, %{title: title}) do
    open = String.at(Enum.at(lines, 5, ""), @field) == "┌"

    for {line, y} <- Enum.with_index(lines) do
      spans(line, row(y, line, title, open))
    end
  end

  defp row(0, _line, title, _open), do: top(title, @meta.cols)

  # The bottom row, the keys on its border.
  defp row(15, _line, _title, _open), do: bottom(@meta.cols, {@keys, &keys/1})

  defp row(14, line, _title, _open) do
    bc = @right - 10
    saved = if String.slice(line, @label, 5) == "saved", do: [{@label, 5, "status.ok"}], else: []

    save =
      if String.at(line, bc - 1) == ">",
        do: [{bc - 1, 1, "focus"}, {bc, 10, "button.focus"}],
        else: [{bc, 10, "button"}]

    sides(saved ++ [{bc - 13, 10, "button"} | save])
  end

  defp row(y, line, _title, open) when y in 2..12//2 do
    i = div(y - 2, 2)
    label = Enum.at(@fields, i)

    {marker, name} =
      if String.at(line, @label - 2) == ">",
        do: {[{@label - 2, 1, "focus"}], "label.focus"},
        else: {[], "label"}

    sides(marker ++ [{@label, String.length(label), name} | control(i, open)])
  end

  defp row(y, _line, _title, open) when y in 5..7 and open, do: sides(menu(y))
  defp row(_y, _line, _title, _open), do: sides([])

  # The top row: the name is " title ", from column 2 to the corner at most.
  defp top(title, cols) do
    n = Text.length(title)
    to = min(3 + n + 1, cols - 1)
    [{0, 2, "frame"}, {3, min(n, cols - 4), "title"}, {to, cols - to, "frame"}]
  end

  # The bottom row, keys (their text, and what labels it) on its border.
  defp bottom(cols, nil), do: [{0, cols, "frame"}]

  defp bottom(cols, {keys, label}) do
    x = cols - 2 - Text.length(keys)
    [{0, x, "frame"}, {x, Text.length(keys), label}, {cols - 2, 2, "frame"}]
  end

  # The border's sides around a row's spans.
  defp sides(spans, cols \\ @meta.cols), do: [{0, 1, "frame"} | spans] ++ [{cols - 1, 1, "frame"}]

  defp control(0, _open) do
    [{@field, 1, "frame.input"}, {@field + 2, @wide, &input/1}, {@right - 1, 1, "frame.input"}]
  end

  defp control(1, _open) do
    [
      {@field, 1, "frame.select"},
      {@field + 2, @wide - 1, &word/1},
      {@right - 3, 1, "frame.select"},
      {@right - 1, 1, "frame.select"}
    ]
  end

  defp control(i, true) when i in 2..3, do: menu(2 + 2 * i)
  defp control(i, false) when i in 2..3, do: [{@field, @right - @field, &choices/1}]
  defp control(4, _open), do: [{@field, @right - @field, &switch/1}]

  defp control(5, _open) do
    [{@field, @track, &slider/1}, {@field + @track, 5, &value/1}, {@right - 1, 1, "unit"}]
  end

  # The select's list over rows 5 to 8: its top, two items and its bottom.
  defp menu(y) when y in [5, 8], do: [{@field, @right - @field, "frame.menu"}]

  defp menu(_y) do
    w = @right - @field
    [{@field, 1, "frame.menu"}, {@field + 1, w - 2, &item/1}, {@right - 1, 1, "frame.menu"}]
  end

  defp input(text), do: Parts.captures(text, @input, ["field", "cursor"]) || [{nil, text}]
  defp word(text), do: Parts.captures(text, @word, ["field"]) || [{nil, text}]
  defp item(text), do: Parts.captures(text, @item, [nil, "focus", nil, "field"]) || [{nil, text}]
  defp value(text), do: Parts.captures(text, @value, [nil, "value"]) || [{nil, text}]
  defp keys(text), do: if(text == @keys, do: @hints, else: [{nil, text}])

  defp choices(text), do: Parts.matches(text, @choice, &choice/1)

  defp choice(mark) when mark in ["(*)", "[x]"], do: "checked"
  defp choice(mark) when mark in ["( )", "[ ]"], do: "unchecked"
  defp choice(_word), do: "field"

  defp switch(text), do: Parts.chars(text, &switch_cell/1)

  defp switch_cell(ch) when ch in ["▕", "▏", "░"], do: "track"
  defp switch_cell("▒"), do: "bar"
  defp switch_cell("█"), do: "knob"
  defp switch_cell(" "), do: nil
  defp switch_cell(_ch), do: "field"

  defp slider(text), do: Parts.chars(text, &slider_cell/1)

  defp slider_cell("━"), do: "bar"
  defp slider_cell("█"), do: "knob"
  defp slider_cell("─"), do: "track"
  defp slider_cell(_ch), do: nil

  # A line cut into spans, sorted by column, cells between them and after
  # the last in no part.
  defp spans(line, spans), do: spans(line, spans, 0, [])

  defp spans(rest, [], _at, acc), do: Parts.merge(Enum.reverse([{nil, rest} | acc]))

  defp spans(line, [{x, n, part} | spans], at, acc) do
    {gap, line} = take(line, x - at)
    {text, rest} = take(line, n)
    spans(rest, spans, x + n, Enum.reverse(label(text, part), [{nil, gap} | acc]))
  end

  defp label(text, part) when is_function(part, 1), do: part.(text)
  defp label(text, part), do: [{part, text}]

  # The first n characters of a line, and the rest.
  defp take(s, n) do
    rest = skip(s, n)
    {binary_part(s, 0, byte_size(s) - byte_size(rest)), rest}
  end

  defp skip(s, n) when n <= 0, do: s

  defp skip(s, n) do
    case String.next_codepoint(s) do
      {_ch, rest} -> skip(rest, n - 1)
      nil -> s
    end
  end

  # This port's own: a form the app describes, its `fields` drawn as
  # upstream draws each kind of control, on its rows and in its columns:
  # labels at column 4, controls from where the widest label leaves room
  # to the right edge four in from the border, the buttons under them. Each
  # row's things are worked out from the options alone, as {column, text,
  # part}, so drawing, labelling and clicks all read the same places.

  @blank_field %{
    type: "text",
    label: "",
    text: "",
    choices: [],
    choice: 0,
    checked: [],
    on: false,
    value: 0.0,
    min: 0.0,
    max: 100.0,
    step: 1.0,
    unit: ""
  }
  # The keys along the bottom, the most of them that fit.
  @form_keys (for pairs <- [
                    [{"tab", "next"}, {"space", "change"}, {"enter", "ok"}],
                    [{"tab", "next"}, {"space", "change"}],
                    [{"tab", "next"}]
                  ] do
                last = length(pairs) - 1

                runs =
                  pairs
                  |> Enum.with_index()
                  |> Enum.flat_map(fn {{key, hint}, i} ->
                    [{"key", key}, {"hint", " " <> hint <> if(i < last, do: " · ", else: " ")}]
                  end)

                runs = [{nil, " "} | runs]
                {Enum.map_join(runs, &elem(&1, 1)), runs}
              end)
  @control ~r/[\x00-\x1f\x7f]/
  @number ~r/^( *)(.*)$/

  defp layout(%{fields: fields, buttons: buttons, focus: focus, cols: cols} = options) do
    cols = trunc(cols)
    right = cols - 4
    fields = Enum.map(fields, &field/1)
    widest = fields |> Enum.map(&Text.length(&1.label)) |> Enum.max(fn -> 0 end)
    fx = min(@label + max(widest + 2, @field - @label), right - 12)
    buttons = place(buttons, right)
    stops = length(fields) + length(buttons)

    %{
      cols: cols,
      rows: 2 * length(fields) + 4,
      right: right,
      fx: fx,
      w: right - fx,
      fields: fields,
      buttons: buttons,
      stops: stops,
      focus: focus |> trunc() |> min(stops - 1) |> max(-1),
      title: plain(options.title),
      status: plain(options.status)
    }
  end

  # A field with every key, its text shown in one line.
  defp field(given) do
    f = Map.merge(@blank_field, given)
    choices = Enum.map(names(f), &plain/1)
    last = max(length(choices) - 1, 0)

    %{
      f
      | label: plain(f.label),
        text: plain(f.text),
        unit: plain(f.unit),
        choices: choices,
        choice: f.choice |> trunc() |> max(0) |> min(last)
    }
  end

  # A row of checkboxes with no names is one box.
  defp names(%{type: "checkbox", choices: []}), do: [""]
  defp names(f), do: f.choices

  defp plain(s), do: String.replace(s, @control, " ")

  # The buttons, right to left from the right edge, three apart: where each
  # starts (nil for one that does not fit), and its face.
  defp place(labels, right) do
    {placed, _} =
      labels
      |> Enum.reverse()
      |> Enum.map_reduce(right, fn label, edge ->
        face = face(label)
        x = edge - Text.length(face)
        if x >= @label, do: {{x, face}, x - 3}, else: {{nil, face}, -1}
      end)

    Enum.reverse(placed)
  end

  # "[  save  ]": the name centred in eight, or a space either side.
  defp face(label) do
    name = label |> plain() |> Text.slice(0, 24)
    n = Text.length(name)
    inner = max(n + 2, 8)
    left = div(inner - n, 2)
    "[" <> String.duplicate(" ", left) <> name <> String.duplicate(" ", inner - n - left) <> "]"
  end

  defp draw(form, caret?) do
    grid =
      form.cols
      |> Grid.new(form.rows)
      |> border()
      |> text(0, 2, " #{form.title} ")

    grid =
      case hints(form.cols) do
        nil -> grid
        {keys, _runs} -> text(grid, form.rows - 1, form.cols - 2 - Text.length(keys), keys)
      end

    grid =
      for y <- 1..(form.rows - 2), {x, s, part} <- items(form, y), reduce: grid do
        grid -> if part == :caret and not caret?, do: grid, else: text(grid, y, x, s)
      end

    IO.iodata_to_binary(Grid.to_iodata(grid))
  end

  defp hints(cols),
    do: Enum.find(@form_keys, fn {keys, _runs} -> cols - 2 - Text.length(keys) >= 2 end)

  defp form_row(form, 0), do: top(form.title, form.cols)

  defp form_row(%{rows: rows, cols: cols}, y) when y == rows - 1 do
    case hints(cols) do
      nil -> bottom(cols, nil)
      {keys, runs} -> bottom(cols, {keys, fn _text -> runs end})
    end
  end

  defp form_row(form, y) do
    spans = for {x, s, part} <- items(form, y), do: {x, Text.length(s), labeller(part)}
    sides(spans, form.cols)
  end

  defp labeller(:caret), do: &caret/1
  defp labeller(part), do: part

  defp caret("█"), do: [{"cursor", "█"}]
  defp caret(text), do: [{nil, text}]

  # A row's things, cut at the right edge.
  defp items(form, y) do
    for {x, s, part} <- row_items(form, y), x < form.right do
      {x, Text.slice(s, 0, form.right - x), part}
    end
  end

  defp row_items(%{fields: fields} = form, y) do
    n = length(fields)

    cond do
      y == 2 * n + 2 -> button_items(form)
      y >= 2 and rem(y, 2) == 0 and y <= 2 * n -> field_items(form, div(y - 2, 2))
      true -> []
    end
  end

  defp field_items(form, i) do
    f = Enum.at(form.fields, i)
    focused? = form.focus == i
    marker = if focused?, do: [{@label - 2, ">", "focus"}], else: []

    label =
      {@label, Text.slice(f.label, 0, form.fx - 6),
       if(focused?, do: "label.focus", else: "label")}

    marker ++ [label | widget(f, form, focused?)]
  end

  # A text field: the end of its text while in focus, so the caret shows.
  defp widget(%{type: "text", text: text}, %{fx: fx, w: w, right: right}, focused?) do
    inner = w - 4
    shown = if focused?, do: Text.slice(text, -(inner - 1)), else: Text.slice(text, 0, inner)
    caret = if focused?, do: [{fx + 2 + Text.length(shown), "█", :caret}], else: []

    [{fx, "[", "frame.input"}, {fx + 2, shown, "field"}] ++
      caret ++ [{right - 1, "]", "frame.input"}]
  end

  defp widget(%{type: "select"} = f, %{fx: fx, w: w, right: right}, _focused?) do
    [
      {fx, "[", "frame.select"},
      {fx + 2, f.choices |> Enum.at(f.choice, "") |> Text.slice(0, w - 5), "field"},
      {right - 3, "v", "frame.select"},
      {right - 1, "]", "frame.select"}
    ]
  end

  # Radio buttons, or checkboxes with a marker at the one keys tick.
  defp widget(%{type: type} = f, form, focused?) when type in ["radio", "checkbox"] do
    marked? = type == "checkbox" and focused? and length(f.choices) > 1

    Enum.flat_map(spots(f, form.fx), fn {j, x, name} ->
      {mark, part} = mark(f, j)
      sub = if marked? and j == f.choice, do: [{x - 1, ">", "focus"}], else: []
      sub ++ [{x, mark, part}, {x + 4, name, "field"}]
    end)
  end

  defp widget(%{type: "switch", on: on}, %{fx: fx}, _focused?) do
    knob = if on, do: 4, else: 0

    track =
      for i <- 0..5, into: "▕" do
        cond do
          i < knob -> "▒"
          i < knob + 2 -> "█"
          true -> "░"
        end
      end

    [{fx, track <> "▏ " <> if(on, do: "on", else: "off"), &switch/1}]
  end

  defp widget(%{type: "slider"} = f, %{fx: fx, w: w}, _focused?) do
    {track, shown, unit} = scale(f, w)
    k = notch(f, track)

    line =
      for i <- 0..(track - 1), into: "" do
        cond do
          i < k -> "━"
          i == k -> "█"
          true -> "─"
        end
      end

    [
      {fx, line, &slider/1},
      {fx + track, shown, &number/1},
      {fx + track + Text.length(shown), unit, &unit/1}
    ]
  end

  defp widget(_f, _form, _focused?), do: []

  # Where each of a row of choices starts: its mark, a space, its name,
  # three spaces to the next.
  defp spots(f, fx) do
    {spots, _} =
      f.choices
      |> Enum.with_index()
      |> Enum.map_reduce(fx, fn {name, j}, x -> {{j, x, name}, x + 4 + Text.length(name) + 3} end)

    spots
  end

  defp mark(%{type: "radio", choice: j}, j), do: {"(*)", "checked"}
  defp mark(%{type: "radio"}, _j), do: {"( )", "unchecked"}
  defp mark(f, j), do: if(checked?(f, j), do: {"[x]", "checked"}, else: {"[ ]", "unchecked"})

  defp checked?(f, j), do: Enum.at(f.checked, j, false) == true

  # A slider's track, its value as shown, and its unit: the value in five
  # (or more), the unit after it, the track the rest.
  defp scale(f, w) do
    shown = shown(f.value, f)
    n = max(5, Text.length(shown) + 1)
    unit = Text.slice(f.unit, 0, max(0, w - n - 4))
    {max(w - n - Text.length(unit), 1), Text.pad_start(shown, n), unit}
  end

  # The cell of the track the value is at.
  defp notch(f, track) do
    {lo, hi} = range(f)
    at = if hi == lo, do: 0, else: (f.value - lo) / (hi - lo)
    JSMath.round(max(0, min(1, at)) * (track - 1))
  end

  defp range(%{min: a, max: b}), do: {min(a, b), max(a, b)}

  defp shown(v, f), do: JSMath.to_fixed(v, places(f))

  # Places after the point the step (and where it starts) need, up to six.
  defp places(%{step: step, min: lo}), do: max(places(step), places(lo))

  defp places(x) do
    Enum.find(0..6, 6, fn d ->
      p = x * :math.pow(10, d)
      abs(p - Kernel.round(p)) < 1.0e-6
    end)
  end

  defp number(text), do: Parts.captures(text, @number, [nil, "value"]) || [{nil, text}]
  defp unit(text), do: Parts.captures(text, @number, [nil, "unit"]) || [{nil, text}]

  # The buttons' row: the status at the left, as far as the buttons leave
  # room, then the buttons that fit.
  defp button_items(%{fields: fields, buttons: buttons, focus: focus, status: status} = form) do
    n = length(fields)
    shown = for {{x, face}, j} <- Enum.with_index(buttons), x != nil, do: {x, face, n + j}

    room =
      case shown do
        [{x, _, _} | _] -> x - @label - 2
        [] -> form.right - @label
      end

    status =
      if status == "", do: [], else: [{@label, Text.slice(status, 0, max(room, 0)), "status"}]

    status ++
      Enum.flat_map(shown, fn
        {x, face, ^focus} -> [{x - 1, ">", "focus"}, {x, face, "button.focus"}]
        {x, face, _stop} -> [{x, face, "button"}]
      end)
  end

  # Using a form of the app's own: keys move the focus over the fields and
  # then the buttons, and change the field in focus; a click takes the
  # focus to what it lands on, and changes it as space would, at the choice
  # or the place clicked. Fields come back as given, but for the keys that
  # change.

  @impl true
  def handle_event(_event, %{fields: []}), do: :ignore

  def handle_event(event, options) do
    form = layout(options)

    case use(event, form, options.fields) do
      {focus, fields} -> {:ok, %{options | focus: focus, fields: fields}}
      :ignore -> :ignore
    end
  end

  defp use({:key, key}, %{focus: focus, fields: fields} = form, given) do
    result =
      if focus in 0..(length(fields) - 1)//1,
        do: field_key(key, Enum.at(fields, focus), Enum.at(given, focus)),
        else: button_key(key, form)

    case result do
      {:field, changed} -> {focus, List.replace_at(given, focus, changed)}
      {:focus, to} -> {to, given}
      :pass -> move(key, form, given)
      :ignore -> :ignore
    end
  end

  defp use({:click, x, y}, %{fields: fields} = form, given) when x > 0 and x < form.cols - 1 do
    n = length(fields)

    cond do
      y >= 2 and y <= 2 * n and rem(y, 2) == 0 ->
        i = div(y - 2, 2)
        changed = click(Enum.at(fields, i), Enum.at(given, i), x, form, form.focus == i)
        {i, List.replace_at(given, i, changed)}

      y == 2 * n + 2 ->
        form.buttons
        |> Enum.with_index(n)
        |> Enum.find_value(:ignore, fn {{bx, face}, stop} ->
          if bx != nil and x >= bx - 1 and x < bx + Text.length(face), do: {stop, given}
        end)

      true ->
        :ignore
    end
  end

  defp use(_event, _form, _given), do: :ignore

  # Moving the focus: tab and back tab go round, up and down stop at the
  # ends, enter steps on from a field, home and end go to the first and last.
  defp move(key, %{focus: focus, stops: stops, fields: fields}, given) do
    last = stops - 1

    to =
      case key do
        "tab" -> if focus < 0, do: 0, else: rem(focus + 1, stops)
        "back_tab" -> if focus <= 0, do: last, else: focus - 1
        "down" -> min(focus + 1, last)
        "up" -> if focus < 0, do: last, else: max(focus - 1, 0)
        "enter" when focus >= 0 and focus < length(fields) -> min(focus + 1, last)
        "home" -> 0
        "end" -> last
        _ -> nil
      end

    if to != nil and stops > 0, do: {to, given}, else: :ignore
  end

  # A button in focus: left and right move along the buttons; enter or
  # space presses it, which is the app's to act on, reading `focus`.
  defp button_key(key, %{focus: focus, fields: fields, stops: stops}) when focus >= 0 do
    case key do
      "left" -> {:focus, max(focus - 1, length(fields))}
      "right" -> {:focus, min(focus + 1, stops - 1)}
      key when key in ["enter", " "] -> :ignore
      _key -> :pass
    end
  end

  defp button_key(_key, _form), do: :pass

  defp field_key("backspace", %{type: "text"}, given) do
    text = Map.get(given, :text, "")
    {:field, Map.put(given, :text, String.slice(text, 0, max(String.length(text) - 1, 0)))}
  end

  # Printable characters are typed into a text field, up to 256.
  defp field_key(<<c>> = key, %{type: "text"}, given) when c in 0x20..0x7E do
    text = Map.get(given, :text, "")
    if String.length(text) < 256, do: {:field, Map.put(given, :text, text <> key)}, else: :ignore
  end

  defp field_key(key, %{type: type, choices: [_ | _] = choices, choice: j}, given)
       when type in ["select", "radio"] do
    last = length(choices) - 1

    case key do
      " " -> {:field, Map.put(given, :choice, rem(j + 1, last + 1))}
      "left" -> {:field, Map.put(given, :choice, max(j - 1, 0))}
      "right" -> {:field, Map.put(given, :choice, min(j + 1, last))}
      _key -> :pass
    end
  end

  # A row of checkboxes: left and right move between them, space ticks one.
  defp field_key(key, %{type: "checkbox", choices: choices, choice: j} = f, given) do
    case key do
      " " -> {:field, tick(f, given, j)}
      "left" -> {:field, Map.put(given, :choice, max(j - 1, 0))}
      "right" -> {:field, Map.put(given, :choice, min(j + 1, length(choices) - 1))}
      _key -> :pass
    end
  end

  defp field_key(key, %{type: "switch", on: on}, given) do
    case key do
      " " -> {:field, Map.put(given, :on, not on)}
      "left" -> {:field, Map.put(given, :on, false)}
      "right" -> {:field, Map.put(given, :on, true)}
      _key -> :pass
    end
  end

  # A slider moves a step, or ten with page up and down.
  defp field_key(key, %{type: "slider"} = f, given) do
    steps = %{"left" => -1, "right" => 1, "page_down" => -10, "page_up" => 10}

    case Map.fetch(steps, key) do
      {:ok, n} -> {:field, Map.put(given, :value, snap(f, f.value + n * step(f)))}
      :error -> :pass
    end
  end

  defp field_key(_key, _f, _given), do: :pass

  defp tick(f, given, j) do
    checked = f.checked ++ List.duplicate(false, max(j + 1 - length(f.checked), 0))

    given
    |> Map.put(:checked, List.update_at(checked, j, &(&1 != true)))
    |> Map.put(:choice, j)
  end

  defp step(%{step: step}) when step > 0, do: step

  defp step(f) do
    {lo, hi} = range(f)
    if hi > lo, do: (hi - lo) / 100, else: 1
  end

  # A value held to the range, a whole number of steps from its low end.
  defp snap(f, v) do
    {lo, hi} = range(f)
    s = step(f)
    v = lo + Kernel.round((v - lo) / s) * s
    v |> max(lo) |> min(hi) |> Kernel.*(1.0) |> Float.round(places(f))
  end

  # A click on a field: a choice picked or ticked, the switch flipped, the
  # slider set where it was clicked, a select in focus stepped on; anything
  # else on the row only takes the focus.
  defp click(%{type: "select"} = f, given, x, form, true) when x >= form.fx do
    case field_key(" ", f, given) do
      {:field, changed} -> changed
      _pass -> given
    end
  end

  defp click(%{type: type} = f, given, x, form, _focused?) when type in ["radio", "checkbox"] do
    case Enum.find(spots(f, form.fx), fn {_j, at, name} ->
           x >= at and x < min(at + 4 + Text.length(name), form.right)
         end) do
      nil -> given
      {j, _, _} when type == "radio" -> Map.put(given, :choice, j)
      {j, _, _} -> tick(f, given, j)
    end
  end

  defp click(%{type: "switch", on: on}, given, x, %{fx: fx}, _focused?)
       when x >= fx and x < fx + 12,
       do: Map.put(given, :on, not on)

  defp click(%{type: "slider"} = f, given, x, %{fx: fx, w: w}, _focused?) do
    {track, _, _} = scale(f, w)
    {lo, hi} = range(f)

    if x >= fx and x < fx + track,
      do: Map.put(given, :value, snap(f, lo + (hi - lo) * (x - fx) / max(track - 1, 1))),
      else: given
  end

  defp click(_f, given, _x, _form, _focused?), do: given

  @impl true
  def describe(%{fields: []}), do: nil

  def describe(options) do
    form = layout(options)
    title = form.title |> String.trim() |> Text.slice(0, 40)
    {shown, rest} = form.fields |> Enum.map(&say/1) |> Enum.reject(&(&1 == "")) |> fit(160)
    more = if rest == 0, do: "", else: ", and #{rest} more"

    "#{if title == "", do: "form", else: title}: " <>
      Enum.join(shown, ", ") <> more <> focus_on(form)
  end

  # As many of the things said as fit in `room` characters, and how many
  # are left over.
  defp fit(said, room) do
    {shown, _} =
      Enum.reduce_while(said, {[], 0}, fn s, {shown, n} ->
        n = n + String.length(s) + 2
        if n <= room or shown == [], do: {:cont, {[s | shown], n}}, else: {:halt, {shown, n}}
      end)

    {Enum.reverse(shown), length(said) - length(shown)}
  end

  # A field in words: its label, then what it holds.
  defp say(f) do
    [f.label, holds(f)]
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" ")
    |> Text.slice(0, 60)
  end

  defp holds(%{type: "text", text: ""}), do: "empty"
  defp holds(%{type: "text", text: text}), do: text

  defp holds(%{type: type} = f) when type in ["select", "radio"],
    do: Enum.at(f.choices, f.choice, "")

  defp holds(%{type: "checkbox", choices: [""]} = f),
    do: if(checked?(f, 0), do: "on", else: "off")

  defp holds(%{type: "checkbox"} = f) do
    case for({name, j} <- Enum.with_index(f.choices), checked?(f, j), do: name) do
      [] -> "none"
      names -> Enum.join(names, " and ")
    end
  end

  defp holds(%{type: "switch", on: on}), do: if(on, do: "on", else: "off")
  defp holds(%{type: "slider"} = f), do: shown(f.value, f) <> f.unit
  defp holds(_f), do: ""

  defp focus_on(%{focus: focus, fields: fields, buttons: buttons}) do
    n = length(fields)

    cond do
      focus < 0 ->
        ""

      focus < n ->
        "; focus on " <> name_of(Enum.at(fields, focus).label, "field #{focus + 1}")

      true ->
        {_x, face} = Enum.at(buttons, focus - n)
        "; focus on " <> name_of(face |> String.trim("[") |> String.trim("]"), "button")
    end
  end

  defp name_of(name, fallback) do
    case name |> String.trim() |> Text.slice(0, 40) do
      "" -> fallback
      name -> name
    end
  end
end
