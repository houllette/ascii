defmodule Ascii.Pieces.Terminal do
  @moduledoc """
  A shell session: typed commands, output, scrolling, clear.

  A shell session in a rounded frame. Each command is typed a key at a time,
  its output prints line by line and scrolls, and a clear starts over. As
  upstream draws it, it plays a session of its own; give it a `history`
  and it shows yours: commands and their output, or a log's tail.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`). New
  history carries on from what is on screen: with `typing`, what has been
  typed stays, new entries are typed from then on, and new lines of output
  under the last command print; without, the history is shown as it stands.

    * `history` - what the terminal shows instead of upstream's session: a
      list of `%{command: "...", output: ["...", ...]}`, each command after
      the prompt with the lines it printed under it. An entry without a
      command is output alone, so a log's tail is
      `history: [%{output: lines}]`. The newest lines are at the bottom,
      older ones scrolled away, and lines too long for the width are cut.
      After a command the prompt comes back, the cursor blinking after it;
      after output alone the cursor waits at the start of the next line, as
      it does while a command runs. Default `[]`: upstream's session.
    * `typing` - with `history`, play it out: each command typed a key at a
      time and its output printed a line at a time, once through, and then
      hold. Default `false`: the history shown at once.
    * `prompt` - before each command; a space follows it. Default
      `"~/notes $"`.
    * `title` - in the top of the frame; `""` for none. Default `"~/notes"`.
    * `cols`, `rows` - the frame's size, the border included, 12 to 200 by
      3 to 60; upstream's 62 by 18 by default.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `frame` - the window's border, grey; `title`, its title.
    * `prompt` - the prompt, blue.
    * `command` - what is typed after it.
    * `output` - what the commands print; a todo list's items marked
      `checked` (`[x]`), green, or `unchecked` (`[ ]`), grey.
    * `cursor` - the cursor, yellow.

  A line that reads as both a command and output (a prompt made to look
  like output) is in no part.

  ## Keys and clicks

  It takes none: it shows a session, and `Ascii.handle_event/2` ignores
  every event. To make it a shell of your own, take the keys in your app
  and give it the new `history`. A Phoenix player given `interactive` and
  `notify` still tells your LiveView where it was clicked, and on which
  part (`Ascii.part_at/4`), a command or a line of output, say.

  ## Screen readers

  `Ascii.describe/1` tells the history: "terminal my_app: 1 command, the
  last mix test", or for output alone "terminal ~/notes: 2 lines of output,
  the last: two". Playing upstream's session, it gives the piece's name and
  note.

  ## Example

  ```elixir
  history = [%{command: "mix test", output: ["...........", "11 tests, 0 failures"]}]
  options = %{title: "my_app", prompt: "$", history: history, cols: 40, rows: 8}
  term = Ascii.new!("terminal", options: options, parts: true)
  {frame, _term} = Ascii.frame(term, 0.0)
  Enum.at(frame.lines, 3)
  #=> "│ 11 tests, 0 failures                 │"

  Ascii.describe(term)
  #=> "terminal my_app: 1 command, the last mix test"
  ```

  ```heex
  <Ascii.Phoenix.live_player id="log" piece="terminal" options={%{title: "deploy", history: [%{output: @log}]}} parts />
  ```

  Ported from `src/pieces/terminal.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath, Parts}
  alias Ascii.Kit.Text

  @meta %Ascii.Meta{
    name: "terminal",
    category: :ui,
    note: "a shell session: typed commands, output, scrolling, clear",
    cols: 62,
    rows: 18,
    fps: 20,
    options: %{
      prompt: "~/notes $",
      title: "~/notes",
      history: [],
      typing: false,
      cols: 62,
      rows: 18
    },
    bounds: %{cols: {12, 200}, rows: {3, 60}},
    shapes: %{history: [%{command: "", output: [""]}]},
    parts: [
      {"frame", "#8b949e"},
      {"title", nil},
      {"prompt", "#58a6ff"},
      {"command", nil},
      {"output", nil},
      {"checked", "#3fb950"},
      {"unchecked", "#8b949e"},
      {"cursor", "#d29922"}
    ]
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

  # Seconds a command runs before its output, in a history typed out.
  @wait 0.1

  @impl true
  def meta, do: @meta

  @impl true
  def size(%{cols: cols, rows: rows}), do: {trunc(cols), trunc(rows)}

  @impl true
  def init(options), do: setup(options, 0.0, nil)

  # A history typed out keeps what it has typed, and types what is new from
  # the play time reached; anything else starts afresh.
  @impl true
  def update(%{t: t} = state, options) do
    old =
      if Map.get(state, :typing) == true,
        do: {state.history, Enum.take(state.steps, length(state.history))}

    setup(options, t, old)
  end

  defp setup(%{prompt: prompt, title: title} = options, since, old) do
    {cols, rows} = size(options)

    %{
      head: prompt <> " ",
      top: top(title, cols),
      bottom: "╰" <> String.duplicate("─", cols - 2) <> "╯",
      inner: cols - 4,
      view: rows - 2,
      t: since
    }
    |> Map.merge(session(options, since, old))
  end

  # Lay upstream's session out in time once: when each prompt shows, each
  # key lands, and each output line prints. The loop ends the moment clear
  # runs.
  defp session(%{history: []}, _since, _old) do
    {steps, _} =
      Enum.map_reduce(@session, {0, Int32.to_int32(5)}, fn {cmd, wait, out}, {at, rand} ->
        shown = at
        {r, rand} = Int32.mulberry32(rand)
        at = at + (0.9 + r * 0.6)
        {keys, {at, rand}} = keys(cmd, at, rand)
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
    %{steps: steps, period: period, start: start}
  end

  defp session(%{history: history, typing: typing}, since, old),
    do: %{steps: schedule(history, typing, since, old), history: history, typing: typing}

  # The history as steps, as upstream's session's: shown at once, or typed
  # out from `since`, the steps of `old` kept for the entries that stand.
  # After a command, the prompt waits for the next.
  defp schedule(history, false, _since, _old) do
    steps =
      Enum.map(history, fn entry ->
        lines = for line <- output(entry), do: {0, line}

        case command(entry) do
          "" ->
            %{cmd: nil, shown: 0, lines: lines}

          cmd ->
            %{
              cmd: cmd,
              shown: 0,
              keys: List.duplicate(0, Text.length(cmd)),
              lines: lines,
              enter: 0
            }
        end
      end)

    steps ++ prompt(List.last(history), 0)
  end

  defp schedule(history, true, since, old) do
    {kept, at} = keep(history, old || {[], []}, since)

    {steps, at} =
      history
      |> Enum.drop(length(kept))
      |> Enum.with_index(length(kept))
      |> Enum.map_reduce(max(at, since), &typed/2)

    kept ++ steps ++ prompt(List.last(history), at)
  end

  # The steps of the entries that stand from before, and when the next may
  # start: an entry as it was keeps its step, and one whose output has grown
  # prints the new lines from `since`.
  defp keep(history, {old_history, old_steps}, since),
    do: keep(history, old_history, old_steps, since, [], 0)

  defp keep([entry | history], [entry | old_history], [step | steps], since, acc, _at),
    do: keep(history, old_history, steps, since, [step | acc], step.done)

  defp keep([entry | _], [was | _], [step | _], since, acc, at) do
    {old, new} = {output(was), output(entry)}

    if command(entry) == command(was) and List.starts_with?(new, old) do
      {lines, done} = print(Enum.drop(new, length(old)), max(step.done - 0.05, since))
      step = %{step | lines: step.lines ++ lines, done: done + 0.05}
      {Enum.reverse([step | acc]), step.done}
    else
      {Enum.reverse(acc), at}
    end
  end

  defp keep(_history, _old_history, _steps, _since, acc, at), do: {Enum.reverse(acc), at}

  # An entry typed out from `at`, its timings seeded by its place.
  defp typed({entry, i}, at) do
    case command(entry) do
      "" ->
        {lines, done} = print(output(entry), at)
        {%{cmd: nil, shown: at, lines: lines, done: done + 0.05}, done + 0.05}

      cmd ->
        {r, rand} = Int32.mulberry32(Int32.to_int32(5 + i))
        {keys, {typed, _rand}} = keys(cmd, at + (0.9 + r * 0.6), rand)
        enter = typed + 0.12
        {lines, done} = print(output(entry), enter + @wait)
        step = %{cmd: cmd, shown: at, keys: keys, lines: lines, enter: enter, done: done + 0.05}
        {step, done + 0.05}
    end
  end

  # When each key of a command lands, from `at`.
  defp keys(cmd, at, rand) do
    cmd
    |> Text.chars()
    |> Enum.map_reduce({at, rand}, fn ch, {at, rand} -> {at, key(ch, at, rand)} end)
  end

  defp print(lines, at),
    do: Enum.map_reduce(lines, at, fn line, at -> {{at + 0.035, line}, at + 0.035} end)

  defp prompt(entry, at) do
    if command(entry) == "",
      do: [],
      else: [%{cmd: "", shown: at, keys: [], lines: [], enter: nil}]
  end

  defp command(entry), do: Map.get(entry, :command, "")
  defp output(entry), do: Map.get(entry, :output, [])

  defp top(title, cols) do
    name = if title != "", do: "─ " <> Text.slice(title, 0, cols - 6) <> " ", else: ""
    "╭" <> Text.slice(name <> String.duplicate("─", cols), 0, cols - 2) <> "╮"
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
  def frame(%{steps: steps, head: head, inner: inner, view: view} = state, t, _env) do
    now = clock(state, t)
    {lines, cursor, ref} = screen(steps, head, now)
    n = length(lines)
    top = max(0, n + if(match?({^n, _}, cursor), do: 1, else: 0) - view)
    # Solid while keys land, blinking once the cursor has sat still.
    blink = JSMath.mod(now - ref, 1) < 0.55

    shown = Enum.drop(lines, top)
    shown = shown ++ List.duplicate("", max(0, view - length(shown)))

    body =
      shown
      |> Enum.take(view)
      |> Enum.with_index(top)
      |> Enum.map(fn {line, i} ->
        s = cell(line, inner)

        s =
          case cursor do
            {^i, c} when blink and c < inner ->
              Text.slice(s, 0, c) <> "█" <> Text.slice(s, c + 1)

            _ ->
              s
          end

        "│ " <> s <> " │"
      end)

    {Enum.intersperse([state.top | body] ++ [state.bottom], ?\n), nil, %{state | t: t}}
  end

  # Upstream's session loops; a history plays once and holds.
  defp clock(%{period: period, start: start}, t),
    do: JSMath.mod(JSMath.mod(t + start, period) + period, period)

  defp clock(_history, t), do: max(t, 0.0)

  defp cell(s, inner) do
    if Text.length(s) > inner, do: Text.slice(s, 0, inner), else: Text.pad_end(s, inner)
  end

  # The lines on screen, where the cursor is ({line index, column} or nil),
  # and the moment it last moved, for the blink.
  defp screen(steps, head, now) do
    {lines, cursor, ref} = Enum.reduce_while(steps, {[], nil, 0}, &screen_step(&1, &2, head, now))
    {Enum.reverse(lines), cursor, ref}
  end

  defp screen_step(%{shown: shown}, acc, _head, now) when shown > now, do: {:halt, acc}

  # Output alone: its lines as they print, the cursor waiting under them.
  defp screen_step(%{cmd: nil} = s, {lines, _cursor, _ref}, _head, now) do
    {lines, ref} = printed(s.lines, lines, s.shown, now)
    {:cont, {lines, {length(lines), 0}, ref}}
  end

  defp screen_step(s, {lines, _cursor, _ref}, head, now) do
    typed = Enum.count(s.keys, &(&1 <= now))
    lines = [head <> Text.slice(s.cmd, 0, typed) | lines]
    ref = if typed > 0, do: Enum.at(s.keys, typed - 1), else: s.shown

    # A prompt with no enter to come waits for the next command.
    if s.enter == nil or now < s.enter do
      {:halt, {lines, {length(lines) - 1, Text.length(head) + typed}, ref}}
    else
      {lines, ref} = printed(s.lines, lines, s.enter, now)

      # While the command runs the cursor waits at the start of the next line.
      {:cont, {lines, {length(lines), 0}, ref}}
    end
  end

  defp printed(timed, lines, ref, now) do
    Enum.reduce_while(timed, {lines, ref}, fn {k, line}, {lines, ref} ->
      if k > now, do: {:halt, {lines, ref}}, else: {:cont, {[line | lines], k}}
    end)
  end

  @impl true
  def describe(%{history: []}), do: nil

  def describe(%{history: history, title: title}) do
    name = if title == "", do: "terminal", else: "terminal " <> title
    commands = for entry <- history, cmd = command(entry), cmd != "", do: cmd
    lines = Enum.flat_map(history, &output/1)

    case {commands, lines} do
      {[], []} -> name <> ": empty"
      {[], lines} -> "#{name}: #{count(lines, "line")} of output, the last: #{short(lines)}"
      {commands, _} -> "#{name}: #{count(commands, "command")}, the last #{short(commands)}"
    end
  end

  defp count([_], one), do: "1 " <> one
  defp count(list, one), do: "#{length(list)} #{one}s"

  defp short(list), do: list |> List.last() |> String.trim() |> String.slice(0, 60)

  # This port's own: the parts of a frame, read off its lines. Inside the
  # border each line is a command after the prompt (the prompt the options
  # give, then the start of one of the session's commands), a line the
  # session prints, or blank; the cursor is after what is typed, or at the
  # start of a blank line. The session is upstream's script or the history,
  # its lines cut to the width as the frame cuts them.

  @commands for {cmd, _wait, _out} <- @session, do: cmd
  @outputs for {_cmd, _wait, out} <- @session, line <- out, is_binary(line), do: line
  @typed ~r/^(.*?)(█?)( *)$/u
  @output [
    {~r/^(\[x\])( )(.*?)( *)$/u, ["checked", nil, "output"]},
    {~r/^(\[ \])( )(.*?)( *)$/u, ["unchecked", nil, "output"]},
    {~r/^(.*?)( *)$/u, ["output"]}
  ]
  @blank ~r/^(█?)( *)$/u

  @impl true
  def parts(%{lines: [top | lines], cols: cols}, %{prompt: prompt, title: title} = options) do
    inner = cols - 4
    {body, bottom} = Enum.split(lines, -1)
    # The prompt and the head it makes, as much of them as a line shows.
    head = {Text.slice(prompt, 0, inner), Text.slice(prompt <> " ", 0, inner)}
    known = known(options, inner)

    [top_parts(top, title, cols) | Enum.map(body, &row(&1, head, known))] ++
      Enum.map(bottom, &[{"frame", &1}])
  end

  # The session's commands, and its output as a line shows it.
  defp known(%{history: []}, inner), do: {@commands, shown(@outputs, inner)}

  defp known(%{history: history}, inner) do
    commands = for entry <- history, cmd = command(entry), cmd != "", do: cmd
    {commands, history |> Enum.flat_map(&output/1) |> shown(inner)}
  end

  defp shown(lines, inner),
    do: MapSet.new(lines, &(&1 |> Text.slice(0, inner) |> String.trim_trailing(" ")))

  defp top_parts(line, "", _cols), do: [{"frame", line}]

  defp top_parts(line, title, cols) do
    name = Text.slice(title, 0, cols - 6)

    case line do
      "╭─ " <> rest ->
        if String.starts_with?(rest, name <> " ") do
          rest = binary_slice(rest, byte_size(name <> " ")..-1//1)
          [{"frame", "╭─"}, {nil, " "}, {"title", name}, {nil, " "}, {"frame", rest}]
        else
          [{nil, line}]
        end

      _ ->
        [{nil, line}]
    end
  end

  defp row("│ " <> rest = line, head, known) do
    if String.ends_with?(rest, " │") do
      s = binary_part(rest, 0, byte_size(rest) - byte_size(" │"))

      Parts.merge(
        [{"frame", "│"}, {nil, " "}] ++ inside(s, head, known) ++ [{nil, " "}, {"frame", "│"}]
      )
    else
      [{nil, line}]
    end
  end

  defp row(line, _head, _known), do: [{nil, line}]

  defp inside(s, head, {commands, outputs}) do
    case {command_line(s, head, commands), MapSet.member?(outputs, String.trim_trailing(s, " "))} do
      {nil, true} -> Parts.first(s, @output)
      {command, false} when command != nil -> command
      _ -> Parts.captures(s, @blank, ["cursor"]) || [{nil, s}]
    end
  end

  # A command's line: the prompt, then a start of one of the commands.
  defp command_line(s, {shown, head}, commands) do
    with true <- String.starts_with?(s, head),
         rest = binary_slice(s, byte_size(head)..-1//1),
         [typed, cursor, pad] <- Regex.run(@typed, rest, capture: :all_but_first),
         true <- Enum.any?(commands, &String.starts_with?(&1, typed)) do
      sep = binary_slice(head, byte_size(shown)..-1//1)

      Parts.merge([
        {"prompt", shown},
        {nil, sep},
        {"command", typed},
        {"cursor", cursor},
        {nil, pad}
      ])
    else
      _ -> nil
    end
  end
end
