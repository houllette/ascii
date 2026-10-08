defmodule AsciiArt.Pieces.Terminal do
  @moduledoc """
  A shell session: typed commands, output, scrolling, clear.

  A shell session in a rounded frame. Each command is typed a key at a time,
  its output prints line by line and scrolls, and a clear starts over.

  Ported from `src/pieces/terminal.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Text

  @meta %AsciiArt.Meta{
    name: "terminal",
    category: :ui,
    note: "a shell session: typed commands, output, scrolling, clear",
    cols: 62,
    rows: 18,
    fps: 20,
    options: %{prompt: "~/notes $", title: "~/notes"}
  }

  # Each command: what is typed, seconds before its output, then the output.
  # A number in the output is a pause before the next line.
  @session [
    {"ls", 0.08, ["drafts   ideas.txt   photos   reading.txt   todo.txt"]},
    {"cat todo.txt", 0.06,
     [
       "[x] water the plants",
       "[x] back up the photos",
       "[ ] fix the bike light",
       "[ ] call home on sunday"
     ]},
    {~s(echo "[ ] buy stamps" >> todo.txt), 0.05, []},
    {"wc -l todo.txt", 0.08, ["5 todo.txt"]},
    {"du -sh photos", 0.7, ["2.4G    photos"]},
    {"ping -c 3 localhost", 0.15,
     [
       "PING localhost (127.0.0.1): 56 data bytes",
       0.8,
       "64 bytes from 127.0.0.1: icmp_seq=0 ttl=64 time=0.041 ms",
       0.9,
       "64 bytes from 127.0.0.1: icmp_seq=1 ttl=64 time=0.067 ms",
       0.9,
       "64 bytes from 127.0.0.1: icmp_seq=2 ttl=64 time=0.052 ms",
       0.3,
       "",
       "--- localhost ping statistics ---",
       "3 packets transmitted, 3 received, 0% packet loss",
       "round-trip min/avg/max = 0.041/0.053/0.067 ms"
     ]},
    {"clear", 0, []}
  ]

  @inner 62 - 4
  @view 18 - 2

  @impl true
  def meta, do: @meta

  @impl true
  def init(%{prompt: prompt, title: title}) do
    %{cols: cols} = @meta

    # Lay the session out in time once: when each prompt shows, each key lands,
    # and each output line prints. The loop ends the moment clear runs.
    {steps, _} =
      Enum.map_reduce(@session, {0, Int32.to_int32(5)}, fn {cmd, wait, out}, {at, rand} ->
        shown = at
        {r, rand} = Int32.mulberry32(rand)
        at = at + (0.9 + r * 0.6)

        {keys, {at, rand}} =
          cmd
          |> Text.chars()
          |> Enum.map_reduce({at, rand}, fn ch, {at, rand} -> {at, key(ch, at, rand)} end)

        enter = at + 0.12
        at = enter + wait

        {lines, at} =
          Enum.flat_map_reduce(out, at, fn
            pause, at when is_number(pause) -> {[], at + pause}
            line, at -> {[{at + 0.035, line}], at + 0.035}
          end)

        step = %{cmd: cmd, shown: shown, keys: keys, lines: lines, enter: enter}
        {step, {at + 0.05, rand}}
      end)

    period = List.last(steps).enter + 0.1
    # Frame 0 lands part way through typing the ping, with the screen most of the way full.
    start = steps |> Enum.at(5) |> Map.fetch!(:keys) |> Enum.at(9)

    name = if title != "", do: "─ " <> Text.slice(title, 0, cols - 6) <> " ", else: ""
    top = "╭" <> Text.slice(name <> String.duplicate("─", cols), 0, cols - 2) <> "╮"
    bottom = "╰" <> String.duplicate("─", cols - 2) <> "╯"

    %{
      steps: steps,
      period: period,
      start: start,
      head: prompt <> " ",
      top: top,
      bottom: bottom
    }
  end

  # When the next key lands after this one.
  defp key(ch, at, rand) do
    {a, rand} = Int32.mulberry32(rand)

    {space, rand} =
      if ch == " " do
        {b, rand} = Int32.mulberry32(rand)
        {b * 0.12, rand}
      else
        {0, rand}
      end

    {c, rand} = Int32.mulberry32(rand)
    {at + (0.06 + a * 0.07 + space + if(c < 0.04, do: 0.35, else: 0)), rand}
  end

  @impl true
  def frame(%{steps: steps, period: period, start: start, head: head} = state, t, _env) do
    now = JSMath.mod(JSMath.mod(t + start, period) + period, period)
    {lines, cursor, ref} = screen(steps, head, now)
    n = length(lines)
    top = max(0, n + if(match?({^n, _}, cursor), do: 1, else: 0) - @view)
    # Solid while keys land, blinking once the cursor has sat still.
    blink = JSMath.mod(now - ref, 1) < 0.55

    shown = Enum.drop(lines, top)
    shown = shown ++ List.duplicate("", max(0, @view - length(shown)))

    body =
      shown
      |> Enum.take(@view)
      |> Enum.with_index(top)
      |> Enum.map(fn {line, i} ->
        s = cell(line)

        s =
          case cursor do
            {^i, c} when blink and c < @inner ->
              Text.slice(s, 0, c) <> "█" <> Text.slice(s, c + 1)

            _ ->
              s
          end

        "│ " <> s <> " │"
      end)

    {Enum.intersperse([state.top | body] ++ [state.bottom], ?\n), nil, state}
  end

  defp cell(s) do
    if Text.length(s) > @inner, do: Text.slice(s, 0, @inner), else: Text.pad_end(s, @inner)
  end

  # The lines on screen, where the cursor is ({line index, column} or nil),
  # and the moment it last moved, for the blink.
  defp screen(steps, head, now) do
    {lines, cursor, ref} = Enum.reduce_while(steps, {[], nil, 0}, &screen_step(&1, &2, head, now))
    {Enum.reverse(lines), cursor, ref}
  end

  defp screen_step(%{shown: shown}, acc, _head, now) when shown > now, do: {:halt, acc}

  defp screen_step(s, {lines, _cursor, _ref}, head, now) do
    typed = Enum.count(s.keys, &(&1 <= now))
    lines = [head <> Text.slice(s.cmd, 0, typed) | lines]
    ref = if typed > 0, do: Enum.at(s.keys, typed - 1), else: s.shown

    if now < s.enter do
      {:halt, {lines, {length(lines) - 1, Text.length(head) + typed}, ref}}
    else
      {lines, ref} =
        Enum.reduce_while(s.lines, {lines, s.enter}, fn {k, line}, {lines, ref} ->
          if k > now, do: {:halt, {lines, ref}}, else: {:cont, {[line | lines], k}}
        end)

      # While the command runs the cursor waits at the start of the next line.
      {:cont, {lines, {length(lines), 0}, ref}}
    end
  end
end
