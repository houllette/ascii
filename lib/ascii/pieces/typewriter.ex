defmodule Ascii.Pieces.Typewriter do
  @moduledoc """
  Phrases typed and deleted in turn behind a blinking cursor.

  Types each phrase a key at a time at an uneven human pace, now and then
  fixing a typo, holds it under a blinking cursor, deletes it, types the
  next. Give it your own: a hero line's "we make …", a list of features.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it
  starts afresh with them.

    * `prefix` - the text before every phrase, which stays as the phrases
      come and go. Default `"i make "`.
    * `phrases` - typed in turn, each held finished for about two seconds,
      then deleted; after the last comes the first again. Each is cut to
      what fits after the prefix in the line's 40 characters, and the line
      is centred on its longest. A typo now and then is a key beside the
      right one on the keyboard, typed and taken back. An empty list types
      nothing. Default `["small tools.", "quiet websites.", "things that
      last.", "notes for later."]`.

  The line is always 44 by 3.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `prefix` - the prefix.
    * `phrase` - the phrase as typed so far, slips and all, blue.
    * `cursor` - the blinking cursor, yellow.

  ## Keys and clicks

  It takes none: it types for itself, and `Ascii.handle_event/2`
  ignores every event. A Phoenix player given `interactive` and `notify`
  still tells your LiveView where it was clicked, and on which part
  (`Ascii.part_at/4`): the phrase, say, and the text typed so far.

  ## Screen readers

  `Ascii.describe/1` reads each phrase after the prefix, four at most,
  their closing stops dropped: "typewriter: we ship on fridays; we ship
  with tests". With no phrase, it gives the piece's name and note.

  ## Example

  ```elixir
  line = Ascii.new!("typewriter", options: %{prefix: "we ship ", phrases: ["on fridays.", "with tests."]}, parts: true)
  {frame, line} = Ascii.frame(line, 0.0)
  frame.text =~ "we ship on fridays."
  #=> true

  Ascii.describe(line)
  #=> "typewriter: we ship on fridays; we ship with tests"
  ```

  ```heex
  <Ascii.Phoenix.live_player id="hero" piece="typewriter" options={%{prefix: "we make ", phrases: @things}} parts />
  ```

  Ported from `src/pieces/typewriter.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath, Parts}
  alias Ascii.Kit.Text

  @meta %Ascii.Meta{
    name: "typewriter",
    category: :type,
    note: "phrases typed and deleted in turn behind a blinking cursor",
    cols: 44,
    rows: 3,
    fps: 20,
    options: %{
      prefix: "i make ",
      phrases: ["small tools.", "quiet websites.", "things that last.", "notes for later."]
    },
    parts: [
      {"prefix", nil},
      {"phrase", "#58a6ff"},
      {"cursor", "#d29922"}
    ]
  }

  @cursor "▌"
  # Seconds a finished phrase stays, and the line waits empty before the next.
  @hold 2.2
  @empty 0.5
  # Keys next to each other on a keyboard, for believable slips.
  @key_rows ["qwertyuiop", "asdfghjkl", "zxcvbnm"]

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{prefix: prefix, phrases: phrases}) do
    %{cols: cols} = @meta
    head = prefix
    keep = max(0, cols - 4 - Text.length(head))
    list = Enum.map(if(phrases == [], do: [""], else: phrases), &Text.slice(&1, 0, keep))

    # The whole loop as a list of {time, text on the line}, laid out once.
    {%{at: period, events: events, done: done}, _rand} =
      Enum.reduce(list, {%{at: 0, text: "", events: [], done: []}, 31}, &lay_out/2)

    # Frame 0 shows the first phrase finished, cursor lit, shortly before it is deleted.
    offset = List.last(done) + @hold - 0.75
    width = Text.length(head) + Enum.max(Enum.map(list, &Text.length/1)) + 1

    %{
      head: head,
      events: Enum.reverse(events),
      period: period,
      offset: offset,
      x: max(0, Integer.floor_div(cols - width, 2))
    }
  end

  defp key(st, next, wait),
    do: %{st | at: st.at + wait, text: next, events: [{st.at + wait, next} | st.events]}

  defp rand(r), do: Int32.mulberry32(r)

  defp type_delay(ch, r) do
    {a, r} = rand(r)
    {space, r} = if ch == " ", do: with({b, r} <- rand(r), do: {0.05 + b * 0.08, r}), else: {0, r}
    {c, r} = rand(r)
    {0.06 + a * 0.09 + space + if(c < 0.05, do: 0.3, else: 0), r}
  end

  defp slip(ch, r) do
    Enum.find_value(@key_rows, {nil, r}, fn row ->
      keys = String.graphemes(row)

      case Enum.find_index(keys, &(&1 == ch)) do
        nil ->
          nil

        0 ->
          {Enum.at(keys, 1), r}

        i when i == length(keys) - 1 ->
          {Enum.at(keys, i - 1), r}

        i ->
          {x, r} = rand(r)
          {Enum.at(keys, i + if(x < 0.5, do: -1, else: 1)), r}
      end
    end)
  end

  defp lay_out(phrase, {st, r}) do
    chars = phrase |> Text.chars() |> List.to_tuple()
    n = tuple_size(chars)

    # Some phrases get one slip: a wrong key, a key or two more, a pause, then backspaces.
    {x, r} = rand(r)

    {typo, r} =
      if x < 0.5 and n > 5 do
        {y, r} = rand(r)
        {3 + JSMath.floor(y * (n - 4)), r}
      else
        {-1, r}
      end

    {st, r} =
      Enum.reduce(0..(n - 1)//1, {st, r}, fn i, {st, r} ->
        ch = elem(chars, i)
        {wrong, r} = if i == typo, do: slip(ch, r), else: {nil, r}
        {st, r} = if wrong, do: fumble(st, r, chars, i, wrong), else: {st, r}
        {delay, r} = type_delay(ch, r)
        pause = if i > 0 and String.contains?(".,!?", elem(chars, i - 1)), do: 0.15, else: 0
        {key(st, st.text <> ch, delay + pause), r}
      end)

    st = %{st | done: [st.at | st.done], at: st.at + @hold}

    # Held backspace: one press, a beat, then it repeats.
    st =
      Enum.reduce(0..(n - 1)//1, st, fn k, st ->
        key(st, Text.slice(st.text, 0, -1), Enum.at([0, 0.18], k, 0.045))
      end)

    {%{st | at: st.at + @empty}, r}
  end

  defp fumble(st, r, chars, i, wrong) do
    {x, r} = rand(r)
    more = min(JSMath.floor(x * 3), tuple_size(chars) - i - 1)
    {delay, r} = type_delay(elem(chars, i), r)
    st = key(st, st.text <> wrong, delay)

    {st, r} =
      Enum.reduce(1..more//1, {st, r}, fn k, {st, r} ->
        {delay, r} = type_delay(elem(chars, i + k), r)
        {key(st, st.text <> elem(chars, i + k), delay), r}
      end)

    {y, r} = rand(r)
    st = %{st | at: st.at + (0.25 + y * 0.2)}

    st =
      Enum.reduce(0..more//1, st, fn k, st ->
        key(st, Text.slice(st.text, 0, -1), if(k > 0, do: 0.07, else: 0.1))
      end)

    {st, r}
  end

  @impl true
  def frame(state, t, _env) do
    %{cols: cols, rows: rows} = @meta
    %{period: period, events: events} = state
    now = JSMath.mod(JSMath.mod(t + state.offset, period) + period, period)

    {line, last} =
      Enum.reduce_while(events, {"", 0}, fn {at, s}, acc ->
        if at > now, do: {:halt, acc}, else: {:cont, {s, at}}
      end)

    # Solid while keys land, blinking once the cursor has sat still.
    idle = now - last
    lit = idle < 0.45 or JSMath.mod(idle - 0.45, 1.06) > 0.53
    body = state.head <> line <> if(lit, do: @cursor, else: "")
    out = (String.duplicate(" ", state.x) <> body) |> Text.slice(0, cols) |> Text.pad_end(cols)
    blank = String.duplicate(" ", cols)
    lines = for r <- 0..(rows - 1), do: if(r == div(rows, 2), do: out, else: blank)
    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # This port's own: the parts of a frame. The middle row is the prefix, at
  # the column init/1 centres the line at, then the phrase so far, then the
  # cursor if it is lit; the rows above and below are blank.

  @impl true
  def parts(%{lines: lines}, %{prefix: prefix, phrases: phrases}) do
    %{cols: cols, rows: rows} = @meta
    head = Text.length(prefix)
    keep = max(0, cols - 4 - head)
    longest = phrases |> Enum.map(&min(Text.length(&1), keep)) |> Enum.max(fn -> 0 end)
    x = max(0, Integer.floor_div(cols - (head + longest + 1), 2))

    for {line, y} <- Enum.with_index(lines) do
      if y == div(rows, 2), do: typed(line, x, head), else: Parts.line(line, nil)
    end
  end

  defp typed(line, x, head) do
    {pad, rest} = split(line, x)
    {prefix, rest} = split(rest, head)
    body = String.trim_trailing(rest, " ")
    trail = binary_part(rest, byte_size(body), byte_size(rest) - byte_size(body))

    {phrase, cursor} =
      if String.ends_with?(body, @cursor),
        do: {binary_part(body, 0, byte_size(body) - byte_size(@cursor)), @cursor},
        else: {body, ""}

    Parts.merge([
      {nil, pad},
      {"prefix", prefix},
      {"phrase", phrase},
      {"cursor", cursor},
      {nil, trail}
    ])
  end

  # The first n characters of s, and the rest.
  defp split(s, n) do
    first = Text.slice(s, 0, n)
    {first, binary_part(s, byte_size(first), byte_size(s) - byte_size(first))}
  end

  # This port's own: the phrases in full, for a screen reader.

  @stop ~r/[.,;:]+$/u

  @impl true
  def describe(%{prefix: prefix, phrases: phrases}) do
    case for(p <- phrases, said = words(prefix <> p), said != "", do: said) do
      [] -> nil
      said -> "typewriter: " <> listed(said)
    end
  end

  defp words(s), do: s |> String.split() |> Enum.join(" ") |> String.replace(@stop, "")

  # Four at most, each its first 80 characters, then how many more.
  defp listed(said) do
    {shown, rest} = Enum.split(said, 4)
    more = if rest == [], do: "", else: "; and #{length(rest)} more"
    Enum.map_join(shown, "; ", &String.slice(&1, 0, 80)) <> more
  end
end
