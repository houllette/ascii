defmodule Ascii.Pieces.Glitch do
  @moduledoc """
  A pixel word that tears into sliding slices in short bursts.

  A word set in a blocky pixel face holds clean, then breaks up in short
  digital bursts: slices slide sideways and lose registration, cells
  corrupt. Three bursts in every seven seconds, then it comes round again.
  Your word, for an error page, a "no signal" or a heading with some edge.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): it starts
  afresh with the new text, the bursts keeping their time, being a function
  of play time.

    * `text` - the word or words, in capitals whatever their case. The face
      has `A` to `Z`, `0` to `9`, the space and `. , : ! ? - ' " / & + · *
      # ( ) @ % = _`, and draws `?` for any other character. A pixel is two
      columns wide when the text fits, about five letters, and one column
      when it does not; past about twelve letters it is cut at the frame's
      edge. Default `"noise"`.

  The frame is always 64 by 13, the word centred in it.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `letter` - the word's pixels, wherever a slice slides them, a smear
      drags them or a block copies them; and `letter.<n>`, each letter by
      its place in the text from 1, counting every character, spaces too
      (so `s` is `letter.4` in "no signal").
    * `ghost` - the copy a slid slice leaves behind where it was, cyan.
    * `noise` - corrupted cells and a block's static, red.
    * `tear` - the line torn through the word, grey.

  Each frame is labelled as it was drawn, from its time.

  ## Keys and clicks

  It takes none: it is a word to read, and `Ascii.handle_event/2`
  ignores every event. A Phoenix player given `interactive` and `notify`
  still tells your LiveView where it was clicked, and on which part
  (`Ascii.part_at/4`): which letter, say.

  ## Screen readers

  `Ascii.describe/1` reads the text, its spaces closed up: "glitch:
  error 404". A text of only spaces gives the piece's name and note.

  ## Example

  ```elixir
  word = Ascii.new!("glitch", options: %{text: "error 404"}, parts: true)
  {frame, _word} = Ascii.frame(word, 3.0)
  frame.palette
  #=> [nil, "#39c5cf", "#8b949e", "#f85149"]

  Ascii.describe(word)
  #=> "glitch: error 404"

  heading = Ascii.new!("glitch", options: %{text: "ok"}, parts: %{"letter.1" => "#3fb950", "letter.2" => "#58a6ff"})
  {frame, _heading} = Ascii.frame(heading, 0.0)
  frame.palette
  #=> [nil, "#3fb950", "#58a6ff"]
  ```

  ```heex
  <Ascii.Phoenix.live_player id="oops" piece="glitch" options={%{text: "error 500"}} parts />
  ```

  Ported from `src/pieces/glitch.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath, Parts}
  import Bitwise, only: [&&&: 2, >>>: 2]

  @meta %Ascii.Meta{
    name: "glitch",
    category: :type,
    note: "a pixel word that tears into sliding slices in short bursts",
    cols: 64,
    rows: 13,
    fps: 15,
    options: %{text: "noise"},
    loop: 7,
    parts: [{"letter", nil}, {"ghost", "#39c5cf"}, {"noise", "#f85149"}, {"tear", "#8b949e"}]
  }

  # 5x7 glyphs: the character, then one base-32 digit per row (bit 4 is the left pixel).
  @packed "0ehjlphe14c4444e2eh1248v3v2421he426aiv225vgu11he668guhhe7v1248888ehhehhe9ehhf12c" <>
            "AehhvhhhBuhhuhhuCehgggheDuhhhhhuEvgguggvFvggugggGehgnhhfHhhhvhhhIe44444eJ72222ic" <>
            "KhikokihLggggggvMhrllhhhNhhpljhhOehhhhhePuhhugggQehhhlidRuhhukihSfgge11uTv444444" <>
            "UhhhhhheVhhhhha4WhhhlllaXhha4ahhYhha4444Zv1248gv.0000004,0000048:0040040!4444404" <>
            "?eh12404-000e000'4400000\"aa00000/11248gg&cik8lid+044v440·0004000*04lel40#aavavaa" <>
            "(2488842)8422248@ehnlngf%op248j3=00v0v00_000000v 0000000"
  @font @packed
        |> String.codepoints()
        |> Enum.chunk_every(8)
        |> Map.new(fn [ch | digits] -> {ch, Enum.map(digits, &String.to_integer(&1, 32))} end)

  # One cycle: clean holds of at least 1.5s broken by bursts of {start, end, peak strength}.
  @period 7
  # Glitch states per second.
  @steps 15
  @bursts [{0.8, 1.2, 0.55}, {2.75, 3.3, 1}, {4.85, 5.3, 0.75}]
  # An empty cell, from nowhere.
  @blank {" ", nil}
  @noise {"▓", "▒", "░", "▚", "▞", "▙", "▟", "▛", "▜", "#", "%", "=", "+"}
  @tears {"▀", "▄", "─", "═"}

  @impl true
  def meta, do: @meta

  # Lays the text out as rows of pixels, trimming each glyph to its inked
  # columns; and each column's letter, by its place in the text from 1 (nil
  # between letters). A character that is two capitals (ß) is both.
  defp bitmap(text) do
    text
    |> String.codepoints()
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {char, n} ->
      for ch <- String.codepoints(String.upcase(char)), do: {ch, n}
    end)
    |> Enum.reduce({List.duplicate([], 7), []}, fn {ch, n}, {px, owners} ->
      g = Map.get(@font, ch, @font["?"])
      inked = for x <- 0..4, Enum.any?(g, &((&1 &&& 16 >>> x) != 0)), do: x

      {lo, hi} =
        if ch == " ",
          do: {0, 2},
          else: {Enum.min(inked, fn -> 4 end), Enum.max(inked, fn -> 0 end)}

      spacer = if hd(px) == [], do: [], else: [0]

      px =
        Enum.zip_with(px, g, fn row, b ->
          row ++ spacer ++ for(x <- lo..hi//1, do: if((b &&& 16 >>> x) != 0, do: 1, else: 0))
        end)

      {px, owners ++ Enum.map(spacer, fn _ -> nil end) ++ Enum.map(lo..hi//1, fn _ -> n end)}
    end)
  end

  @impl true
  def init(%{text: text}) do
    %{cols: cols, rows: rows} = @meta
    {px, owners} = bitmap(text)
    px = Enum.map(px, &List.to_tuple/1)
    w = tuple_size(hd(px))
    # Pixels two cells wide when the word fits.
    sx = if w * 2 <= cols - 8, do: 2, else: 1
    x0 = max(0, Int32.sar(cols - w * sx, 1))
    y0 = Int32.sar(rows - 7, 1)

    ink =
      for {row, y} <- Enum.with_index(px),
          c <- 0..(cols - 1),
          x = JSMath.floor((c - x0) / sx),
          c >= x0 and x < w and elem(row, x) == 1,
          into: MapSet.new(),
          do: (y0 + y) * cols + c

    clean =
      for r <- 0..(rows - 1) do
        for c <- 0..(cols - 1), do: if(MapSet.member?(ink, r * cols + c), do: "█", else: " ")
      end

    owners = List.to_tuple(owners)

    # Each column's letter, as laid out clean.
    columns =
      List.to_tuple(
        for c <- 0..(cols - 1), x = JSMath.floor((c - x0) / sx) do
          if c >= x0 and x < w, do: elem(owners, x)
        end
      )

    %{ink: ink, y0: y0, columns: columns, clean: Enum.intersperse(clean, ?\n)}
  end

  defp ink?(ink, r, c) do
    %{cols: cols, rows: rows} = @meta
    r >= 0 and r < rows and c >= 0 and c < cols and MapSet.member?(ink, r * cols + c)
  end

  # How hard the picture is breaking at cycle time u, 0 when clean.
  defp strength(u) do
    Enum.find_value(@bursts, 0, fn {s, e, peak} ->
      if u >= s and u < e, do: peak * (0.35 + 0.65 * :math.sin(:math.pi() * (u - s) / (e - s)))
    end)
  end

  defp next(rand), do: Int32.mulberry32(rand)

  @impl true
  def frame(state, t, _env) do
    %{cols: cols, rows: rows} = @meta

    case picture(state, t) do
      :clean ->
        {state.clean, nil, state}

      out ->
        lines =
          for r <- 0..(rows - 1) do
            for c <- 0..(cols - 1), do: at(out, r * cols + c)
          end

        {Enum.intersperse(lines, ?\n), nil, state}
    end
  end

  # The picture at t: clean, or broken as cells by index, each its glyph and
  # where it came from: a letter's place in the text, :ghost, :noise, :tear,
  # or nil for a hole.
  defp picture(state, t) do
    u = JSMath.mod(JSMath.mod(t, @period) + @period, @period)
    step = JSMath.floor(u * @steps + 1.0e-6)
    rand = step * 7919 + 17
    s = strength(step / @steps)

    # A clean flicker inside a burst.
    {s, rand} =
      if s > 0,
        do: with({x, rand} <- next(rand), do: {if(x < 0.12, do: 0, else: s), rand}),
        else: {s, rand}

    if s == 0, do: :clean, else: broken(state, s, rand)
  end

  defp broken(%{ink: ink, y0: y0, columns: columns}, s, rand) do
    %{cols: cols, rows: rows} = @meta

    # Bands of rows slide sideways.
    {x, rand} = next(rand)

    {shift, rand} =
      Enum.reduce(1..(1 + JSMath.floor(x * (1 + 2 * s))), {%{}, rand}, &band(&1, &2, s, y0))

    # The slid slices lose registration: a second channel stays behind where
    # the slice was.
    {x, rand} = next(rand)
    split = x < 0.4 + 0.5 * s
    {x, rand} = next(rand)
    sub = 0.02 + 0.08 * s * x
    holes = 0.01 + 0.04 * s

    {out, rand} =
      for r <- 0..(rows - 1), c <- 0..(cols - 1), reduce: {%{}, rand} do
        {out, rand} ->
          from = c - Map.get(shift, r, 0)

          if ink?(ink, r, from) do
            {v, rand} = next(rand)

            cond do
              v < sub ->
                {n, rand} = next(rand)
                noise = elem(@noise, JSMath.floor(n * tuple_size(@noise)))
                {Map.put(out, r * cols + c, {noise, :noise}), rand}

              v < sub + holes ->
                {Map.put(out, r * cols + c, @blank), rand}

              true ->
                {Map.put(out, r * cols + c, {"█", elem(columns, from)}), rand}
            end
          else
            {out, rand}
          end
      end

    out = if split, do: registration(out, shift, ink), else: out
    {out, rand} = smears(out, s, y0, rand)
    {out, rand} = blocks(out, s, y0, {ink, columns}, rand)
    {out, rand} = tear(out, s, y0, rand)
    jump(out, s, rand)
  end

  defp at(out, k), do: out |> Map.get(k, @blank) |> elem(0)
  defp from(out, k), do: out |> Map.get(k, @blank) |> elem(1)

  defp band(_b, {shift, rand}, s, y0) do
    rows = @meta.rows
    {a, rand} = next(rand)
    top = y0 - 1 + JSMath.floor(a * 8)
    {b, rand} = next(rand)
    h = 1 + JSMath.floor(b * 3)
    {c, rand} = next(rand)
    {d, rand} = next(rand)
    dx = if(c < 0.5, do: -1, else: 1) * (3 + JSMath.floor(d * (2 + 8 * s)))

    shift =
      Enum.reduce(top..(min(top + h, rows) - 1)//1, shift, fn r, shift ->
        Map.put(shift, r, JSMath.i8(Map.get(shift, r, 0) + dx))
      end)

    {shift, rand}
  end

  # It only shows on slices that slid well clear, where it clears the main
  # ink by a column, so it reads as a copy left behind rather than a shadow.
  defp registration(main, shift, ink) do
    %{cols: cols, rows: rows} = @meta

    for r <- 0..(rows - 1),
        abs(Map.get(shift, r, 0)) >= 5,
        c <- 0..(cols - 1),
        k = r * cols + c,
        at(main, k) == " " and (c == 0 or at(main, k - 1) == " ") and
          (c == cols - 1 or at(main, k + 1) == " ") and ink?(ink, r, c),
        reduce: main,
        do: (out -> Map.put(out, k, {"▒", :ghost}))
  end

  # Smears: a row's pixels drag out to one side and fade.
  defp smears(out, s, y0, rand) do
    cols = @meta.cols
    {x, rand} = next(rand)

    {count, rand} =
      if x < 0.45 * s,
        do: with({y, rand} <- next(rand), do: {1 + JSMath.floor(y * 2), rand}),
        else: {0, rand}

    Enum.reduce(1..count//1, {out, rand}, fn _, {out, rand} ->
      {a, rand} = next(rand)
      r = y0 + JSMath.floor(a * 7)
      {b, rand} = next(rand)
      c = run_to_ink(out, r * cols, JSMath.floor(b * cols))
      {d, rand} = next(rand)
      len = 4 + JSMath.floor(d * 14 * s)
      # The pixel dragged out, and so its letter.
      letter = from(out, r * cols + c)

      out =
        Enum.reduce(1..len//1, out, fn j, out ->
          if c + j < cols,
            do: Map.put(out, r * cols + c + j, {smear(j, len), letter}),
            else: out
        end)

      {out, rand}
    end)
  end

  defp run_to_ink(out, base, c) do
    if c < @meta.cols - 1 and at(out, base + c) != "█", do: run_to_ink(out, base, c + 1), else: c
  end

  defp smear(j, len) when j > len - 2, do: "░"
  defp smear(j, len) when j > len - 5, do: "▒"
  defp smear(_j, _len), do: "▓"

  # Macroblocks: a patch of the picture copied in from somewhere else.
  defp blocks(out, s, y0, {ink, columns}, rand) do
    %{cols: cols, rows: rows} = @meta
    {x, rand} = next(rand)

    {count, rand} =
      if x < 0.5 * s,
        do: with({y, rand} <- next(rand), do: {1 + JSMath.floor(y * 2), rand}),
        else: {0, rand}

    Enum.reduce(1..count//1, {out, rand}, fn _, {out, rand} ->
      {[a, b, c, d, e, f], rand} = take(rand, 6)
      bw = 3 + JSMath.floor(a * 10)
      bh = 1 + JSMath.floor(b * 2)
      br = y0 + JSMath.floor(c * 7)
      bc = JSMath.floor(d * (cols - bw))
      dr = JSMath.floor(e * 5) - 2
      dc = JSMath.floor(f * 21) - 10

      for r <- br..(min(br + bh, rows) - 1)//1, c <- bc..(bc + bw - 1), reduce: {out, rand} do
        {out, rand} ->
          {z, rand} = next(rand)

          cell =
            cond do
              ink?(ink, r + dr, c + dc) ->
                {if(z < 0.3, do: "▓", else: "█"), elem(columns, c + dc)}

              z < 0.15 * s ->
                {"░", :noise}

              true ->
                @blank
            end

          {Map.put(out, r * cols + c, cell), rand}
      end
    end)
  end

  defp take(rand, n), do: Enum.map_reduce(1..n, rand, fn _, rand -> next(rand) end)

  # A tear line through the word, or just above or below it.
  defp tear(out, s, y0, rand) do
    cols = @meta.cols
    {x, rand} = next(rand)

    if x < 0.5 * s do
      {[a, b, c, d], rand} = take(rand, 4)
      r = y0 - 1 + JSMath.floor(a * 9)
      start = JSMath.floor(b * cols * 0.6)
      len = 6 + JSMath.floor(c * cols * 0.5)
      g = elem(@tears, JSMath.floor(d * 4))

      Enum.reduce(start..(min(cols, start + len) - 1)//1, {out, rand}, fn col, {out, rand} ->
        k = r * cols + col

        if at(out, k) == " " do
          {Map.put(out, k, {g, :tear}), rand}
        else
          {e, rand} = next(rand)
          {if(e < 0.5, do: Map.put(out, k, {g, :tear}), else: out), rand}
        end
      end)
    else
      {out, rand}
    end
  end

  # At full strength the whole picture sometimes jumps a row.
  defp jump(out, s, rand) when s > 0.7 do
    %{cols: cols, rows: rows} = @meta
    {x, rand} = next(rand)

    if x < 0.25 do
      {y, _rand} = next(rand)
      dir = if y < 0.5, do: 1, else: -1

      for r <- 0..(rows - 1),
          from = r - dir,
          from >= 0 and from < rows,
          c <- 0..(cols - 1),
          into: %{},
          do: {r * cols + c, Map.get(out, from * cols + c, @blank)}
    else
      out
    end
  end

  defp jump(out, _s, _rand), do: out

  # This port's own: the parts of a frame, from where each cell came as the
  # frame was drawn, played again from its time.

  @impl true
  def parts(%{lines: lines, t: t}, options) do
    %{cols: cols} = @meta
    state = init(options)

    from =
      case picture(state, t) do
        :clean ->
          fn k -> if MapSet.member?(state.ink, k), do: elem(state.columns, rem(k, cols)) end

        out ->
          &from(out, &1)
      end

    for {line, r} <- Enum.with_index(lines) do
      Parts.cells(line, fn
        ?\s, _c -> nil
        _cp, c -> name(from.(r * cols + c))
      end)
    end
  end

  defp name(n) when is_integer(n), do: "letter.#{n}"
  defp name(nil), do: nil
  defp name(where), do: Atom.to_string(where)

  @impl true
  def describe(%{text: text}) do
    case String.split(text) do
      [] -> nil
      words -> "glitch: " <> Enum.join(words, " ")
    end
  end
end
