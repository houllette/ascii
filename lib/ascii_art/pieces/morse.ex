defmodule AsciiArt.Pieces.Morse do
  @moduledoc """
  A lamp keying morse, the marks on a tape, letters decoded.

  A signal lamp keys out a message. The marks run off along a tape from the
  head, and each letter is written beneath its group once it is complete.

  Ported from `src/pieces/morse.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.JSMath
  alias AsciiArt.Kit.Grid

  @meta %AsciiArt.Meta{
    name: "morse",
    category: :type,
    note: "a lamp keying morse, the marks on a tape, letters decoded",
    cols: 64,
    rows: 19,
    fps: 15,
    options: %{text: "hello world"}
  }

  @code %{
    "A" => ".-",
    "B" => "-...",
    "C" => "-.-.",
    "D" => "-..",
    "E" => ".",
    "F" => "..-.",
    "G" => "--.",
    "H" => "....",
    "I" => "..",
    "J" => ".---",
    "K" => "-.-",
    "L" => ".-..",
    "M" => "--",
    "N" => "-.",
    "O" => "---",
    "P" => ".--.",
    "Q" => "--.-",
    "R" => ".-.",
    "S" => "...",
    "T" => "-",
    "U" => "..-",
    "V" => "...-",
    "W" => ".--",
    "X" => "-..-",
    "Y" => "-.--",
    "Z" => "--..",
    "0" => "-----",
    "1" => ".----",
    "2" => "..---",
    "3" => "...--",
    "4" => "....-",
    "5" => ".....",
    "6" => "-....",
    "7" => "--...",
    "8" => "---..",
    "9" => "----.",
    "." => ".-.-.-",
    "," => "--..--",
    "?" => "..--..",
    "!" => "-.-.--",
    "'" => ".----.",
    "/" => "-..-.",
    "-" => "-....-",
    "&" => ".-..."
  }
  # Seconds per dot.
  @unit 0.12
  @ramp {" ", "·", ":", "░", "▒", "▓", "█"}
  # The lamp's centre, where marks land on the tape, and the tape's row.
  @cx 31
  @cy 6
  @head 64 - 7
  @tape 16

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{text: text}) do
    # Lay the message out in dot units: when each mark is on, and where each letter sits.
    {on, letters, at} =
      text
      |> String.upcase()
      |> String.codepoints()
      |> Enum.reduce({MapSet.new(), [], 0}, &lay_out/2)

    # A long rest before it starts again.
    l = max(at + 12, 20)
    state = %{on: on, l: l, letters: Enum.reverse(letters)}

    # Seconds of play already sent at frame 0, chosen so the lamp is lit and the tape full.
    warm = warm(state, min(45, l - 1))

    lamps =
      for glow <- [0, 0.35, 1],
          paper <- [false, true],
          into: %{},
          do: {{glow, paper}, lamp(glow, paper)}

    Map.merge(state, %{t0: (warm + 0.5) * @unit, lamps: lamps})
  end

  defp lay_out(ch, {on, letters, at}) do
    case @code do
      %{^ch => code} ->
        start = at

        {on, at} =
          code
          |> String.to_charlist()
          |> Enum.reduce({on, at}, fn m, {on, at} ->
            len = if m == ?., do: 1, else: 3
            {Enum.into(at..(at + len - 1), on), at + len + 1}
          end)

        {on, [{ch, start, at - 1} | letters], at + 2}

      # A word gap is seven, three already follow the letter before.
      _ ->
        {on, letters, at + 4}
    end
  end

  defp lit?(%{on: on, l: l}, x), do: MapSet.member?(on, Integer.mod(x, l))

  defp warm(state, warm) do
    if not lit?(state, warm) and warm < state.l * 2, do: warm(state, warm + 1), else: warm
  end

  # The lamp face: a lens, a dark gap, then the housing ring.
  defp lamp(glow, paper) do
    for r <- 0..11,
        c <- (@cx - 10)..(@cx + 10),
        cell = face(glow, paper, c, r),
        cell != nil,
        do: cell
  end

  defp face(glow, paper, c, r) do
    dx = (c - @cx) / 2
    dy = r - @cy
    d = JSMath.hypot(dx, dy)

    cond do
      d <= 2.75 ->
        # Lit, the glass is brightest at the centre; dark, only a glint shows.
        glint = if dx < -0.3 and dy < -0.3 and abs(d - 1.9) < 0.45, do: 0.34, else: 0
        q = d / 2.75
        b = if glow != 0, do: glow * (0.62 + 0.38 * (1 - q * q)), else: glint
        i = JSMath.round(b * (tuple_size(@ramp) - 1))
        {c, r, elem(@ramp, if(paper, do: tuple_size(@ramp) - 1 - i, else: i))}

      d > 3.2 and d <= 4.15 ->
        {c, r, if(d > 3.8, do: "▓", else: "█")}

      true ->
        nil
    end
  end

  @impl true
  def frame(state, t, env) do
    %{cols: cols, rows: rows} = @meta
    now = (t + state.t0) / @unit
    unit = JSMath.floor(now)

    # Full while keyed, with a brief afterglow as the shutter closes.
    glow =
      cond do
        lit?(state, unit) -> 1
        lit?(state, unit - 1) and now - unit < 0.5 -> 0.35
        true -> 0
      end

    g =
      Enum.reduce(state.lamps[{glow, env.paper}], Grid.new(cols, rows), fn {c, r, ch}, g ->
        Grid.put(g, c, r, ch)
      end)

    g = g |> rays(glow) |> yoke()

    # The tape: marks behind the head, blank paper ahead of it.
    g =
      g
      |> Grid.put_string(0, @tape - 1, dashes(cols))
      |> Grid.put_string(0, @tape + 1, dashes(cols))

    g =
      Enum.reduce(0..@head, g, fn c, g ->
        if lit?(state, unit - (@head - c)), do: Grid.put(g, c, @tape, "█"), else: g
      end)

    g = g |> Grid.put(@head, @tape - 1, "┬") |> Grid.put(@head, @tape + 1, "┴")

    # Each letter under the middle of its group once its last mark is sent.
    lap = Integer.floor_div(unit, state.l)

    g =
      for k <- (lap - 1)..lap,
          {ch, s, e} <- state.letters,
          k * state.l + e <= unit - 1,
          reduce: g do
        g ->
          Grid.put_string(
            g,
            @head - (unit - JSMath.round(k * state.l + (s + e) / 2)),
            @tape + 2,
            ch
          )
      end

    {Grid.to_iodata(g), nil, state}
  end

  defp dashes(n), do: String.duplicate("─", n)

  # Rays while it shines.
  defp rays(g, 0), do: g

  defp rays(g, glow) do
    n = if glow == 1, do: 3, else: 1

    Enum.reduce(0..(n - 1), g, fn k, g ->
      g
      |> Grid.put(@cx - 13 - 2 * k, @cy, "─")
      |> Grid.put(@cx + 13 + 2 * k, @cy, "─")
      |> Grid.put(@cx, @cy - 5 - k, "│")
      |> Grid.put(@cx - 6 - k, @cy - 4 - k, "╲")
      |> Grid.put(@cx + 6 + k, @cy - 4 - k, "╱")
    end)
  end

  # The yoke it swings in, a post and a foot.
  defp yoke(g) do
    g =
      Enum.reduce(@cy..(@cy + 4), g, fn r, g ->
        g |> Grid.put(@cx - 10, r, "│") |> Grid.put(@cx + 10, r, "│")
      end)

    g
    |> Grid.put(@cx - 10, @cy, "o")
    |> Grid.put(@cx + 10, @cy, "o")
    |> Grid.put_string(
      @cx - 10,
      @cy + 5,
      "╰" <> String.duplicate("─", 9) <> "┬" <> String.duplicate("─", 9) <> "╯"
    )
    |> Grid.put(@cx, @cy + 6, "│")
    |> Grid.put_string(@cx - 5, @cy + 7, "▄▄▄▄█▀█▄▄▄▄")
  end
end
