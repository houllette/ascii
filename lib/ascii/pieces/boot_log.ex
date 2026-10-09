defmodule Ascii.Pieces.BootLog do
  @moduledoc """
  A self test counts memory, then the boot log scrolls by.

  A machine starting up. The firmware tests its memory and probes its
  devices, the kernel prints timestamped lines, services start, and a login
  waits. That is upstream's boot, which it plays by default; give it
  `steps` and it is your app's own log instead: a deploy, a setup wizard,
  a CI run.

  ## Options

  Give them to `Ascii.new/2` as `options:`, and new ones while it plays
  with `Ascii.put_options/2` (or a Phoenix player's `options`): new
  steps take their place at once, and as the stars and the cursor keep play
  time, nothing jumps.

    * `steps` - the log, a list of `%{text: "...", status: "..."}`, a line
      each, systemd style: `"ok"` is `[  OK  ] text`, `"warn"`
      `[ WARN ] text`, `"fail"` `[FAILED] text`, and `"busy"`, a step under
      way, has three stars sweeping in its brackets; any other status (or
      none) is the text alone. The newest steps are at the bottom, older
      ones scrolled away as upstream scrolls its boot, with a cursor
      blinking on the line after the last. Default `[]`.
    * `title` - a heading over a rule, which stays put as the steps scroll
      under it. Default `""`. With no `steps` and no `title` (the
      defaults) it plays upstream's boot; a title alone is an empty log,
      for an app with no steps yet.
    * `cols`, `rows` - the frame's size, 24 to 200 by 3 to 60; upstream's
      64 by 16 by default. Upstream's boot lays its self test out to the
      width, and lines longer than the frame are cut at its edge.

  ## Colours

  In one ink, or a gradient, with `:ink` and `:gradient` (see
  `Ascii.Ink`); part by part with `:parts` (see `Ascii.Parts`),
  `parts: true` taking the colours suggested here:

    * `title` - the firmware's heading, or the log's title.
    * `rule` - the rule under it, grey.
    * `status.ok` - `ok`, `link up` and `[  OK  ]`, green; `status.warn`,
      `[ WARN ]`, yellow; `status.fail`, `[FAILED]`, red; and
      `status.busy`, a test or probe under way, or a start job's or a busy
      step's stars, cyan.
    * `message` - a kernel or service line's text, or a step's.
    * `label`, `detail` - a self test row's device, and what was found.
    * `bar`, `track` - the memory test's done, blue, and to do, grey; with
      its `address`, grey, and `percent`.
    * `key`, `hint` - the keys the firmware offers, yellow, and what they
      do, grey.
    * `time` - a kernel line's timestamp, grey.
    * `prompt`, `cursor` - the login prompt, and the cursor at the login or
      after the steps.

  ## Keys and clicks

  It takes none: it shows a log, and `Ascii.handle_event/2` ignores
  every event. A Phoenix player given `interactive` and `notify` still
  tells your LiveView where it was clicked, and on which part
  (`Ascii.part_at/4`): a step's `status.fail`, say, or its `message`
  and its text, to show what went wrong.

  ## Screen readers

  `Ascii.describe/1` counts the steps by status, naming a failed or a
  running one, as "deploy web: 4 steps, 2 ok, 1 warning, 1 failed (health
  check)"; with a title and no steps, "deploy web: no steps yet". Playing
  upstream's boot, it gives the piece's name and note.

  ## Example

  ```elixir
  steps = [
    %{text: "built release 1.4.2", status: "ok"},
    %{text: "disk 81% full", status: "warn"},
    %{text: "migrating database", status: "busy"}
  ]

  log = Ascii.new!("boot-log", options: %{title: "deploy web", steps: steps}, parts: true)
  Ascii.describe(log)
  #=> "deploy web: 3 steps, 1 ok, 1 warning, 1 running (migrating database)"

  done = List.replace_at(steps, 2, %{text: "migrated database", status: "ok"})
  log = Ascii.put_options!(log, steps: done ++ [%{text: "health check", status: "fail"}])
  {frame, _log} = Ascii.frame(log, 1.0)
  frame.text =~ "[FAILED] health check"
  #=> true
  ```

  ```heex
  <Ascii.Phoenix.live_player id="deploy" piece="boot-log" options={%{title: "deploy web", steps: @steps}} parts />
  ```

  Ported from `src/pieces/boot-log.ts` in bas3line/ascii (MIT).
  """
  @behaviour Ascii.Piece

  alias Ascii.{Int32, JSMath, Parts}
  alias Ascii.Kit.Text

  @meta %Ascii.Meta{
    name: "boot log",
    category: :ui,
    note: "a self test counts memory, then the boot log scrolls by",
    cols: 64,
    rows: 16,
    fps: 15,
    options: %{steps: [], title: "", cols: 64, rows: 16},
    bounds: %{cols: {24, 200}, rows: {3, 60}},
    shapes: %{steps: [%{text: "", status: ""}]},
    parts: [
      {"title", nil},
      {"rule", "#8b949e"},
      {"label", nil},
      {"detail", nil},
      {"status.ok", "#3fb950"},
      {"status.warn", "#d29922"},
      {"status.fail", "#f85149"},
      {"status.busy", "#39c5cf"},
      {"bar", "#58a6ff"},
      {"track", "#8b949e"},
      {"address", "#8b949e"},
      {"percent", nil},
      {"key", "#d29922"},
      {"hint", "#8b949e"},
      {"time", "#8b949e"},
      {"message", nil},
      {"prompt", nil},
      {"cursor", nil}
    ]
  }

  # MB.
  @memory 16_384
  # When the memory test starts, and the seconds it takes.
  @mem_at 0.4
  @test 2
  @spin {"|", "/", "-", "\\"}
  @eighths {"░", "▏", "▎", "▍", "▌", "▋", "▊", "▉"}

  # Kernel lines: seconds since the previous line on the kernel's clock, then the text.
  @kernel [
    {0, "kernel 6.8.0 starting on 8 cpus"},
    {0, "command line: root=/dev/sda2 ro quiet"},
    {0.004, "memory: 16384 MB available, 412 MB reserved"},
    {0.077, "smp: brought up 1 node, 8 cpus"},
    {0.082, "pci: probing bus 0000:00"},
    {0.047, "pci 0000:00:17.0: sata controller, 6 ports"},
    {0.087, "usb 1-1: new high speed device, number 2"},
    {0.022, "usb 1-4: new full speed device, number 3"},
    {0.084, "sd 0:0:0:0: [sda] 1000215216 sectors (512 GB)"},
    {0.002, " sda: sda1 sda2"},
    {0.107, "eth0: link up, 1000 Mb/s, full duplex"},
    {0.129, "ext4: mounted sda2 read-only"},
    {0.062, "init: running /sbin/init"}
  ]

  # Service lines: seconds after the previous line, then the text. A third value
  # makes it a start job that spins that long before it lands. The last is the login.
  @services [
    {0.35, "[  OK  ] mounted root file system"},
    {0.12, "[  OK  ] started file system check on sda1"},
    {0.08, "[  OK  ] reached target local file systems"},
    {0.2, "[  OK  ] started journal service"},
    {0.1, "[  OK  ] started device manager"},
    {0.06, "[  OK  ] created runtime directories"},
    {0.15, "[  OK  ] started load kernel modules"},
    {0.25, "[ WARN ] clock not synced, using hardware time"},
    {0.2, "[  OK  ] started system logger"},
    {0.08, "[  OK  ] reached target sockets"},
    {0.1, "[  OK  ] reached target basic system"},
    {0.15, "[  OK  ] finished waiting for network", 2.6},
    {0.1, "[  OK  ] reached target network"},
    {0.25, "[  OK  ] synced clock to network time"},
    {0.1, "[  OK  ] started secure shell server"},
    {0.08, "[  OK  ] started job scheduler"},
    {0.1, "[  OK  ] started print spooler"},
    {0.3, "[  OK  ] reached target multi-user system"},
    {0.5, ""},
    {0.1, "node-1 login: "}
  ]

  # Seconds at the login prompt before the next boot.
  @wait 3.5

  @impl true
  def meta, do: @meta

  @impl true
  def size(%{cols: cols, rows: rows}), do: {trunc(cols), trunc(rows)}

  @impl true
  def init(options) do
    {cols, rows} = size(options)

    if log?(options),
      do: %{log: options.steps, title: options.title, cols: cols, rows: rows},
      else: boot(cols, rows)
  end

  # The app's own log, or upstream's boot.
  defp log?(%{steps: steps, title: title}), do: steps != [] or title != ""

  # Upstream's boot, the self test laid out to `w`, the text's width inside
  # a one-column margin.
  defp boot(cols, rows) do
    w = cols - 2
    rule = String.duplicate("─", w)

    {at, entries} =
      {0.12, []}
      |> put({:text, row(w, "system firmware 2.31.0", "", "self test")})
      |> step(0.04)
      |> put({:text, rule})
      |> step(0.04)
      |> put({:text, row(w, "cpu", "4 cores, 8 threads at 2.40 GHz", "ok")})
      |> step(0.04)
      |> put({:text, row(w, "cache", "l1 256 KB   l2 2 MB   l3 8 MB", "ok")})
      |> step(0.04)
      |> put({:memory, w})
      # The test's progress, the address it has reached, and a percentage.
      |> put({:bar, w})
      |> step(0.04)
      |> put({:text, row(w, "display", "1920 x 1080 at 60 Hz", "ok")})
      |> step(0.04)
      |> put({:probe, w, "storage", "sata 0: disk 0, 512 GB", "ok", 1.3})
      |> step(0.04)
      |> put({:probe, w, "usb", "2 controllers, 2 devices", "ok", 1.9})
      |> step(0.04)
      |> put({:probe, w, "network", "1 port, 1000 Mb/s", "link up", 2.2})
      |> step(0.04)
      |> put({:probe, w, "sensors", "cpu 41°C   board 33°C   fan 2400 rpm", "ok", 0.95})
      |> step(0.04)
      |> put({:text, row(w, "boot order", "disk 0, usb, network")})
      |> step(0.04)
      |> put({:text, rule})
      |> step(0.04)
      |> put({:text, "F2 setup    F12 boot menu    esc skip memory test"})
      |> then(fn {_, entries} -> {@mem_at + @test + 0.2, entries} end)
      |> put({:text, ""})
      |> step(0.05)
      |> put({:text, "booting from disk 0"})
      |> step(0.2)
      |> put({:text, "loading kernel 6.8.0 ..."})
      # The kernel's burst plays at two thirds speed so it reads as a fast scroll.
      |> step(0.3)
      |> kernel()
      |> services()

    login = at
    period = login + @wait

    # Frame 0 is the finished boot at the login prompt, a moment before it restarts.
    %{
      entries: Enum.reverse(entries),
      login: login,
      period: period,
      start: period - 0.25,
      cols: cols,
      rows: rows
    }
  end

  defp put({at, entries}, entry), do: {at, [{at, entry} | entries]}
  defp step({at, entries}, dt), do: {at + dt, entries}

  defp kernel(acc) do
    {acc, _, _} =
      Enum.reduce(@kernel, {acc, 0, Int32.to_int32(11)}, fn {gap, text}, {acc, stamp, rand} ->
        stamp = stamp + gap
        acc = step(acc, gap * 1.5)

        {s, rand} =
          if stamp != 0 do
            {r, rand} = Int32.mulberry32(rand)
            {stamp + r * 0.0009, rand}
          else
            {0, rand}
          end

        line = "[" <> Text.pad_start(JSMath.to_fixed(s, 6), 12) <> "] " <> text
        {put(acc, {:text, line}), stamp, rand}
      end)

    acc
  end

  defp services(acc) do
    Enum.reduce(@services, acc, fn
      {gap, text}, acc ->
        acc |> step(gap) |> put({:text, text})

      {gap, text, spin}, acc ->
        {at, _} = acc = step(acc, gap)
        acc |> put({:job, at, spin, text}) |> step(spin)
    end)
  end

  # A self test row: a label, its detail, and a status at the right edge.
  defp row(w, label, detail, status \\ "") do
    left = Text.pad_end(label, 11) <> detail
    left <> Text.pad_start(status, w - Text.length(left))
  end

  defp tested(now), do: min(1, max(0, (now - @mem_at) / @test))

  defp text({:text, s}, _now), do: s

  defp text({:memory, w}, now) do
    f = tested(now)
    mb = floor(f * @memory)

    row(
      w,
      "memory",
      Text.pad_start(Integer.to_string(mb), 5) <> " MB of #{@memory} MB",
      if(f < 1, do: "testing", else: "ok")
    )
  end

  defp text({:bar, w}, now) do
    f = tested(now)
    fill = f * 32
    full = floor(fill)
    part = if full < 32, do: elem(@eighths, floor((fill - full) * 8)), else: ""
    bar = Text.pad_end(String.duplicate("█", full) <> part, 32, "░")
    top = @memory * 1_048_576
    addr = if f < 1, do: floor(f * top / 4096) * 4096, else: top - 1
    hex = "0x" <> Text.pad_start(Integer.to_string(addr, 16), 9, "0")
    pct = Text.pad_start("#{floor(f * 100)}%", w - 56)
    String.duplicate(" ", 11) <> bar <> "  " <> hex <> pct
  end

  # A device probe spins until it resolves at `done`.
  defp text({:probe, w, label, detail, status, done}, now) when now >= done,
    do: row(w, label, detail, status)

  defp text({:probe, w, label, _detail, _status, done}, now),
    do: row(w, label, "detecting " <> elem(@spin, rem(floor((now + done) * 10), 4)))

  defp text({:job, from, spin, text}, now) do
    age = now - from

    if age >= spin do
      text
    else
      # Three stars sweep back and forth inside the brackets. The job shows
      # itself once it has run for 5s, so its clock starts there.
      "[" <> stars(age) <> "] a start job is running for network (#{floor(age + 5)}s / 1min 30s)"
    end
  end

  # Three stars sweeping back and forth inside a start job's brackets.
  defp stars(age) do
    k = Integer.mod(floor(age * 8), 6)
    p = if k < 4, do: k, else: 6 - k
    Text.pad_end(String.duplicate(" ", p) <> "***", 6)
  end

  @impl true
  def frame(%{log: _, cols: cols} = state, t, _env) do
    # The cursor blinks on the line after the last step, as at the login.
    cursor = if JSMath.mod(t, 1) < 0.6, do: "_", else: ""
    {head, body} = log_lines(state)

    body =
      Enum.map(body, fn
        {:step, status, text} -> status_text(status, t) <> text
        :cursor -> cursor
      end)

    out = for line <- head ++ body, do: (" " <> line) |> Text.pad_end(cols) |> Text.slice(0, cols)
    {Enum.intersperse(out, ?\n), nil, state}
  end

  def frame(%{entries: entries, login: login, period: period, start: start} = state, t, _env) do
    %{cols: cols, rows: rows} = state
    now = JSMath.mod(t + start, period)
    lines = for {at, e} <- entries, at <= now, do: text(e, now)

    # The cursor blinks after the login prompt, or at the top of the blank screen.
    lines =
      cond do
        now >= login ->
          cursor = if JSMath.mod(now - login, 1) < 0.6, do: "_", else: ""
          List.update_at(lines, -1, &(&1 <> cursor))

        lines == [] ->
          ["_"]

        true ->
          lines
      end

    n = length(lines)
    shown = Enum.drop(lines, max(0, n - rows)) ++ List.duplicate("", rows - min(n, rows))
    out = for line <- shown, do: (" " <> line) |> Text.pad_end(cols) |> Text.slice(0, cols)

    {Enum.intersperse(out, ?\n), nil, state}
  end

  # An app's log as lines: the title and its rule, which stay put, then the
  # steps and the cursor's line, the newest that fit, blank lines under
  # them until they fill the rows.
  defp log_lines(%{log: steps, title: title, cols: cols, rows: rows}) do
    head = if title == "", do: [], else: [title, String.duplicate("─", cols - 2)]

    body =
      Enum.map(steps, &{:step, Map.get(&1, :status, ""), Map.get(&1, :text, "")}) ++ [:cursor]

    room = rows - length(head)
    shown = Enum.take(body, -room)
    {head, shown ++ List.duplicate({:step, "", ""}, room - length(shown))}
  end

  # A step's status, in brackets as systemd prints it, or nothing.
  defp status_text("ok", _t), do: "[  OK  ] "
  defp status_text("warn", _t), do: "[ WARN ] "
  defp status_text("fail", _t), do: "[FAILED] "
  defp status_text("busy", t), do: "[" <> stars(t) <> "] "
  defp status_text(_status, _t), do: ""

  @impl true
  def describe(%{steps: [], title: ""}), do: nil

  def describe(%{steps: steps, title: title}) do
    name = if title == "", do: "boot log", else: title
    by = Enum.group_by(steps, &Map.get(&1, :status, ""), &Map.get(&1, :text, ""))

    counts =
      [
        {"ok", "ok", "ok"},
        {"warn", "warning", "warnings"},
        {"fail", "failed", "failed"},
        {"busy", "running", "running"}
      ]
      |> Enum.flat_map(fn {status, one, many} ->
        case Map.get(by, status, []) do
          [] -> []
          [first | _] = all -> [count(all, one, many) <> which(status, first)]
        end
      end)

    case steps do
      [] -> name <> ": no steps yet"
      _ -> Enum.join(["#{name}: #{count(steps, "step", "steps")}" | counts], ", ")
    end
  end

  defp count([_], one, _many), do: "1 " <> one
  defp count(list, _one, many), do: "#{length(list)} " <> many

  # The step a failure or a step under way is, as a reader would want it.
  defp which(status, text) when status in ["fail", "busy"] and text != "",
    do: " (" <> String.slice(text, 0, 40) <> ")"

  defp which(_status, _text), do: ""

  # This port's own: the parts of a frame. An app's log is labelled from
  # its steps, by where each sits; upstream's boot is read off its lines,
  # each of which is one of the few kinds the script prints, after a
  # one-column margin.

  @tested "cpu|cache|memory|display|storage|usb|network|sensors"
  @lines [
    {~r/^ (system firmware \S+)( +)(self test)( *)$/u, ["title", nil, "title"]},
    {~r/^ (─+)( *)$/u, ["rule"]},
    {~r/^ (#{@tested})( +)(.*?)( +)(ok|link up)( *)$/u,
     ["label", nil, "detail", nil, "status.ok"]},
    {~r/^ (memory)( +)(.*?)( +)(testing)( *)$/u, ["label", nil, "detail", nil, "status.busy"]},
    {~r/^ (#{@tested})( +)(detecting .)( *)$/u, ["label", nil, "status.busy"]},
    {~r/^ (boot order)( +)(.*?)( *)$/u, ["label", nil, "detail"]},
    {~r/^( +)([█▏▎▍▌▋▊▉]*)(░*)( +)(0x[0-9A-F]+)( +)(\d+%)( *)$/u,
     [nil, "bar", "track", nil, "address", nil, "percent"]},
    {~r/^ (F2)( setup +)(F12)( boot menu +)(esc)( skip memory test)( *)$/u,
     ["key", "hint", "key", "hint", "key", "hint"]},
    {~r/^ (\[ *\d+\.\d+\])( )(.*?)( *)$/u, ["time", nil, "message"]},
    {~r/^ (\[  OK  \])( )(.*?)( *)$/u, ["status.ok", nil, "message"]},
    {~r/^ (\[ WARN \])( )(.*?)( *)$/u, ["status.warn", nil, "message"]},
    {~r/^ (\[[ *]{6}\])( )(.*?)( *)$/u, ["status.busy", nil, "message"]},
    {~r/^ (\S+ login:)( )(_?)( *)$/u, ["prompt", nil, "cursor"]},
    {~r/^ (_)( *)$/u, ["cursor"]},
    {~r/^ (\S.*?)( *)$/u, ["message"]}
  ]

  @impl true
  def parts(%{lines: lines, cols: cols, rows: rows}, options) do
    if log?(options) do
      {head, body} =
        log_lines(%{log: options.steps, title: options.title, cols: cols, rows: rows})

      spans = Enum.zip_with(head, ["title", "rule"], &[{&2, &1}]) ++ Enum.map(body, &spans/1)
      Enum.zip_with(lines, spans, &cut(&1, [{nil, 1} | &2]))
    else
      Enum.map(lines, &Parts.first(&1, @lines))
    end
  end

  # A line's spans, as {part, its text or how many characters}.
  defp spans({:step, status, text}) do
    case status_text(status, 0) do
      "" -> [{"message", text}]
      _ -> [{"status." <> status, 8}, {nil, 1}, {"message", text}]
    end
  end

  defp spans(:cursor), do: [{"cursor", 1}]

  # A line cut into spans, each so many characters (or as long as its
  # text), the rest in no part; a cursor that blinked out is in none.
  defp cut(line, spans) do
    {runs, rest} =
      Enum.map_reduce(spans, line, fn {name, n}, rest ->
        n = if is_binary(n), do: Text.length(n), else: n
        {text, rest} = take(rest, n)
        {{if(name == "cursor" and text != "_", do: nil, else: name), text}, rest}
      end)

    Parts.merge(runs ++ [{nil, rest}])
  end

  defp take(s, n) do
    head = Text.slice(s, 0, n)
    {head, binary_part(s, byte_size(head), byte_size(s) - byte_size(head))}
  end
end
