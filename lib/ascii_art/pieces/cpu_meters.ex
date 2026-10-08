defmodule AsciiArt.Pieces.CpuMeters do
  @moduledoc """
  Htop-style core, memory and swap meters over a process list.

  The top of an htop screen. Eight cores split into user and kernel time,
  memory and swap bars, load and uptime, and the busiest processes.

  ## Options

  `commands` (upstream's) names the simulated processes. This port adds real
  readings for a dashboard or a terminal UI; each one given replaces that
  part of the simulation, and the rest plays on. Update them as they change
  (`AsciiArt.put_options/2`).

    * `cores` - each core's use, in percent: a meter each, in two columns.
      More than eight make the frame taller; up to 32.
    * `memory`, `swap` - `[used, total]`, in gigabytes.
    * `load` - the load averages, up to three.
    * `tasks` - the number of tasks.
    * `uptime` - seconds up at play time 0; it counts on as play goes.
    * `processes` - rows of `%{pid, user, cpu, mem, virt, res, time, state,
      command}` (cpu and mem in percent, virt and res in gigabytes, time in
      seconds; any may be left out), of which the five busiest are shown.

  Ported from `src/pieces/cpu-meters.ts` in bas3line/ascii (MIT).
  """
  @behaviour AsciiArt.Piece

  alias AsciiArt.{Int32, JSMath}
  alias AsciiArt.Kit.Text

  @meta %AsciiArt.Meta{
    name: "cpu meters",
    category: :data,
    note: "htop-style core, memory and swap meters over a process list",
    cols: 66,
    rows: 16,
    fps: 10,
    options: %{
      commands: ["build", "indexer", "server", "backup", "sync", "editor", "shell"],
      cores: [],
      memory: [],
      swap: [],
      load: [],
      tasks: nil,
      uptime: nil,
      processes: []
    },
    bounds: %{tasks: {0, 1_000_000}, uptime: {0, 1_000_000_000}},
    shapes: %{
      cores: [0.0],
      memory: [0.0],
      swap: [0.0],
      load: [0.0],
      processes: [
        %{
          pid: 0,
          user: "",
          cpu: 0.0,
          mem: 0.0,
          virt: 0.0,
          res: 0.0,
          time: 0.0,
          state: "",
          command: ""
        }
      ]
    }
  }

  @max_cores 32

  # Refreshes per second, like htop's delay; refreshes run before frame 0.
  @rate 2
  @warm 80
  @ncpu 8
  # Gigabytes.
  @mem 15.5
  @swap 2
  # One meter column, label and brackets included.
  @col 31
  # Seconds each load average spans.
  @spans [60, 300, 900]

  @compile {:inline, clamp: 3, next: 1}

  @impl true
  def meta, do: @meta

  @impl true
  def size(%{cores: cores}), do: {@meta.cols, max(@meta.rows, half(cores) + 12)}

  # Cores in the left column: upstream's eight make four.
  defp half([]), do: div(@ncpu, 2)
  defp half(cores), do: div(min(length(cores), @max_cores) + 1, 2)

  @impl true
  def init(%{commands: commands} = options) do
    fresh = reset(commands)
    # The machine after the warm-up, where every frame from t = 0 starts.
    warm = run(fresh, @warm)
    {_cols, rows} = size(options)
    given = Map.take(options, [:cores, :memory, :swap, :load, :tasks, :uptime, :processes])
    %{fresh: fresh, warm: warm, sim: warm, given: given, rows: rows, commands: commands}
  end

  # The simulation keeps playing under readings given, so taking new ones
  # up does not restart it.
  @impl true
  def update(state, options) do
    fresh = init(options)
    if options.commands == state.commands, do: %{fresh | sim: state.sim}, else: fresh
  end

  defp next(r), do: Int32.mulberry32(r)

  defp clamp(v, lo, hi), do: max(lo, min(hi, v))

  defp reset(commands) do
    # Each core's load is a background part plus one part per job, each easing to its target.
    {cores, r} =
      Enum.map_reduce(1..@ncpu, 1, fn _, r ->
        {a, r} = next(r)
        {%{u: 0.1, k: 0.02, idle: 0.03 + a * 0.14, base: 0.1, p0: 0, p1: 0}, r}
      end)

    {procs, r} =
      commands
      |> Enum.with_index()
      |> Enum.map_reduce(r, fn {cmd, i}, r ->
        {a, r} = next(r)
        {b, r} = next(r)
        {c, r} = next(r)
        {d, r} = next(r)
        {w, r} = next(r)

        {%{
           cmd: Text.slice(cmd, 0, 13),
           pid: 1000 + JSMath.floor(a * 48_000),
           user: if(rem(i, 3) == 2, do: "root", else: "app"),
           virt: 0.4 + b * 3.2,
           mem: 0.4 + c * 4,
           time: 20 + d * 3000,
           w: w,
           cpu: 0
         }, r}
      end)

    %{
      made: 0,
      r: r,
      cores: cores,
      # Two kinds of work that come and go, run by the first two commands.
      jobs: [%{who: 0, left: 0, load: 0, on: {}}, %{who: 1, left: 0, load: 0, on: {}}],
      mem: %{used: 4.6, buf: 0.31, cache: 5.2, swap: 0.13},
      load: [1.62, 1.24, 0.91],
      # How far each load average moves toward the busy count in one refresh.
      decay: Enum.map(@spans, &(1 - :math.exp(-1 / @rate / &1))),
      tasks: 141,
      procs: procs
    }
  end

  defp run(%{made: made} = sim, need) when made >= need, do: sim
  defp run(sim, need), do: sim |> step() |> Map.update!(:made, &(&1 + 1)) |> run(need)

  # Upstream rebuilds the machine from scratch when asked for an earlier refresh.
  defp fill(%{sim: %{made: made}} = state, need) when need < made do
    from = if need >= @warm, do: state.warm, else: state.fresh
    %{state | sim: run(from, need)}
  end

  defp fill(state, need), do: %{state | sim: run(state.sim, need)}

  # One refresh of the whole machine.
  defp step(sim) do
    # Now and then a job lands on some of the cores, works a while, and lets go.
    {jobs, r} = Enum.map_reduce(sim.jobs, sim.r, &job/2)
    {cores, {r, busy, s0, s1}} = cores(sim.cores, jobs, r)
    working = Enum.any?(jobs, &(&1.left != 0))
    {mem, r} = mem(sim.mem, working, r)

    load = Enum.zip_with(sim.load, sim.decay, &(&1 + (busy - &1) * &2))

    {a, r} = next(r)
    tasks = clamp(sim.tasks + JSMath.round((a - 0.5) * 2.2), 136, 149)

    # A job's process takes what the job does; the rest share the idle work.
    job_cpu = (0 + s0 + s1) * 100
    {procs, r} = procs(sim.procs, jobs, {busy, job_cpu, s0, s1}, r)

    %{
      sim
      | r: r,
        cores: cores,
        jobs: jobs,
        mem: mem,
        load: load,
        tasks: tasks,
        procs: procs
    }
  end

  defp job(%{left: left} = j, r) when left > 0, do: {%{j | left: left - 1}, r}

  defp job(j, r) do
    {x, r} = next(r)

    if x < elem({0.1, 0.06}, j.who) do
      {a, r} = next(r)
      {b, r} = next(r)
      load = 0.35 + b * 0.55

      {on, r} =
        Enum.map_reduce(1..@ncpu, r, fn _, r ->
          {c, r} = next(r)
          {c < 0.3 + load * 0.5, r}
        end)

      {%{j | left: 5 + JSMath.floor(a * 16), load: load, on: List.to_tuple(on)}, r}
    else
      {j, r}
    end
  end

  defp target(%{left: 0}, _i), do: 0
  defp target(%{on: on, load: load}, i), do: if(elem(on, i), do: load, else: 0)

  defp cores(cores, [j0, j1], r) do
    cores
    |> Enum.with_index()
    |> Enum.map_reduce({r, 0, 0, 0}, fn {c, i}, {r, busy, s0, s1} ->
      {x, r} = next(r)

      {idle, r} =
        if x < 0.06,
          do: with({y, r} <- next(r), do: {0.02 + y * 0.2, r}),
          else: {c.idle, r}

      base = c.base + (idle - c.base) * 0.6
      p0 = c.p0 + (target(j0, i) - c.p0) * 0.6
      p1 = c.p1 + (target(j1, i) - c.p1) * 0.6
      want = base + p0 + p1
      {a, r} = next(r)
      u = clamp(want + (a - 0.5) * 0.12, 0.004, 0.95)
      {b, r} = next(r)
      {d, r} = next(r)
      {e, r} = next(r)
      k = clamp(u * (0.1 + b * 0.22) + d * 0.015, 0, 0.97 + e * 0.03 - u)
      c = %{c | u: u, k: k, idle: idle, base: base, p0: p0, p1: p1}
      {c, {r, busy + (u + k), s0 + (u + k) * p0 / want, s1 + (u + k) * p1 / want}}
    end)
  end

  defp mem(mem, working, r) do
    {a, r} = next(r)

    used =
      clamp(
        mem.used + (4.4 + if(working, do: 2.6, else: 0) - mem.used) * 0.12 + (a - 0.5) * 0.05,
        3,
        9
      )

    {b, r} = next(r)
    buf = clamp(mem.buf + (b - 0.5) * 0.01, 0.25, 0.4)
    {c, r} = next(r)
    cache = clamp(mem.cache + (c - 0.45) * 0.03, 4, @mem - 0.4 - used - buf)
    {d, r} = next(r)
    swap = clamp(mem.swap + (d - 0.5) * 0.004, 0.11, 0.16)
    {%{used: used, buf: buf, cache: cache, swap: swap}, r}
  end

  defp procs(procs, jobs, {busy, job_cpu, s0, s1}, r) do
    {procs, {r, sw}} =
      Enum.map_reduce(procs, {r, 0}, fn p, {r, sw} ->
        {x, r} = next(r)
        w = clamp(p.w + (x - 0.5) * 0.3, 0.02, 1)
        {%{p | w: w}, {r, sw + w * w}}
      end)

    jobs = List.to_tuple(jobs)
    share = {s0, s1}

    procs
    |> Enum.with_index()
    |> Enum.map_reduce(r, fn {p, i}, r ->
      # The job run by this command, if any.
      n = if i < tuple_size(jobs), do: i, else: -1
      mine = n >= 0 and elem(jobs, n).left > 0
      extra = if n >= 0, do: elem(share, n) * 100, else: 0
      cpu = (busy * 100 - job_cpu) * 0.75 * p.w * p.w / sw + extra
      {y, r} = next(r)
      mem = clamp(p.mem + (y - 0.5) * 0.06 + if(mine, do: 0.05, else: -0.004), 0.2, 14)
      {%{p | cpu: cpu, mem: mem, time: p.time + cpu / 100 / @rate}, r}
    end)
  end

  # A meter: label, then stacked {fraction, glyph} parts, value text at the right inside.
  defp meter(label, parts, text) do
    inner = @col - 5

    {cells, at, _} =
      Enum.reduce(parts, {[], 0, 0}, fn {f, g}, {cells, at, acc} ->
        acc = acc + f
        stop = min(inner, JSMath.round(acc * inner))
        n = max(stop - at, 0)
        {[cells | List.duplicate(g, n)], at + n, acc}
      end)

    cells = IO.iodata_to_binary([cells | List.duplicate(" ", inner - at)])
    n = Text.length(text)
    cells = Text.slice(cells, 0, max(inner - n, 0)) <> Text.slice(text, max(n - inner, 0))
    Text.pad_start(label, 3) <> "[" <> cells <> "]"
  end

  defp human_size(gb) when gb < 0.98, do: JSMath.to_string(JSMath.round(gb * 1024)) <> "M"
  defp human_size(gb), do: JSMath.to_fixed(gb, if(gb < 10, do: 2, else: 1)) <> "G"

  defp cpu_time(s) do
    m = JSMath.floor(s / 60)
    sec = s - m * 60

    if m < 60 do
      "#{m}:" <> Text.pad_start(JSMath.to_fixed(sec, 2), 5, "0")
    else
      "#{div(m, 60)}h" <> pad2(rem(m, 60)) <> ":" <> pad2(JSMath.floor(sec))
    end
  end

  defp pad2(n), do: n |> JSMath.to_string() |> Text.pad_start(2, "0")

  defp row(pid, user, virt, res, s, cpu, mem, time, cmd) do
    Text.pad_end(
      " " <>
        Text.pad_start(pid, 5) <>
        " " <>
        Text.pad_end(user, 8) <>
        " " <>
        Text.pad_start(virt, 5) <>
        " " <>
        Text.pad_start(res, 5) <>
        " " <>
        s <>
        " " <>
        Text.pad_start(cpu, 5) <>
        " " <> Text.pad_start(mem, 4) <> " " <> Text.pad_start(time, 9) <> "  " <> cmd,
      @meta.cols
    )
  end

  defp fit(s), do: s |> Text.slice(0, @col) |> Text.pad_end(@col)

  @impl true
  def frame(state, t, _env) do
    %{cols: cols} = @meta
    rows = state.rows
    given = state.given
    state = fill(state, @warm + JSMath.floor(t * @rate))
    %{cores: cores, mem: mem, load: load, tasks: tasks, procs: procs} = state.sim
    blank = String.duplicate(" ", cols)
    cores = cores(given.cores, cores)

    meters =
      Enum.map(Enum.with_index(cores), fn {{u, k}, i} ->
        meter(
          Integer.to_string(i),
          [{u, "|"}, {k, "#"}],
          JSMath.to_fixed((u + k) * 100, 1) <> "%"
        )
      end)

    {left, right} = Enum.split(meters, half(given.cores))

    left = left ++ [memory(given.memory, mem), swap(given.swap, mem), ""]

    running = max(1, Enum.count(cores, fn {u, k} -> u + k > 0.45 end))
    tasks = given.tasks || tasks
    up = JSMath.floor(given.uptime || 4 * 86_400 + 3 * 3600 + 12 * 60 + 45) + JSMath.floor(t)
    hms = Enum.map_join([rem(div(up, 3600), 24), rem(div(up, 60), 60), rem(up, 60)], ":", &pad2/1)
    load = if given.load == [], do: load, else: Enum.take(given.load, 3)

    right =
      right ++
        [
          "Tasks: #{JSMath.floor(tasks)}, #{JSMath.floor(tasks) * 3 - 5} thr; #{running} running",
          "Load average: " <> Enum.map_join(load, " ", &JSMath.to_fixed(&1, 2)),
          "Uptime: #{div(up, 86_400)} days, " <> hms
        ]

    right = right ++ List.duplicate("", length(left) - length(right))
    meters = Enum.zip_with(left, right, &(" " <> fit(&1) <> "  " <> fit(&2) <> " "))
    header = row("PID", "USER", "VIRT", "RES", "S", "CPU%", "MEM%", "TIME+", "Command")
    top = top(given.processes, procs)

    lines = [blank] ++ meters ++ [blank, header] ++ top
    lines = lines ++ List.duplicate(blank, max(rows - length(lines), 0))
    {Enum.intersperse(lines, ?\n), nil, state}
  end

  # Each core's {user, kernel} share: the simulation's, or the use given.
  defp cores([], sim), do: Enum.map(sim, &{&1.u, &1.k})

  defp cores(given, _sim),
    do: given |> Enum.take(@max_cores) |> Enum.map(&{clamp(&1 / 100, 0, 1), 0})

  defp memory([used, total | _], _mem) when total > 0,
    do:
      meter(
        "Mem",
        [{clamp(used / total, 0, 1), "|"}],
        human_size(used) <> "/" <> human_size(total)
      )

  defp memory(_given, mem) do
    meter(
      "Mem",
      [{mem.used / @mem, "|"}, {mem.buf / @mem, "#"}, {mem.cache / @mem, "*"}],
      human_size(mem.used) <> "/" <> JSMath.to_string(@mem) <> "G"
    )
  end

  defp swap([used, total | _], _mem) when total > 0,
    do:
      meter(
        "Swp",
        [{clamp(used / total, 0, 1), "|"}],
        human_size(used) <> "/" <> human_size(total)
      )

  defp swap(_given, mem),
    do:
      meter(
        "Swp",
        [{mem.swap / @swap, "|"}],
        human_size(mem.swap) <> "/" <> JSMath.to_fixed(@swap, 2) <> "G"
      )

  # The five busiest processes: the simulation's, or those given.
  defp top([], procs) do
    procs
    |> Enum.sort_by(& &1.cpu, :desc)
    |> Enum.take(5)
    |> Enum.map(fn p ->
      row(
        Integer.to_string(p.pid),
        p.user,
        human_size(p.virt),
        human_size(p.mem / 100 * @mem),
        if(p.cpu > 30, do: "R", else: "S"),
        JSMath.to_fixed(p.cpu, 1),
        JSMath.to_fixed(p.mem, 1),
        cpu_time(p.time),
        p.cmd
      )
    end)
  end

  defp top(given, _procs) do
    given
    |> Enum.sort_by(&(Map.get(&1, :cpu) || 0), :desc)
    |> Enum.take(5)
    |> Enum.map(fn p ->
      cpu = Map.get(p, :cpu) || 0
      state = Map.get(p, :state) || if(cpu > 30, do: "R", else: "S")

      row(
        if(pid = Map.get(p, :pid), do: JSMath.to_string(pid), else: ""),
        p |> Map.get(:user, "") |> Text.slice(0, 8),
        if(v = Map.get(p, :virt), do: human_size(v), else: ""),
        if(r = Map.get(p, :res), do: human_size(r), else: ""),
        Text.slice(state, 0, 1),
        JSMath.to_fixed(cpu, 1),
        JSMath.to_fixed(Map.get(p, :mem) || 0, 1),
        if(time = Map.get(p, :time), do: cpu_time(time), else: ""),
        p |> Map.get(:command, "") |> Text.slice(0, 13)
      )
    end)
  end
end
